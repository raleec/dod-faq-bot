# DoD FAQ Bot — Pilot Deployment Runbook

> **Scope:** Commercial-cloud proof-of-pattern of the DoD FAQ-bot architecture,
> deployed into the MngEnvMCAP217858 sandbox subscription. **NOT** an IL5
> production deployment. The DoD variant of the Bicep (see `bicep/`) is
> preserved untouched for the actual customer engagement.

**Executed by:** Ralee Cook (`admin@MngEnvMCAP217858.onmicrosoft.com`)
**Executed on:** 2026-09-21
**Region:** eastus2
**Resource group:** `rg-faqbot-pilot1-eastus2`
**Budget cap:** $250 · **Planned lifetime:** ~1 week

---

## 0. Prereqs (verified)

| Tool | Version | OK |
|---|---|---|
| Azure CLI | current | ✅ |
| Bicep | current | ✅ |
| PowerShell | 7.x | ✅ |
| Node.js | v22.15 | ✅ |
| Active cloud | AzureCloud (Commercial) | ✅ |
| Subscription | `<subscription-name>` (`<subscription-id>`) | ✅ |
| Tenant | `<tenant-id>` | ✅ |

---

## 1. Adapt Bicep from DoD → Commercial pilot

The DoD Bicep in `bicep/` was copied to `bicep-pilot/` and the following
surgical changes made:

| File | Change |
|---|---|
| `main.bicep` | region `usgovvirginia` → `eastus2`; env allowed-list widened; `msaAppId` promoted to top-level parameter; tags `CUI` / `DoD-IL5` → `General` / `Pilot-Commercial` |
| `modules/network.bicep` | Private-DNS zones: `.openai.azure.us` → `.openai.azure.com`; `.search.azure.us` → `.search.windows.net`; `.vaultcore.usgovcloudapi.net` → `.vaultcore.azure.net`; `.blob.core.usgovcloudapi.net` → `.blob.core.windows.net`; `.monitor.azure.us` → `.monitor.azure.com` |
| `modules/bot.bicep` | Removed `deploymentEnvironment: 'FairfaxCommercialDeployment'` from the Teams channel (DoD-only setting) |
| `modules/aisearch.bicep` | Endpoint output suffix `.search.azure.us` → `.search.windows.net` |
| `modules/aoai.bicep` | Chat TPM `240k` → `100k` (sub quota in eastus2 is 150 kTPM); embeddings `120k` → `100k` |
| `modules/keyvault.bicep` | Premium → Standard; purge protection off; soft-delete retention 90 → 7 days (pilot only) |
| `modules/vm.bicep` | `Standard_D4s_v5` → `Standard_D2s_v7` (v5 not available in eastus2 sandbox; downshift also protects budget) |
| `cloud-init.yml` | `AzureUSGovernment` → `AzureCloud`; endpoint placeholders updated |

---

## 2. Sign in to sandbox tenant

The Az CLI SSO auto-picked the `@microsoft.com` corp identity (not a member of
the sandbox tenant). Solved with device-code flow.

```powershell
az logout
az account clear
az login --tenant <tenant-id> --use-device-code
# Sign in as your sandbox admin (e.g. admin@<sandbox-tenant>.onmicrosoft.com)
az account set --subscription <subscription-id>
```

---

## 3. Register resource providers

```powershell
foreach ($rp in 'Microsoft.CognitiveServices','Microsoft.Search',
                'Microsoft.BotService','Microsoft.KeyVault',
                'Microsoft.OperationalInsights','Microsoft.Insights',
                'Microsoft.Compute','Microsoft.Network') {
    az provider register -n $rp
}
```

All eight registered.

---

## 4. Capture identities and secrets

**Signed-in user object ID** (for Key Vault Admin RBAC):
```powershell
az ad signed-in-user show --query id -o tsv
# <admin-object-id>
```

**Bot Entra app registration:**
```powershell
az ad app create --display-name faqbot-pilot1 --sign-in-audience AzureADMyOrg
az ad sp create --id <appId>
az ad app credential reset --id <appId> --years 2 --display-name faqbot-pilot1-secret
```

- **App ID (`msaAppId`):** `<bot-msa-app-id>`
- **Secret:** stored at `%USERPROFILE%\.copilot\session-state\<session>\files\bot-app-registration.json`

**SSH keypair** (VM admin):
```powershell
ssh-keygen -t ed25519 -f $HOME\.ssh\id_ed25519_faqpilot -N '""' -C faqbot-pilot1
```
- Private key: `%USERPROFILE%\.ssh\id_ed25519_faqpilot`
- Public key: `%USERPROFILE%\.ssh\id_ed25519_faqpilot.pub`

---

## 5. Confirm AOAI quota

```powershell
az cognitiveservices usage list --location eastus2
```

Available in `eastus2` at pilot start:

| Model | Available (kTPM) | Requested (kTPM) |
|---|---|---|
| `Standard.gpt-4o` | 150 | 100 ✅ |
| `Standard.text-embedding-3-large` | 320 | 100 ✅ |

(No quota request needed for the pilot. DoD deploy will need the intake form
in `aoai-quota-request.md`.)

---

## 6. Populate parameter file

`bicep-pilot/main.bicepparam` was updated with real values. Final contents
committed alongside this runbook.

---

## 7. Build + what-if

```powershell
cd bicep-pilot
az bicep build --file main.bicep
az deployment sub what-if --location eastus2 `
    --template-file main.bicep --parameters main.bicepparam `
    --result-format ResourceIdOnly
```

Preview: **33 create + 3 dependent role assignments** across:

- 1 RG (`rg-faqbot-pilot1-eastus2`)
- 1 vNet + 3 subnets + 1 NSG + 5 private DNS zones + vnet-links
- 3 private endpoints (AOAI, AI Search, Key Vault)
- 1 Log Analytics workspace + 1 App Insights component
- 1 Key Vault (Standard)
- 1 AOAI account + 2 model deployments + diag
- 1 AI Search service (S1) + diag
- 1 Linux VM + NIC + AMA extension
- 1 Azure Bot + Teams channel + Direct Line channel
- 3 role assignments (VM MI → AOAI User / Search Reader / KV Secrets User)

---

## 8. Deploy

Six deployment attempts were needed to reach a green build. All six landed
under the same resource group; ARM incremental mode meant every retry
preserved successful modules.

| # | Deployment name | Result | Root cause / fix |
|---|---|---|---|
| 1 | `faqbot-pilot1-20260921-110716` | ❌ | KV name overflow (30 chars > 24). Race on AOAI PE (account in `Accepted` state). Search out of capacity in eastus2. |
| 2 | `faqbot-pilot1-20260921-111313` | ❌ | KV name shortened via `substring(uniqueString,0,5)`. KV creation rejected `enablePurgeProtection: false` (subscription default appears to force ON). AOAI PE race persists. Search still no capacity. |
| 3 | `faqbot-pilot1-20260921-111916` | ❌ | KV switched to `enablePurgeProtection: true`. Search moved to `eastus` (had capacity). PE for Search failed: cross-region PE not supported for `Microsoft.Search`. |
| 4 | `faqbot-pilot1-20260921-113407` | ❌ | Search moved back to `eastus2`, SKU downshifted `standard` → `basic` hoping different capacity pool. Still `InsufficientResourcesAvailable`. |
| 5 | `faqbot-pilot1-20260921-114441` | ❌ | Deleted stale eastus Search service. Redeploy hit same eastus2 capacity ceiling. |
| 6 | `faqbot-pilot1-20260921-115418` | ✅ | Made Search PE conditional (`enablePrivateEndpoint: false`), moved Search to `eastus`, kept `basic` SKU. **All 8 modules Succeeded.** |

```powershell
cd bicep-pilot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
az deployment sub create --name "faqbot-pilot1-$stamp" `
    --location eastus2 --template-file main.bicep `
    --parameters main.bicepparam
```

**Final Bicep delta vs original DoD design (for the pilot only):**

- `bicep-pilot/main.bicep`: added `searchLocation` (defaults `eastus`); wired `msaAppId` to Bot module
- `bicep-pilot/modules/keyvault.bicep`: name shortened; purge protection ON; soft-delete retention 7 days
- `bicep-pilot/modules/aisearch.bicep`: `basic` SKU; `enablePrivateEndpoint` flag defaulting to false; semantic search disabled (basic tier constraint)
- `bicep-pilot/modules/vm.bicep`: `Standard_D2s_v7` (only v-series available in the sandbox)
- `bicep-pilot/modules/aoai.bicep`: TPMs 100k / 100k (fits sub quota of 150 kTPM chat / 350 kTPM embed)

---

## 9. Post-deploy configuration

### 9a. L2 semantic cache index

The pilot deploys a **second AI Search index** on the same Basic service — no
extra Azure resource, just data-plane config. Both the L1 (exact-hash) and L2
(vector) cache lookups target this index.

```powershell
$searchName = 'srch-faqbot-pilot1-pbkgn5co6zxwe'
$rg = 'rg-faqbot-pilot1-eastus2'
$adminKey = az search admin-key show --service-name $searchName -g $rg --query primaryKey -o tsv
$endpoint = "https://$searchName.search.windows.net"

$indexBody = @{
    name = 'faq-cache'
    fields = @(
        @{ name='id';                type='Edm.String';         key=$true;  filterable=$true }
        @{ name='cacheKeyHash';      type='Edm.String';         filterable=$true }               # L1 SHA-256 lookup
        @{ name='question';          type='Edm.String';         searchable=$true }               # debug / audit
        @{ name='answer';            type='Edm.String';         retrievable=$true }
        @{ name='citations';         type='Collection(Edm.String)'; retrievable=$true }
        @{ name='retrievedChunkIds'; type='Collection(Edm.String)'; retrievable=$true }
        @{ name='sourceDocsVersion'; type='Edm.String';         filterable=$true }               # invalidate on reindex
        @{ name='promptVersion';     type='Edm.String';         filterable=$true }               # invalidate on prompt rev
        @{ name='modelVersion';      type='Edm.String';         filterable=$true }               # invalidate on model rev
        @{ name='sensitivityLabel';  type='Edm.String';         filterable=$true }               # e.g. unclassified / cui
        @{ name='hitCount';          type='Edm.Int32';          retrievable=$true }
        @{ name='createdAt';         type='Edm.DateTimeOffset'; filterable=$true; sortable=$true }
        @{ name='expiresAt';         type='Edm.DateTimeOffset'; filterable=$true }               # TTL enforcement
        @{ name='questionEmbedding'; type='Collection(Edm.Single)';
          dimensions=3072; vectorSearchProfile='faq-cache-hnsw' }                                # L2 vector field
    )
    vectorSearch = @{
        algorithms = @(@{ name='hnsw-cosine'; kind='hnsw';
                          hnswParameters=@{ metric='cosine'; m=4; efConstruction=400; efSearch=500 } })
        profiles   = @(@{ name='faq-cache-hnsw'; algorithm='hnsw-cosine' })
    }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Method PUT `
  -Uri  "$endpoint/indexes/faq-cache?api-version=2024-07-01" `
  -Headers @{ 'api-key' = $adminKey; 'Content-Type' = 'application/json' } `
  -Body $indexBody
```

Result: index `faq-cache` created — **14 fields, `faq-cache-hnsw` HNSW / cosine profile**.

**Runtime behavior** (mirrored between `orchestrator/rag.py` and `deploy/rag-query.ps1`):

1. **L1 lookup** — POST `docs/search` with `filter=cacheKeyHash eq '<sha>' and expiresAt gt <now> and promptVersion eq '<v>' and modelVersion eq '<m>'`. Sub-second, no embed cost. On hit: bump `hitCount` via `merge`, return the cached answer.
2. **Miss → embed** the question with `text-embedding-3-large` (3072-d).
3. **L2 lookup** — POST `docs/search` with a `vectorQueries` block against `questionEmbedding` (k=1) + the same filter as L1. Azure AI Search returns `@search.score = 1 / (2 - cosine)`; the code inverts back to raw cosine and compares to `L2_THRESHOLD` (default `0.85`). Empirically the useful range for `text-embedding-3-large` is `0.82–0.88`; the industry-default `0.92` almost never fires on this model.
4. **Miss → RAG** — full retrieval on `faq-index` + chat completion, then **write the answer back** to `faq-cache` with a fresh `id`, `cacheKeyHash`, `questionEmbedding`, `createdAt`, and `expiresAt = now + CACHE_TTL_HOURS`.

**Invalidation** is baked into the filter clause — no purge job needed:

| Change | Bump | Effect |
|---|---|---|
| System prompt | `PROMPT_VERSION` env / `-PromptVersion` param | Prior entries become invisible to the filter and are eventually reaped by TTL |
| Model swap | `modelVersion` (auto-derived from AOAI deployment) | Same |
| Corpus reindex | `SOURCE_DOCS_VERSION` env | Same |
| Emergency purge | Manual DELETE on `faq-cache` docs, or delete + recreate the index | Instant |

The full standalone body lives in `deploy/configure-cache-index.ps1` — that
script hardcodes the DoD `*.search.azure.us` suffix, so the block above is the
commercial variant used for the pilot.

### 9b. Escalation surface

Escalation SharePoint list + Teams channel: **not run** for the pilot smoke
test (Graph `Sites.Selected` + `ChannelMessage.Send.Group` admin consent
requires tenant-level global admin approval and isn't needed to prove infra
health). The `deploy/configure-escalation.ps1` script is ready to run when
the pilot moves to a live-chat proof.

---

## 10. Smoke test

Ran on 2026-09-21 after deploy 6 completed. See `SMOKE-TEST.md` for the full
result matrix.

**Summary: 24 / 24 passed.** All resources exist, both AOAI model deployments
are `Succeeded`, both private endpoints resolve, VM is running with AMA
extension, Bot has Teams + Direct Line channels, and the VM's system-assigned
managed identity holds all three least-privilege data-plane roles.

Live inference through the bot is **not** part of the smoke test — the
orchestrator container image is not yet built or deployed onto the VM. That's
the next milestone if the pilot moves to a live-chat proof.

---

## 11. Teardown

Pilot lifetime: ~1 week from 2026-09-21. Teardown script committed at
`deploy/teardown-pilot.ps1`:

```powershell
# From the workspace root
cd 'C:\Users\raleecook\OneDrive - Microsoft\Documents\Microsoft Scout\dod-faq-bot'

# Dry run first
.\deploy\teardown-pilot.ps1 -WhatIf

# Then for real
.\deploy\teardown-pilot.ps1
```

The script:

1. `az group delete --name rg-faqbot-pilot1-eastus2 --yes --no-wait`
2. Waits for RG deletion, then purges AOAI soft-delete
3. Purges Key Vault soft-delete (may fail if the sub's Contributor role
   doesn't allow purge with purge-protection ON — in that case the KV auto-
   purges after 7 days)
4. Deletes bot Entra app registration `<bot-msa-app-id>`
5. Deletes the `id_ed25519_faqpilot` SSH keypair (skip with `-KeepSshKey`)

**Estimated cost while running:** ~$3-4/day burn rate (Bot S1 $1.60/day +
VM D2s_v7 $2/day + Search basic $2.50/day + storage/AMA/LAW ~$0.30/day). Over
a full 7-day window, expect ~$40-50 — well under the $250 cap.

---

## Appendix: Session artifacts

- `bicep-pilot/` — pilot Bicep templates (this variant deployed successfully)
- `bicep/` — original DoD Bicep (untouched; ready for customer engagement)
- `deploy/configure-cache-index.ps1` — DoD-endpoint variant (rewrite for commercial pilot inlined above)
- `deploy/configure-escalation.ps1` — SharePoint + Teams triage config (unused in pilot smoke)
- `deploy/teardown-pilot.ps1` — teardown script
- `SMOKE-TEST.md` — pass/fail results
- `DoD-FAQ-Bot-Architecture.docx` and `DoD-FAQ-Bot-Overview.pptx` — customer-facing deliverables (unchanged)
- Session state: `%USERPROFILE%\.copilot\session-state\b8657cf3-…\files\`
  - `bot-app-registration.json` — bot app secret
  - `deployment-name.txt` — last deployment name

