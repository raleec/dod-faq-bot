# =============================================================================
#  Provisions the escalation surface for the DoD FAQ Bot.
#  - Creates a SharePoint list "FAQ Escalations" on the target site
#  - Prints the site + list IDs needed to configure Sites.Selected on the bot
#  - Optionally creates the "FAQ Bot - Triage" private Teams channel
#
#  Prereqs
#    - PowerShell 7+
#    - Microsoft.Graph module (Install-Module Microsoft.Graph -Scope CurrentUser)
#    - Signed in with sufficient permissions in the DoD tenant
#      (Sites.FullControl.All for list creation; Group.ReadWrite.All to make
#       the Teams channel).
#    - Az CLI on AzureUSGovernment cloud if you plan to grant Sites.Selected
#      via the Graph app-role assignment later in this script.
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SiteUrl,                # e.g. https://<tenant>.sharepoint-mil.us/sites/faq
    [Parameter(Mandatory)] [string] $BotAppId,               # bot's Entra app registration (client) id
    [string] $ListName = 'FAQ Escalations',
    [string] $TriageTeamId,                                  # AAD group id of the Team hosting the triage channel
    [string] $TriageChannelName = 'FAQ Bot - Triage',
    [switch] $CreateTriageChannel,
    [switch] $GrantSitesSelected
)

$ErrorActionPreference = 'Stop'

# ---- 1. Connect to Graph on the DoD cloud --------------------------------
Write-Host "==> Connecting to Microsoft Graph (USGov DoD)..." -ForegroundColor Cyan
Connect-MgGraph -Environment USGovDoD -Scopes @(
    'Sites.FullControl.All'
    'Group.ReadWrite.All'
    'Application.ReadWrite.All'
) | Out-Null

# ---- 2. Resolve the SharePoint site --------------------------------------
Write-Host "==> Resolving site: $SiteUrl"
$hostAndPath = [Uri]$SiteUrl
$sitePath    = $hostAndPath.AbsolutePath.TrimEnd('/')
$site        = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.us/v1.0/sites/$($hostAndPath.Host):$sitePath"
Write-Host "    site id: $($site.id)" -ForegroundColor Green

# ---- 3. Create the list (idempotent) -------------------------------------
$existing = try {
    Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.us/v1.0/sites/$($site.id)/lists?`$filter=displayName eq '$ListName'"
} catch { $null }

if ($existing.value.Count -gt 0) {
    $list = $existing.value[0]
    Write-Host "==> List '$ListName' already exists (id: $($list.id)) - skipping create." -ForegroundColor Yellow
} else {
    Write-Host "==> Creating list '$ListName'..." -ForegroundColor Cyan
    $listBody = @{
        displayName = $ListName
        description = 'Escalations from the DoD FAQ Bot. One row per user report of a wrong or unanswered question.'
        list        = @{ template = 'genericList' }
        columns     = @(
            @{ name = 'UserUpn';         text          = @{} }
            @{ name = 'Channel';         text          = @{} }
            @{ name = 'Question';        text          = @{ allowMultipleLines = $true; textType = 'plain' } }
            @{ name = 'BotAnswer';       text          = @{ allowMultipleLines = $true; textType = 'plain' } }
            @{ name = 'RetrievedChunks'; text          = @{ allowMultipleLines = $true; textType = 'plain' } }
            @{ name = 'SourceUrls';      text          = @{ allowMultipleLines = $true; textType = 'plain' } }
            @{ name = 'ModelVersion';    text          = @{} }
            @{ name = 'PromptVersion';   text          = @{} }
            @{ name = 'Reason';          choice        = @{ choices = @('AnswerWrong','BotSaidUnknown','AnswerIncomplete','Other') } }
            @{ name = 'UserComment';     text          = @{ allowMultipleLines = $true; textType = 'plain' } }
            @{ name = 'Status';          choice        = @{ choices = @('New','InTriage','Resolved','NoAction') } }
            @{ name = 'TriageOwner';     text          = @{} }
            @{ name = 'ResolutionNotes'; text          = @{ allowMultipleLines = $true; textType = 'plain' } }
            @{ name = 'ConversationRef'; text          = @{} }
            @{ name = 'CorrelationId';   text          = @{} }
        )
    } | ConvertTo-Json -Depth 10
    $list = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.us/v1.0/sites/$($site.id)/lists" -Body $listBody -ContentType 'application/json'
    Write-Host "    list id: $($list.id)" -ForegroundColor Green
}

# ---- 4. (Optional) Create the triage Teams channel -----------------------
if ($CreateTriageChannel) {
    if (-not $TriageTeamId) { throw "-CreateTriageChannel requires -TriageTeamId (AAD group id of the Team)." }
    Write-Host "==> Ensuring Teams channel '$TriageChannelName' in team $TriageTeamId..." -ForegroundColor Cyan
    $existingCh = try {
        Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.us/v1.0/teams/$TriageTeamId/channels?`$filter=displayName eq '$TriageChannelName'"
    } catch { $null }
    if ($existingCh.value.Count -gt 0) {
        Write-Host "    channel already exists (id: $($existingCh.value[0].id))" -ForegroundColor Yellow
    } else {
        $chBody = @{ displayName = $TriageChannelName; membershipType = 'private'; description = 'Escalations from the DoD FAQ Bot.' } | ConvertTo-Json
        $ch = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.us/v1.0/teams/$TriageTeamId/channels" -Body $chBody -ContentType 'application/json'
        Write-Host "    channel id: $($ch.id)" -ForegroundColor Green
    }
}

# ---- 5. (Optional) Grant Sites.Selected on the list to the bot app -------
if ($GrantSitesSelected) {
    Write-Host "==> Granting Sites.Selected (write) on list '$ListName' to app $BotAppId..." -ForegroundColor Cyan
    $permBody = @{
        roles = @('write')
        grantedToIdentities = @(
            @{ application = @{ id = $BotAppId; displayName = 'DoD FAQ Bot' } }
        )
    } | ConvertTo-Json -Depth 5
    Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.us/v1.0/sites/$($site.id)/permissions" -Body $permBody -ContentType 'application/json' | Out-Null
    Write-Host "    granted." -ForegroundColor Green
}

# ---- 6. Summary ----------------------------------------------------------
Write-Host ""
Write-Host "=============== Escalation surface summary ===============" -ForegroundColor Cyan
Write-Host " Site id       : $($site.id)"
Write-Host " List id       : $($list.id)"
Write-Host " List URL      : $SiteUrl/Lists/$($list.displayName.Replace(' ',''))"
Write-Host " Bot app id    : $BotAppId"
if ($CreateTriageChannel) {
    Write-Host " Triage team   : $TriageTeamId"
    Write-Host " Channel name  : $TriageChannelName"
}
Write-Host "=========================================================="
Write-Host ""
Write-Host "Put these values into the orchestrator config (Key Vault):" -ForegroundColor Yellow
Write-Host " ESCALATION_SITE_ID       = $($site.id)"
Write-Host " ESCALATION_LIST_ID       = $($list.id)"
if ($CreateTriageChannel) {
    Write-Host " TRIAGE_TEAM_ID           = $TriageTeamId"
    Write-Host " TRIAGE_CHANNEL_NAME      = $TriageChannelName"
}
