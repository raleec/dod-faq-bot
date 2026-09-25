// Azure Bot Service + Teams channel + Direct Line (for web chat).
// The bot points at the orchestrator API endpoint (VM behind an internal
// load balancer or app gateway - configured post-deploy).

param workloadName string
param env string
param location string  // Bot Service is a global resource; use 'global'
param tenantId string
param appInsightsInstrumentationKey string
param tags object

@description('Fully-qualified endpoint URL of the orchestrator API (must be internet-reachable for Bot Framework).')
param botEndpoint string = 'https://REPLACE-ME.azure.us/api/messages'

@description('Microsoft App ID (Entra Gov app registration created out of band).')
param msaAppId string

var botName = 'bot-${workloadName}-${env}'

resource bot 'Microsoft.BotService/botServices@2022-09-15' = {
  name: botName
  location: location
  tags: tags
  sku: { name: 'S1' }
  kind: 'azurebot'
  properties: {
    displayName: 'DoD FAQ Bot (${env})'
    endpoint: botEndpoint
    msaAppId: msaAppId
    msaAppType: 'SingleTenant'
    msaAppTenantId: tenantId
    developerAppInsightKey: appInsightsInstrumentationKey
    disableLocalAuth: false
    publicNetworkAccess: 'Enabled'  // Bot Framework relay is internet-facing
  }
}

resource teamsChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: bot
  name: 'MsTeamsChannel'
  location: location
  properties: {
    channelName: 'MsTeamsChannel'
    properties: {
      isEnabled: true
      // In Azure Gov, Teams for GCC-H / DoD requires the appropriate deployment env
      deploymentEnvironment: 'FairfaxCommercialDeployment'
    }
  }
}

resource directLine 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: bot
  name: 'DirectLineChannel'
  location: location
  properties: {
    channelName: 'DirectLineChannel'
    properties: {
      sites: [
        {
          siteName: 'web-embed'
          isEnabled: true
          isV1Enabled: false
          isV3Enabled: true
          isSecureSiteEnabled: true
        }
      ]
    }
  }
}

output botName string = bot.name
