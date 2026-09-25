// Orchestrator VM: Ubuntu 22.04 LTS, Standard_D4s_v5, system-assigned MI,
// Azure Monitor Agent, cloud-init installs Docker + pulls orchestrator image.

param workloadName string
param env string
param location string
param subnetIdApp string
param adminUsername string
@secure()
param adminSshPublicKey string
param logAnalyticsWorkspaceId string
param tags object

@description('VM size. COMMERCIAL PILOT default is D2s_v7 (2 vCPU / 8 GB) - only v7 is available in eastus2 sandbox. DoD design calls for D4s_v5.')
param vmSize string = 'Standard_D2s_v7'

var vmName = 'vm-${workloadName}-${env}'
var nicName = 'nic-${vmName}'
var osDiskName = 'osdisk-${vmName}'

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipcfg1'
        properties: {
          subnet: { id: subnetIdApp }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
      }
      customData: base64(loadTextContent('../cloud-init.yml'))
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: osDiskName
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
        diskSizeGB: 64
      }
    }
    networkProfile: {
      networkInterfaces: [ { id: nic.id } ]
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: { secureBootEnabled: true, vTpmEnabled: true }
    }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}

resource ama 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: vm
  name: 'AzureMonitorLinuxAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.29'
    autoUpgradeMinorVersion: true
    settings: { workspaceId: logAnalyticsWorkspaceId }
  }
}

output vmName string = vm.name
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output systemIdentityPrincipalId string = vm.identity.principalId
