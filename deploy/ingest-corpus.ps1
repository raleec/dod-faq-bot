# dod-faq-bot\deploy\ingest-corpus.ps1
#
# Crack .txt / .md / .docx / .pdf under a corpus folder, chunk, embed, and push to faq-index.
#
# Cracker backends:
#   - .txt  / .md         : direct file read
#   - .docx               : System.IO.Packaging (WindowsBase, no external deps)
#   - .pdf                : Word COM automation (Word 2013+ can open PDF)
#
# The script skips (with a warning) any format for which no backend is available on this machine.

[CmdletBinding()]
param(
    [string]$ResourceGroup = 'rg-faqbot-pilot1-eastus2',
    [string]$AoaiAccount   = 'aoai-faqbot-pilot1-pbkgn5co6zxwe',
    [string]$AoaiEndpoint  = 'https://aoai-faqbot-pilot1-pbkgn5co6zxwe.openai.azure.com',
    [string]$EmbedDeploy   = 'text-embedding-3-large',
    [string]$SearchService = 'srch-faqbot-pilot1-pbkgn5co6zxwe',
    [string]$IndexName     = 'faq-index',
    [string]$CorpusPath    = (Join-Path $PSScriptRoot '..\sample-corpus'),
    [int]   $ChunkChars    = 2000,
    [int]   $OverlapChars  = 200,
    [string]$Category      = 'seed',
    [string]$AoaiKey       = $null,
    [string]$SearchKey     = $null,
    [string]$ApiVersion    = '2024-08-01-preview',
    [string]$SearchApiVer  = '2024-07-01'
)
$ErrorActionPreference = 'Stop'

# ---------------- Auth ----------------
if (-not $AoaiKey) {
    $tok = az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv
    if ([string]::IsNullOrWhiteSpace($tok)) { throw "Failed to get AAD token for AOAI" }
    $aoaiHeaders = @{ Authorization = "Bearer $tok"; 'Content-Type' = 'application/json' }
} else {
    $aoaiHeaders = @{ 'api-key' = $AoaiKey; 'Content-Type' = 'application/json' }
}
if (-not $SearchKey) {
    $SearchKey = az search admin-key show --service-name $SearchService -g $ResourceGroup --query primaryKey -o tsv
    if ([string]::IsNullOrWhiteSpace($SearchKey)) { throw "Failed to get Search admin key" }
}
$searchHeaders = @{ 'api-key' = $SearchKey; 'Content-Type' = 'application/json' }
$searchBase = "https://$SearchService.search.windows.net"

# ---------------- Crackers ----------------
Add-Type -AssemblyName WindowsBase

function Crack-Text {
    param([string]$Path)
    return (Get-Content -Path $Path -Raw)
}

function Crack-Docx {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'word/document.xml' } | Select-Object -First 1
        if (-not $entry) { return '' }
        $sr = New-Object IO.StreamReader($entry.Open())
        $xml = $sr.ReadToEnd()
        $sr.Close()
    } finally { $zip.Dispose() }

    $sb = New-Object Text.StringBuilder
    $doc = [xml]$xml
    $ns = New-Object Xml.XmlNamespaceManager($doc.NameTable)
    $ns.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main')
    foreach ($p in $doc.SelectNodes('//w:p', $ns)) {
        foreach ($t in $p.SelectNodes('.//w:t', $ns)) { [void]$sb.Append($t.InnerText) }
        [void]$sb.AppendLine()
    }
    return $sb.ToString().Trim()
}

$script:_word = $null
function Get-WordApp {
    if ($script:_word) { return $script:_word }
    try {
        $script:_word = New-Object -ComObject Word.Application
        $script:_word.Visible = $false
        $script:_word.DisplayAlerts = 0
        return $script:_word
    } catch { return $null }
}

function Ensure-PdfPig {
    $libDir  = Join-Path $PSScriptRoot 'lib'
    $mainDll = Join-Path $libDir 'UglyToad.PdfPig.dll'
    if (Test-Path $mainDll) { return $mainDll }
    Write-Host "  fetching PdfPig from NuGet..." -ForegroundColor DarkGray
    New-Item -ItemType Directory -Force -Path $libDir | Out-Null
    $tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), "pdfpig-$([Guid]::NewGuid().ToString('N')).zip")
    try {
        Invoke-WebRequest -Uri 'https://www.nuget.org/api/v2/package/PdfPig/0.1.9' -OutFile $tmp -UseBasicParsing
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
        try {
            $targetFolder = if ($PSVersionTable.PSVersion.Major -ge 7) { 'lib/net6.0/' } else { 'lib/net462/' }
            $wanted = @(
                'UglyToad.PdfPig.dll','UglyToad.PdfPig.Core.dll','UglyToad.PdfPig.Fonts.dll',
                'UglyToad.PdfPig.Tokenization.dll','UglyToad.PdfPig.Tokens.dll'
            )
            foreach ($name in $wanted) {
                $entry = $zip.Entries | Where-Object { $_.FullName -eq ($targetFolder + $name) } | Select-Object -First 1
                if (-not $entry) { throw "PdfPig: $name not found in $targetFolder" }
                $out = Join-Path $libDir $name
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $out, $true)
            }
        } finally { $zip.Dispose() }
    } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
    return $mainDll
}

function Crack-Pdf {
    param([string]$Path)
    $dll = Ensure-PdfPig
    $libDir = Split-Path $dll
    # Load dependencies first (order matters — Tokens, Tokenization, Core, Fonts, then PdfPig)
    foreach ($d in 'UglyToad.PdfPig.Tokens.dll','UglyToad.PdfPig.Tokenization.dll','UglyToad.PdfPig.Core.dll','UglyToad.PdfPig.Fonts.dll','UglyToad.PdfPig.dll') {
        try { Add-Type -Path (Join-Path $libDir $d) -ErrorAction SilentlyContinue } catch { }
    }
    $doc = [UglyToad.PdfPig.PdfDocument]::Open($Path)
    try {
        $sb = New-Object Text.StringBuilder
        foreach ($p in $doc.GetPages()) {
            [void]$sb.AppendLine($p.Text)
        }
    } finally { $doc.Dispose() }
    return $sb.ToString().Trim()
}

function Crack-Any {
    param([IO.FileInfo]$File)
    switch ($File.Extension.ToLowerInvariant()) {
        '.txt'      { return Crack-Text $File.FullName }
        '.md'       { return Crack-Text $File.FullName }
        '.markdown' { return Crack-Text $File.FullName }
        '.docx'     { return Crack-Docx $File.FullName }
        '.pdf'      { return Crack-Pdf  $File.FullName }
        default     {
            Write-Host ("  SKIP unsupported extension: {0}" -f $File.Name) -ForegroundColor Yellow
            return $null
        }
    }
}

# ---------------- Helpers ----------------
function Get-Embedding {
    param([string]$Text)
    $uri = "$AoaiEndpoint/openai/deployments/$EmbedDeploy/embeddings?api-version=$ApiVersion"
    $r = Invoke-RestMethod -Method POST -Uri $uri -Headers $aoaiHeaders -Body (@{ input = $Text } | ConvertTo-Json)
    return $r.data[0].embedding
}

function Split-Chunks {
    param([string]$Text, [int]$Size, [int]$Overlap)
    if ($Text.Length -le $Size) { return ,$Text }
    $chunks = @()
    $i = 0
    while ($i -lt $Text.Length) {
        $end = [Math]::Min($i + $Size, $Text.Length)
        $chunks += $Text.Substring($i, $end - $i)
        if ($end -eq $Text.Length) { break }
        $i = $end - $Overlap
    }
    return $chunks
}

function Get-TitleFrom {
    param([string]$Content, [string]$FileName)
    $first = ($Content -split "`r?`n" | Where-Object { $_ -match '\S' } | Select-Object -First 1)
    if ($first -match '^\s*Title\s*:\s*(.+)$') { return $Matches[1].Trim() }
    if ($first -and $first.Length -le 120)      { return $first.Trim() }
    return [IO.Path]::GetFileNameWithoutExtension($FileName)
}

# ---------------- Ingest ----------------
$exts = @('*.txt','*.md','*.markdown','*.docx','*.pdf')
$files = @()
foreach ($e in $exts) { $files += Get-ChildItem -Path $CorpusPath -Filter $e -File -Recurse -ErrorAction SilentlyContinue }
$files = $files | Sort-Object Name -Unique
Write-Host "Found $($files.Count) source file(s) in $CorpusPath"

$docs = New-Object System.Collections.Generic.List[object]
$totalChunks = 0
$skipped = 0
foreach ($f in $files) {
    try {
        $raw = Crack-Any -File $f
    } catch {
        Write-Host ("  ERROR cracking {0}: {1}" -f $f.Name, $_.Exception.Message) -ForegroundColor Red
        $skipped++; continue
    }
    if (-not $raw) { $skipped++; continue }
    $title  = Get-TitleFrom -Content $raw -FileName $f.Name
    $chunks = Split-Chunks -Text $raw -Size $ChunkChars -Overlap $OverlapChars
    $ci = 0
    foreach ($c in $chunks) {
        $embed = Get-Embedding -Text $c
        $safeName = [IO.Path]::GetFileNameWithoutExtension($f.Name) -replace '[^a-zA-Z0-9_-]','_'
        $docId = "{0}__c{1}" -f $safeName, $ci
        $docs.Add([ordered]@{
            '@search.action'  = 'mergeOrUpload'
            id                = $docId
            title             = $title
            content           = $c
            source            = $f.Name
            category          = $Category
            chunkIndex        = $ci
            contentVector     = $embed
        }) | Out-Null
        $ci++; $totalChunks++
    }
    Write-Host ("  {0} -> {1} chunk(s) [{2}]" -f $f.Name, $chunks.Count, $f.Extension)
}
Write-Host "Total chunks: $totalChunks   Skipped files: $skipped"

# Word COM cleanup
if ($script:_word) {
    try {
        $script:_word.Quit()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($script:_word) | Out-Null
        $script:_word = $null
    } catch { }
}

# ---------------- Upload ----------------
$batchSize = 20
for ($i = 0; $i -lt $docs.Count; $i += $batchSize) {
    $slice = $docs.GetRange($i, [Math]::Min($batchSize, $docs.Count - $i))
    $body = @{ value = $slice } | ConvertTo-Json -Depth 10 -Compress
    $uri = "$searchBase/indexes/$IndexName/docs/index?api-version=$SearchApiVer"
    $r = Invoke-RestMethod -Method POST -Uri $uri -Headers $searchHeaders -Body $body
    $ok = ($r.value | Where-Object { $_.status } | Measure-Object).Count
    Write-Host ("  batch {0}: {1} indexed" -f ([Math]::Floor($i/$batchSize)+1), $ok)
}

# ---------------- Verify ----------------
Start-Sleep -Seconds 3
$stat = Invoke-RestMethod -Method GET -Uri "$searchBase/indexes/$IndexName/stats?api-version=$SearchApiVer" -Headers $searchHeaders
Write-Host ("`nIndex '{0}': {1} documents, {2:N0} bytes" -f $IndexName, $stat.documentCount, $stat.storageSize)
