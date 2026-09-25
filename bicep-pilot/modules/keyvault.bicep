// Key Vault (Premium HSM-backed) with RBAC + private endpoint.
// Stores bot MSA secret, SharePoint client secret (if used), and any
// break-glass credentials.

param workloadName string
param env string
param location string
param tenantId string
param adminObjectIds array
param subnetIdPe string
param logAnalyticsWorkspaceId string
param tags object

var vaultName = 'kv-${workloadName}-${env}-${substring(uniqueString(resourceGroup().id), 0, 5)}'

resource kv 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: vaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenantId
    // COMMERCIAL PILOT: Standard SKU (no HSM) to keep cost + cleanup simple.
    // DoD variant uses 'premium' for HSM-backed keys.
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // Sub disallows disabling purge protection. Teardown must call `az keyvault purge`.
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// Grant Key Vault Administrator to break-glass admins
resource kvAdminAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for oid in adminObjectIds: {
  name: guid(kv.id, oid, 'kv-admin')
  scope: kv
  properties: {
    principalId: oid
    // Key Vault Administrator
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalType: 'User'
  }
}]

resource pe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${vaultName}'
  location: location
  tags: tags
  properties: {
    subnet: { id: subnetIdPe }
    privateLinkServiceConnections: [
      {
        name: 'plsc-kv'
        properties: {
          privateLinkServiceId: kv.id
          groupIds: [ 'vault' ]
        }
      }
    ]
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: kv
  name: 'diag-kv'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { categoryGroup: 'audit', enabled: true }
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

output vaultName string = kv.name
output vaultUri string = kv.properties.vaultUri
