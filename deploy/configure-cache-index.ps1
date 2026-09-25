# =============================================================================
#  Creates the L2 semantic-cache index (faq-cache) on the existing AI Search
#  service. Piggybacks on the S1 tier already provisioned by main.bicep - no
#  new Azure resources.
#
#  Prereqs
#    - PowerShell 7+, Az CLI on AzureUSGovernment cloud
#    - You are signed in with rights to call the AI Search data plane
#      (Search Service Contributor or admin key holder)
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SearchServiceName,   # e.g. srch-faqbot-prd-abcd
    [Parameter(Mandatory)] [string] $AdminKey,            # or use bearer auth if disableLocalAuth is on
    [string] $IndexName = 'faq-cache',
    [int]    $VectorDimensions = 3072                      # text-embedding-3-large
)

$ErrorActionPreference = 'Stop'
$endpoint = "https://$SearchServiceName.search.azure.us"

$indexBody = @{
    name = $IndexName
    fields = @(
        @{ name = 'id';                type = 'Edm.String';               key = $true; filterable = $true }
        @{ name = 'cacheKeyHash';      type = 'Edm.String';               filterable = $true }
        @{ name = 'question';          type = 'Edm.String';               searchable = $true }
        @{ name = 'answer';            type = 'Edm.String';               searchable = $false; retrievable = $true }
        @{ name = 'citations';         type = 'Collection(Edm.String)';   retrievable = $true }
        @{ name = 'retrievedChunkIds'; type = 'Collection(Edm.String)';   retrievable = $true }
        @{ name = 'sourceDocsVersion'; type = 'Edm.String';               filterable = $true }
        @{ name = 'promptVersion';     type = 'Edm.String';               filterable = $true }
        @{ name = 'modelVersion';      type = 'Edm.String';               filterable = $true }
        @{ name = 'createdAt';         type = 'Edm.DateTimeOffset';       filterable = $true; sortable = $true }
        @{ name = 'expiresAt';         type = 'Edm.DateTimeOffset';       filterable = $true; sortable = $true }
        @{ name = 'sensitivityLabel';  type = 'Edm.String';               filterable = $true }
        @{ name = 'hitCount';          type = 'Edm.Int32';                filterable = $true; sortable = $true }
        @{
            name = 'questionEmbedding'
            type = 'Collection(Edm.Single)'
            searchable = $true
            dimensions = $VectorDimensions
            vectorSearchProfile = 'faq-cache-hnsw'
        }
    )
    vectorSearch = @{
        algorithms = @(
            @{
                name = 'hnsw-default'
                kind = 'hnsw'
                hnswParameters = @{ metric = 'cosine'; m = 4; efConstruction = 400; efSearch = 500 }
            }
        )
        profiles = @(
            @{ name = 'faq-cache-hnsw'; algorithm = 'hnsw-default' }
        )
    }
} | ConvertTo-Json -Depth 10

Write-Host "==> Creating index '$IndexName' on $SearchServiceName ..." -ForegroundColor Cyan
Invoke-RestMethod `
    -Method PUT `
    -Uri  "$endpoint/indexes/$($IndexName)?api-version=2024-07-01" `
    -Headers @{ 'api-key' = $AdminKey; 'Content-Type' = 'application/json' } `
    -Body $indexBody | Out-Null
Write-Host "OK." -ForegroundColor Green

Write-Host ""
Write-Host "Orchestrator config (set in Key Vault):" -ForegroundColor Yellow
Write-Host "  CACHE_INDEX_NAME          = $IndexName"
Write-Host "  CACHE_L2_SIMILARITY_MIN   = 0.95"
Write-Host "  CACHE_L1_TTL_SECONDS      = 3600"
Write-Host "  CACHE_L2_TTL_SECONDS      = 86400"
Write-Host "  CACHE_MAX_SENSITIVITY     = Internal"
