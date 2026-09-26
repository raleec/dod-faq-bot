# =============================================================================
#  Tears down the commercial pilot deployment cleanly.
#
#  Order:
#    1. Delete resource group (all resources, incl. soft-delete-eligible ones).
#       Resources currently in the RG (post 2026-09-22 build-out):
#         - AOAI account + PE + gpt-4o + text-embedding-3-large deployments
#         - AI Search svc (cachebot-index + cachebot-cache indexes)
#         - Storage account, Key Vault (+ PE), Log Analytics + App Insights, vNet
#         - Bot Service resource + channels (Teams, Direct Line)
#         - VM (management jumpbox), MI, disk, NIC
#         - Container Registry (crfaqbotpilot1pbkgn5co6zxwe, Basic)
#         - Container Apps environment (cae-faqbot-pilot1) + orchestrator app
#           (ca-faqbot-orchestrator) — child of CAE, cascade-deleted with RG
#    2. Purge Cognitive Services (AOAI) soft-delete
#    3. Purge Key Vault soft-delete (purge protection is ON in the pilot -
#       must wait 7 days OR call purge as a Subscription Contributor)
#    4. Delete bot Entra app registration
#    5. Delete SSH key (optional)
#
#  Run when: pilot window closes (target: ~2026-09-28 for the 1-week pilot).
# =============================================================================
[CmdletBinding()]
param(
    [string] $ResourceGroup = 'rg-faqbot-pilot1-eastus2',
    [string] $Location = 'eastus2',
    [string] $BotAppId = '<bot-msa-app-id>',
    [switch] $KeepSshKey,
    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
Write-Host "=== CACHEBOT pilot teardown ===" -ForegroundColor Cyan
Write-Host "  ResourceGroup: $ResourceGroup"
Write-Host "  Location:      $Location"
Write-Host "  Bot AppId:     $BotAppId"
Write-Host "  WhatIf:        $WhatIf"
Write-Host ""

if ($WhatIf) { Write-Host "== WhatIf mode - no changes will be made ==" -ForegroundColor Yellow }

# --- 1. RG delete ---
$rgExists = az group exists -n $ResourceGroup
if ($rgExists -eq 'true') {
    Write-Host "[1/5] Deleting resource group '$ResourceGroup' (async)..." -ForegroundColor Yellow
    if (-not $WhatIf) { az group delete --name $ResourceGroup --yes --no-wait | Out-Null }
    Write-Host "      submitted."
} else {
    Write-Host "[1/5] Resource group '$ResourceGroup' does not exist - skipping."
}

# --- 2. Wait for RG delete then purge AOAI soft-delete ---
Write-Host "[2/5] Waiting for resource group deletion to complete..."
if (-not $WhatIf) {
    while ((az group exists -n $ResourceGroup) -eq 'true') { Start-Sleep -Seconds 30; Write-Host "      still deleting..." }
    Write-Host "      RG deleted."
}
Write-Host "      Purging AOAI soft-delete entries..." -ForegroundColor Yellow
$deletedAoais = az cognitiveservices account list-deleted --query "[?location=='$Location' && contains(name,'faqbot-pilot1')].name" -o tsv
foreach ($n in $deletedAoais) {
    Write-Host "      purging AOAI $n"
    if (-not $WhatIf) {
        try { az cognitiveservices account purge --location $Location --resource-group $ResourceGroup --name $n | Out-Null }
        catch { Write-Host "        purge failed: $($_.Exception.Message)" -ForegroundColor Red }
    }
}

# --- 3. Purge Key Vault soft-delete ---
Write-Host "[3/5] Purging Key Vault soft-delete entries..." -ForegroundColor Yellow
$deletedKvs = az keyvault list-deleted --query "[?properties.location=='$Location' && contains(name,'faqbot-pilot1')].name" -o tsv
foreach ($n in $deletedKvs) {
    Write-Host "      purging KV $n (purge protection was ON - this will fail until retention expires unless caller has Contributor)"
    if (-not $WhatIf) {
        try { az keyvault purge --name $n --location $Location | Out-Null; Write-Host "      OK" -ForegroundColor Green }
        catch { Write-Host "      purge failed: $($_.Exception.Message)" -ForegroundColor Red; Write-Host "      -> KV will auto-purge after 7 days (soft-delete retention). Re-run then if needed." -ForegroundColor Yellow }
    }
}

# --- 4. Bot Entra app registration ---
Write-Host "[4/5] Deleting bot Entra app registration $BotAppId..." -ForegroundColor Yellow
if (-not $WhatIf) {
    try { az ad app delete --id $BotAppId | Out-Null; Write-Host "      deleted." -ForegroundColor Green }
    catch { Write-Host "      delete failed: $($_.Exception.Message)" -ForegroundColor Red }
}

# --- 5. SSH key ---
if ($KeepSshKey) {
    Write-Host "[5/5] Keeping SSH key (--KeepSshKey)."
} else {
    Write-Host "[5/5] Removing SSH keypair..." -ForegroundColor Yellow
    $keyPath = "$env:USERPROFILE\.ssh\id_ed25519_faqpilot"
    if (Test-Path $keyPath) {
        if (-not $WhatIf) { Remove-Item $keyPath, "$keyPath.pub" -Force }
        Write-Host "      removed."
    } else { Write-Host "      not present." }
}

Write-Host ""
Write-Host "=== Teardown complete ===" -ForegroundColor Cyan
Write-Host "Verify no leftover charges: az resource list --tag workload=faqbot" -ForegroundColor Yellow
