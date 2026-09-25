// Virtual network + subnets + NSGs + private DNS zones for private endpoints.
// Skeleton: hub-and-spoke integration and ExpressRoute peering are out of scope.

param workloadName string
param env string
param location string
param tags object

var vnetName = 'vnet-${workloadName}-${env}'

resource nsgApp 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${workloadName}-${env}-app'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowBotFrameworkInbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureBotService'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [ '10.42.0.0/22' ] }
    subnets: [
      {
        name: 'snet-app'
        properties: {
          addressPrefix: '10.42.0.0/24'
          networkSecurityGroup: { id: nsgApp.id }
          serviceEndpoints: []
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: '10.42.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-bastion'
        properties: {
          addressPrefix: '10.42.2.0/26'
        }
      }
    ]
  }
}

// Private DNS zones consumed by other modules (registered with the vnet)
var privateZoneNames = [
  'privatelink.openai.azure.us'
  'privatelink.search.azure.us'
  'privatelink.vaultcore.usgovcloudapi.net'
  'privatelink.blob.core.usgovcloudapi.net'
  'privatelink.monitor.azure.us'
]

resource privateZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zone in privateZoneNames: {
  name: zone
  location: 'global'
  tags: tags
}]

resource zoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zone, i) in privateZoneNames: {
  parent: privateZones[i]
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}]

output vnetId string = vnet.id
output appSubnetId string = '${vnet.id}/subnets/snet-app'
output peSubnetId string = '${vnet.id}/subnets/snet-pe'
output bastionSubnetId string = '${vnet.id}/subnets/snet-bastion'
