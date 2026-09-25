// Grants VM system-assigned managed identity the least-privilege data-plane
// roles needed to call AOAI, AI Search, and Key Vault.

param vmPrincipalId string
param aoaiName string
param searchName string
param keyVaultName string

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = { name: aoaiName }
resource search 'Microsoft.Search/searchServices@2024-06-01-preview' existing = { name: searchName }
resource kv 'Microsoft.KeyVault/vaults@2024-11-01' existing = { name: keyVaultName }

// Cognitive Services OpenAI User (5e0bd9bd-7b93-4f28-af87-19fc36ad61bd)
resource aoaiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aoai.id, vmPrincipalId, 'openai-user')
  scope: aoai
  properties: {
    principalId: vmPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  }
}

// Search Index Data Reader (1407120a-92aa-4202-b7e9-c0e197c71c8f)
resource searchRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, vmPrincipalId, 'search-reader')
  scope: search
  properties: {
    principalId: vmPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1407120a-92aa-4202-b7e9-c0e197c71c8f')
  }
}

// Key Vault Secrets User (4633458b-17de-408a-b874-0445c86b69e6)
resource kvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, vmPrincipalId, 'kv-secret-user')
  scope: kv
  properties: {
    principalId: vmPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
  }
}
