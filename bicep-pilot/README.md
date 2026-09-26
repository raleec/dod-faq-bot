# CACHEBOT — Bicep Skeleton

Infrastructure-as-Code for the DoD-region FAQ bot (Teams + Web) described in
`../DoD-FAQ-Bot-Architecture.docx`.

## What this deploys

| Module | Resource(s) | Notes |
|---|---|---|
| `network.bicep` | vNet (10.42.0.0/22), NSG, 3 subnets, 5 private DNS zones | Bring-your-own hub peering is out of scope |
| `monitoring.bicep` | Log Analytics + Application Insights | Workspace-based AI, private ingest |
| `keyvault.bicep` | Premium Key Vault + PE | RBAC-only, purge-protected |
| `aoai.bicep` | Cognitive Services (OpenAI) + `gpt-4o` + `text-embedding-3-large` deployments + PE | **Requires quota first** — see `../aoai-quota-request.md` |
| `aisearch.bicep` | AI Search Standard S1 + PE | Semantic ranker on |
| `vm.bicep` | Ubuntu 22.04 `Standard_D4s_v5` + system MI + AMA | Cloud-init installs Docker + Az CLI |
| `bot.bicep` | Azure Bot S1 + Teams + Direct Line channels | Requires Entra Gov app registration ID |
| `rbac.bicep` | Data-plane role assignments (VM MI → AOAI / Search / KV) | Least privilege |

## Prerequisites

1. **Azure Gov subscription** with contributor rights.
2. **AOAI quota granted** for `gpt-4o` and `text-embedding-3-large` in `usgovvirginia` (see the quota request draft).
3. **Entra Gov app registration** for the bot; note the App (client) ID.
4. **SSH public key** for the VM admin.

## Deploy

```bash
az cloud set --name AzureUSGovernment
az login
az account set --subscription <sub-id>

# One-shot: subscription-scope deployment creates the RG + all children.
az deployment sub create \
  --name faqbot-prd-$(date +%Y%m%d%H%M) \
  --location usgovvirginia \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters vmAdminSshPublicKey="$(cat ~/.ssh/id_rsa.pub)" \
  --parameters msaAppId=<bot-app-id> \
  --parameters keyVaultAdminObjectIds="[\"<your-obj-id>\"]"
```

## Post-deploy

- Configure the SharePoint Online indexer on the AI Search service (data plane, not ARM). Example script goes in `../deploy/configure-search.ps1`.
- Create the L2 semantic-cache index on the same AI Search service with `../deploy/configure-cache-index.ps1` (no new Azure resources — piggybacks on the S1 service).
- Provision the escalation surface (SharePoint list + optional Teams channel + Sites.Selected grant) with `../deploy/configure-escalation.ps1`. Feed the returned `ESCALATION_SITE_ID` / `ESCALATION_LIST_ID` (and optionally `TRIAGE_TEAM_ID`) into the orchestrator config in Key Vault.
- Push the orchestrator container image to an ACR and update `cloud-init.yml`. Orchestrator ships with L1 in-process LRU + L2 semantic cache enabled by default; tune via `CACHE_L1_TTL_SECONDS`, `CACHE_L2_TTL_SECONDS`, `CACHE_L2_SIMILARITY_MIN`, `CACHE_MAX_SENSITIVITY` in Key Vault.
- Publish the Teams manifest and the web-chat embed HTML.

## What this skeleton does NOT include (deliberate)

- Hub-and-spoke integration / ExpressRoute peering
- Azure Front Door / App Gateway (add if public web chat needs a WAF)
- ACR (assumed pre-existing enterprise registry)
- Backup / disaster-recovery replication
- CI/CD pipeline definitions (GitHub Actions / Azure DevOps)
