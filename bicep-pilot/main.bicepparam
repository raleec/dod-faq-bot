// COMMERCIAL PILOT parameter file - not for DoD deploy.
// See ../bicep/main.bicepparam for the DoD variant.
//
// Populate the placeholders below before running:
//   az deployment sub create --location eastus2 \
//     --template-file main.bicep --parameters main.bicepparam

using './main.bicep'

param workloadName = 'faqbot'
param env = 'pilot1'
param location = 'eastus2'
param ownerTag = '<owner-email>'

// Microsoft App (MSA) AppId of the bot Entra app registration
// Create via: az ad app create --display-name faqbot-pilot1 --sign-in-audience AzureADMyOrg
param msaAppId = '<bot-msa-app-id>'

param vmAdminUsername = 'azadmin'
// Generate via: ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_faqpilot -N ''
param vmAdminSshPublicKey = '<paste-ssh-pub-key>'

// Sandbox tenant this deploys into. Leave blank to default to subscription tenant.
param tenantId = '<tenant-id>'

// AAD object IDs that receive Key Vault Administrator (ops / break-glass).
// Get yours via: az ad signed-in-user show --query id -o tsv
param keyVaultAdminObjectIds = [
  '<admin-object-id>'
]


