using './main.bicep'

param workloadName = 'faqbot'
param env = 'prd'
param location = 'usgovvirginia'
param ownerTag = '<owner-email>'

param vmAdminUsername = 'azadmin'
// Populate via `az deployment sub create --parameters vmAdminSshPublicKey=@~/.ssh/id_rsa.pub`
param vmAdminSshPublicKey = '<paste-ssh-pub-key>'

param tenantId = ''  // defaults to subscription tenant if left blank

// AAD object IDs that should hold Key Vault Administrator (ops / break-glass).
param keyVaultAdminObjectIds = [
  // '00000000-0000-0000-0000-000000000000'
]
