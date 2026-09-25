# dod-faq-bot\deploy\rag-query.ps1
# End-to-end RAG loop with two-layer cache.
#
# Flow:
#   1. L1 lookup: SHA256 of the normalized question against faq-cache.cacheKeyHash (filter, no embed).
#   2. On L1 miss: embed the question ONCE, then L2 semantic lookup against faq-cache.questionEmbedding (top-1 vector search, cosine >= threshold).
#   3. On L1+L2 miss: vector search faq-index -> gpt-4o with cited context -> answer -> write cache entry.
#
# Cache entries also validate promptVersion + modelVersion + expiresAt so we can safely change the system prompt or model
# without serving stale answers.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Question,
    [string]$ResourceGroup    = 'rg-faqbot-pilot1-eastus2',
    [string]$AoaiEndpoint     = 'https://aoai-faqbot-pilot1-pbkgn5co6zxwe.openai.azure.com',
    [string]$EmbedDeploy      = 'text-embedding-3-large',
    [string]$ChatDeploy       = 'gpt-4o',
    [string]$SearchService    = 'srch-faqbot-pilot1-pbkgn5co6zxwe',
    [string]$IndexName        = 'faq-index',
    [string]$CacheIndex       = 'faq-cache',
    [int]   $TopK             = 3,
    [switch]$Hybrid,
    [switch]$SkipCache,
    [int]   $CacheTtlHours    = 24,
    [double]$L2Threshold      = 0.92,
    [string]$PromptVersion    = 'v1',
    [string]$ApiVersion       = '2024-08-01-preview',
    [string]$SearchApiVer     = '2024-07-01'
)
$ErrorActionPreference = 'Stop'

# ---------- Auth ----------
$tok = az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv
if ([string]::IsNullOrWhiteSpace($tok)) { throw "Failed to get AAD token for AOAI" }
$aoaiH = @{ Authorization = "Bearer $tok"; 'Content-Type' = 'application/json' }

$searchKey = az search admin-key show --service-name $SearchService -g $ResourceGroup --query primaryKey -o tsv
$searchH   = @{ 'api-key' = $searchKey; 'Content-Type' = 'application/json' }
$searchBase = "https://$SearchService.search.windows.net"

# ---------- Helpers ----------
function Normalize-Question {
    param([string]$Q)
    ($Q.ToLowerInvariant() -replace '\s+', ' ').Trim() -replace '[^\p{L}\p{Nd}\s]', ''
}

function Get-QuestionHash {
    param([string]$Q)
    $bytes = [Text.Encoding]::UTF8.GetBytes((Normalize-Question $Q))
    $sha   = [Security.Cryptography.SHA256]::Create()
    $hash  = $sha.ComputeHash($bytes)
    ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-Embedding {
    param([string]$Text)
    $uri = "$AoaiEndpoint/openai/deployments/$EmbedDeploy/embeddings?api-version=$ApiVersion"
    $r = Invoke-RestMethod -Method POST -Uri $uri -Headers $aoaiH -Body (@{ input = $Text } | ConvertTo-Json)
    return $r.data[0].embedding
}

function Try-L1CacheHit {
    param([string]$Hash, [string]$ModelVer)
    $filter = "cacheKeyHash eq '$Hash' and expiresAt gt $(([DateTimeOffset]::UtcNow).ToString('o')) and promptVersion eq '$PromptVersion' and modelVersion eq '$ModelVer'"
    $body = @{ filter = $filter; top = 1; select = 'id,question,answer,citations,createdAt,hitCount' } | ConvertTo-Json -Compress
    $r = Invoke-RestMethod -Method POST -Uri "$searchBase/indexes/$CacheIndex/docs/search?api-version=$SearchApiVer" -Headers $searchH -Body $body
    if ($r.value.Count -gt 0) { return $r.value[0] }
    return $null
}

function Try-L2CacheHit {
    param([single[]]$Vec, [string]$ModelVer)
    $filter = "expiresAt gt $(([DateTimeOffset]::UtcNow).ToString('o')) and promptVersion eq '$PromptVersion' and modelVersion eq '$ModelVer'"
    $body = @{
        vectorQueries = @(@{ kind='vector'; vector=$Vec; fields='questionEmbedding'; k=1 })
        top    = 1
        filter = $filter
        select = 'id,question,answer,citations,createdAt,hitCount'
    } | ConvertTo-Json -Depth 10 -Compress
    $r = Invoke-RestMethod -Method POST -Uri "$searchBase/indexes/$CacheIndex/docs/search?api-version=$SearchApiVer" -Headers $searchH -Body $body
    if ($r.value.Count -gt 0) {
        $hit = $r.value[0]
        # Azure AI Search cosine vector score: @search.score = 1 / (2 - cosine_similarity)
        # Reverse: cosine = 2 - (1 / score)
        $cosine = 2.0 - (1.0 / $hit.'@search.score')
        Write-Host ("  L2 top-1 candidate: '{0}' cosine={1:N3} (threshold={2})" -f $hit.question, $cosine, $L2Threshold) -ForegroundColor DarkGray
        if ($cosine -ge $L2Threshold) { return $hit }
    }
    return $null
}

function Write-CacheEntry {
    param(
        [string]$Hash, [string]$Question, [single[]]$Vec, [string]$Answer,
        [string[]]$Citations, [string[]]$RetrievedChunkIds, [string]$ModelVer
    )
    $now = [DateTimeOffset]::UtcNow
    $exp = $now.AddHours($CacheTtlHours)
    $doc = [ordered]@{
        '@search.action'   = 'mergeOrUpload'
        id                 = [Guid]::NewGuid().ToString('N')
        cacheKeyHash       = $Hash
        question           = $Question
        answer             = $Answer
        citations          = $Citations
        retrievedChunkIds  = $RetrievedChunkIds
        sourceDocsVersion  = 'seed-2026-07-27'
        promptVersion      = $PromptVersion
        modelVersion       = $ModelVer
        createdAt          = $now.ToString('o')
        expiresAt          = $exp.ToString('o')
        sensitivityLabel   = 'unclassified'
        hitCount           = 0
        questionEmbedding  = $Vec
    }
    $body = @{ value = @($doc) } | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Method POST -Uri "$searchBase/indexes/$CacheIndex/docs/index?api-version=$SearchApiVer" -Headers $searchH -Body $body | Out-Null
}

function Bump-HitCount {
    param([string]$Id, [int]$Current)
    $doc = [ordered]@{ '@search.action' = 'merge'; id = $Id; hitCount = ($Current + 1) }
    $body = @{ value = @($doc) } | ConvertTo-Json -Depth 5 -Compress
    Invoke-RestMethod -Method POST -Uri "$searchBase/indexes/$CacheIndex/docs/index?api-version=$SearchApiVer" -Headers $searchH -Body $body | Out-Null
}

# ---------- Flow ----------
$modelVer = "$ChatDeploy+$EmbedDeploy"
$hash = Get-QuestionHash $Question
Write-Host "Q: $Question" -ForegroundColor White
Write-Host ("cacheKeyHash: {0}..." -f $hash.Substring(0, 12)) -ForegroundColor DarkGray

$cacheLayer = 'miss'
$cacheHit   = $null
$qVec       = $null

if (-not $SkipCache) {
    $cacheHit = Try-L1CacheHit -Hash $hash -ModelVer $modelVer
    if ($cacheHit) { $cacheLayer = 'L1' }
    else {
        $qVec = Get-Embedding -Text $Question
        $cacheHit = Try-L2CacheHit -Vec $qVec -ModelVer $modelVer
        if ($cacheHit) { $cacheLayer = 'L2' }
    }
}

if ($cacheHit) {
    Write-Host "`n=== $cacheLayer cache HIT (id=$($cacheHit.id), hitCount was $($cacheHit.hitCount), score=$($cacheHit.'@search.score')) ===" -ForegroundColor Magenta
    Bump-HitCount -Id $cacheHit.id -Current $cacheHit.hitCount
    Write-Host "`n=== Cached answer ===" -ForegroundColor Green
    Write-Host $cacheHit.answer
    Write-Host "`n(zero AOAI chat tokens billed on cache hit)" -ForegroundColor DarkGray
    return
}

Write-Host "`n=== Cache miss — running full RAG ===" -ForegroundColor Yellow

if (-not $qVec) { $qVec = Get-Embedding -Text $Question }

# Retrieve
$sBody = @{
    vectorQueries = @(@{ kind='vector'; vector=$qVec; fields='contentVector'; k=$TopK })
    select = 'id,title,content,source'
    top    = $TopK
}
if ($Hybrid) { $sBody.search = $Question }
$sBody = $sBody | ConvertTo-Json -Depth 10 -Compress

$sr = Invoke-RestMethod -Method POST `
    -Uri "$searchBase/indexes/$IndexName/docs/search?api-version=$SearchApiVer" `
    -Headers $searchH -Body $sBody

Write-Host "`n=== Top $TopK retrieved (hybrid=$($Hybrid.IsPresent)) ===" -ForegroundColor Cyan
$idx = 1
foreach ($h in $sr.value) {
    Write-Host ("  [{0}] {1}  (score={2:N3}, source={3})" -f $idx, $h.title, $h.'@search.score', $h.source)
    $idx++
}

$ctxParts = @()
$idx = 1
foreach ($h in $sr.value) {
    $ctxParts += ("[{0}] Title: {1}`nSource: {2}`n{3}" -f $idx, $h.title, $h.source, $h.content)
    $idx++
}
$context = $ctxParts -join "`n`n---`n`n"

$system = @"
You are a federal / Azure Government FAQ assistant. Answer ONLY from the CONTEXT below. Cite each factual sentence with the bracketed source number, e.g. [1]. If the context does not contain the answer, say so and suggest escalating to a human FAQ owner. Keep answers under 150 words.

CONTEXT:
$context
"@

$chatBody = @{
    messages    = @(@{ role='system'; content=$system }, @{ role='user'; content=$Question })
    temperature = 0.2
    max_tokens  = 400
} | ConvertTo-Json -Depth 10

$chatR = Invoke-RestMethod -Method POST `
    -Uri "$AoaiEndpoint/openai/deployments/$ChatDeploy/chat/completions?api-version=$ApiVersion" `
    -Headers $aoaiH -Body $chatBody

$answer = $chatR.choices[0].message.content

Write-Host "`n=== Grounded answer ===" -ForegroundColor Green
Write-Host $answer
Write-Host ""
Write-Host ("(usage: prompt={0} tokens, completion={1} tokens)" -f $chatR.usage.prompt_tokens, $chatR.usage.completion_tokens) -ForegroundColor DarkGray

# Write to cache for next time
if (-not $SkipCache) {
    $citations = @($sr.value | ForEach-Object { $_.source })
    $chunkIds  = @($sr.value | ForEach-Object { $_.id })
    try {
        Write-CacheEntry -Hash $hash -Question $Question -Vec $qVec -Answer $answer `
            -Citations $citations -RetrievedChunkIds $chunkIds -ModelVer $modelVer
        Write-Host "(cached; ttl ${CacheTtlHours}h)" -ForegroundColor DarkGray
    } catch {
        Write-Host "WARN: cache write failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
