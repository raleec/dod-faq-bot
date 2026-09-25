// Azure AI Search (Standard S1) with private endpoint + AAD auth.
// SharePoint Online indexer + data source are configured via the
// data plane (see deploy/configure-search.ps1) rather than ARM.

param workloadName string
param env string
param location string
param subnetIdPe string
param logAnalyticsWorkspaceId string
param tags object

var serviceName = 'srch-${workloadName}-${env}-${uniqueString(resourceGroup().id)}'

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: serviceName
  location: location
  tags: tags
  sku: { name: 'standard' }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'disabled'
    semanticSearch: 'standard'
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    disableLocalAuth: false  // keep API key path enabled for indexer; flip to true once bearer auth is proven
    networkRuleSet: {
      ipRules: []
      bypass: 'AzureServices'
    }
  }
  identity: { type: 'SystemAssigned' }
}

resource pe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
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
output endpoint string = 'https://${search.name}.search.azure.us'
output principalId string = search.identity.principalId
