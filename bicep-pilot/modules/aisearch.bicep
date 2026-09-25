// Azure AI Search with optional private endpoint.
// PILOT: PE disabled by default; public network access enabled with key auth.
// DoD design keeps PE + AAD auth.

param workloadName string
param env string
param location string
param subnetIdPe string
param logAnalyticsWorkspaceId string
param tags object

@description('Search SKU. Pilot uses basic ($75/mo) to fit budget; DoD design uses standard.')
@allowed([ 'basic', 'standard', 'standard2', 'standard3' ])
param searchSku string = 'basic'

@description('Create a private endpoint for Search? Disable for pilot to allow deployment when Search capacity is constrained.')
param enablePrivateEndpoint bool = false

var serviceName = 'srch-${workloadName}-${env}-${uniqueString(resourceGroup().id)}'

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: serviceName
  location: location
  tags: tags
  sku: { name: searchSku }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: enablePrivateEndpoint ? 'disabled' : 'enabled'
    semanticSearch: searchSku == 'basic' ? 'disabled' : 'standard'
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    disableLocalAuth: false
    networkRuleSet: {
      ipRules: []
      bypass: 'AzureServices'
    }
  }
  identity: { type: 'SystemAssigned' }
}

resource pe 'Microsoft.Network/privateEndpoints@2024-05-01' = if (enablePrivateEndpoint) {
  name: 'pe-${serviceName}'
  location: location
  tags: tags
  properties: {
    subnet: { id: subnetIdPe }
    privateLinkServiceConnections: [
      {
        name: 'plsc-search'
        properties: {
          privateLinkServiceId: search.id
          groupIds: [ 'searchService' ]
        }
      }
    ]
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: search
  name: 'diag-search'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [ { categoryGroup: 'allLogs', enabled: true } ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

output serviceName string = search.name
output endpoint string = 'https://${search.name}.search.windows.net'
output principalId string = search.identity.principalId
