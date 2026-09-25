// =========================================================================
//  DoD FAQ Bot - Root Bicep
//  Target: Azure Government (usgovvirginia / usgovarizona) - IL5 eligible
//  Deploys: vNet + PE, Key Vault, AOAI, AI Search, VM (orchestrator),
//           Azure Bot Service, Log Analytics + App Insights
// =========================================================================

targetScope = 'subscription'

@description('Short workload name used as a resource-name prefix (3-8 chars).')
@minLength(3)
@maxLength(8)
param workloadName string = 'faqbot'

@description('Deployment environment (dev, tst, prd).')
@allowed([ 'dev', 'tst', 'prd' ])
param env string = 'prd'

@description('Azure Government region.')
@allowed([ 'usgovvirginia', 'usgovarizona' ])
param location string = 'usgovvirginia'

@description('Owner / cost-center tag value.')
param ownerTag string = 'ralee.cook@microsoft.com'

@description('VM admin username for the orchestrator host.')
param vmAdminUsername string

@description('SSH public key for VM admin.')
@secure()
param vmAdminSshPublicKey string

@description('Azure AD tenant ID for Bot Service MSA app registration binding.')
param tenantId string = subscription().tenantId

@description('AAD object ID(s) permitted to read Key Vault secrets (ops/dev).')
param keyVaultAdminObjectIds array = []

var rgName = 'rg-${workloadName}-${env}-${location}'

var tags = {
  workload: workloadName
  environment: env
  owner: ownerTag
  dataClassification: 'CUI'
  complianceScope: 'DoD-IL5'
  costCenter: 'CAIP-FED'
}

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: rgName
  location: location
  tags: tags
}

module network 'modules/network.bicep' = {
  scope: rg
  name: 'network-deploy'
  params: {
    workloadName: workloadName
    env: env
    location: location
    tags: tags
  }
}

module monitoring 'modules/monitoring.bicep' = {
  scope: rg
  name: 'monitoring-deploy'
  params: {
    workloadName: workloadName
    env: env
    location: location
    tags: tags
  }
}

module keyvault 'modules/keyvault.bicep' = {
  scope: rg
  name: 'keyvault-deploy'
  params: {
    workloadName: workloadName
    env: env
    location: location
    tenantId: tenantId
    adminObjectIds: keyVaultAdminObjectIds
    subnetIdPe: network.outputs.peSubnetId
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    tags: tags
  }
}

module aoai 'modules/aoai.bicep' = {
  scope: rg
  name: 'aoai-deploy'
  params: {
    workloadName: workloadName
    env: env
    location: location
    subnetIdPe: network.outputs.peSubnetId
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    tags: tags
  }
}

module search 'modules/aisearch.bicep' = {
  scope: rg
  name: 'search-deploy'
  params: {
    workloadName: workloadName
    env: env
    location: location
    subnetIdPe: network.outputs.peSubnetId
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    tags: tags
  }
}

module vm 'modules/vm.bicep' = {
  scope: rg
  name: 'vm-deploy'
  params: {
    workloadName: workloadName
    env: env
    location: location
    subnetIdApp: network.outputs.appSubnetId
    adminUsername: vmAdminUsername
    adminSshPublicKey: vmAdminSshPublicKey
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    tags: tags
  }
}

module bot 'modules/bot.bicep' = {
  scope: rg
  name: 'bot-deploy'
  params: {
    workloadName: workloadName
    env: env
    location: 'global'  // Bot Service is a global resource; channels bind to Gov endpoints
    tenantId: tenantId
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
    tags: tags
  }
}

// =========================================================================
//  RBAC: give the VM managed identity access to AOAI, AI Search, Key Vault
// =========================================================================
module rbac 'modules/rbac.bicep' = {
  scope: rg
  name: 'rbac-deploy'
  params: {
    vmPrincipalId: vm.outputs.systemIdentityPrincipalId
    aoaiName: aoai.outputs.accountName
    searchName: search.outputs.serviceName
    keyVaultName: keyvault.outputs.vaultName
  }
}

output resourceGroupName string = rg.name
output aoaiEndpoint string = aoai.outputs.endpoint
output searchEndpoint string = search.outputs.endpoint
output keyVaultUri string = keyvault.outputs.vaultUri
output vmPrivateIp string = vm.outputs.privateIp
output botName string = bot.outputs.botName
