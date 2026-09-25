// Azure OpenAI (Government) with private endpoint + two model deployments.
// NOTE: quota for gpt-4o + text-embedding-3-large must be granted first
// (see aoai-quota-request.md).

param workloadName string
param env string
param location string
param subnetIdPe string
param logAnalyticsWorkspaceId string
param tags object

@description('TPM (tokens per minute) allocated to the chat model deployment.')
param chatTpm int = 240000

@description('TPM allocated to the embeddings deployment.')
param embeddingsTpm int = 120000

var accountName = 'aoai-${workloadName}-${env}-${uniqueString(resourceGroup().id)}'

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: accountName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: accountName
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true  // enforce AAD auth
    networkAcls: {
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
  identity: { type: 'SystemAssigned' }
}

resource chatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aoai
  name: 'gpt-4o'
  sku: {
    name: 'Standard'
    capacity: chatTpm / 1000  // capacity in TPM/1K
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-11-20'
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
    raiPolicyName: 'Microsoft.Default'
  }
}

resource embedDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aoai
  name: 'text-embedding-3-large'
  dependsOn: [ chatDeployment ]  // serialise to avoid 429 on parent
  sku: {
    name: 'Standard'
    capacity: embeddingsTpm / 1000
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-large'
      version: '1'
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
    raiPolicyName: 'Microsoft.Default'
  }
}

// Private endpoint
resource pe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${accountName}'
  location: location
  tags: tags
  properties: {
    subnet: { id: subnetIdPe }
    privateLinkServiceConnections: [
      {
        name: 'plsc-aoai'
        properties: {
          privateLinkServiceId: aoai.id
          groupIds: [ 'account' ]
        }
      }
    ]
  }
}

// Diagnostics
resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: aoai
  name: 'diag-aoai'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { categoryGroup: 'audit', enabled: true }
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

output accountName string = aoai.name
output endpoint string = aoai.properties.endpoint
output principalId string = aoai.identity.principalId
