# FAQ Bot Pilot — Access & Corpus Feed Guide

**Deployment**: commercial-cloud pilot in sub `MngEnvMCAP217858`, RG `rg-faqbot-pilot1-eastus2`
**Purpose**: proves the RAG pipeline end-to-end. DoD prod deploy will reuse this pattern in a Gov region.
**Status (2026-07-27)**: infra deployed, 25 seed docs indexed, 4/4 RAG queries verified.

---

## 1. What's actually running today

| Layer | Resource | How you reach it |
|---|---|---|
| Retrieval | `srch-faqbot-pilot1-pbkgn5co6zxwe` (AI Search Basic, eastus) | Portal, REST, or `az search` |
| Embeddings + Chat | `aoai-faqbot-pilot1-pbkgn5co6zxwe` (AOAI, eastus2) | Portal (Foundry playground), REST |
| Bot channel | `bot-faqbot-pilot1` (App Registration `<bot-msa-app-id>`) | Bot Framework Emulator, Teams (post-manifest) |
| Compute (future orchestrator) | `vm-faqbot-pilot1` (D2s_v7, private only) | Bastion or Run-Command |
| Secrets | `kv-faqbot-pilot1-pbkgn5co6zxwe` | Portal, `az keyvault` |
| Indexes | `faq-index` (primary, 25 docs) · `faq-cache` (L2 semantic cache, empty) | Search REST |

There is no orchestrator app yet — the retrieval + LLM loop is proven via `deploy\rag-query.ps1`. The next phase (customer DoD deploy) drops this loop into the App Service or Function.

---

## 2. How to access it right now

### 2a. Query the RAG loop from your desktop
```powershell
cd 'C:\Users\raleecook\OneDrive - Microsoft\Documents\Microsoft Scout\dod-faq-bot'
.\deploy\rag-query.ps1 -Question "How do IL4 and IL5 differ?"

# Hybrid (BM25 + vector) — better for keyword-heavy questions:
.\deploy\rag-query.ps1 -Question "..." -Hybrid

# Change top-k:
.\deploy\rag-query.ps1 -Question "..." -TopK 5

# Force a fresh answer (bypass cache):
.\deploy\rag-query.ps1 -Question "..." -SkipCache

# Tune the L2 semantic-cache threshold (cosine, 0-1):
.\deploy\rag-query.ps1 -Question "..." -L2Threshold 0.85
```

**Cache behavior** (default on):
- **L1** — SHA256 of the normalized question. Repeat asks return the cached answer with zero chat-token spend.
- **L2** — vector similarity over past questions. Paraphrases above the cosine threshold reuse the prior answer.
- Cache entries include `promptVersion` and `modelVersion`; changing either invalidates old entries automatically.
- Default TTL 24h — override with `-CacheTtlHours`.

### 2b. Try it in the AOAI Foundry playground
- Portal → `aoai-faqbot-pilot1-pbkgn5co6zxwe` → **Go to Azure AI Foundry portal**
- Chat playground → **Add your data** → **Azure AI Search** → pick `faq-index`, field `content`, vector field `contentVector`, embedding `text-embedding-3-large`.
- No code — good for showing the customer the pattern in ~5 minutes.

### 2c. Bot Framework Emulator (channel test)
- Download Bot Framework Emulator locally.
- Endpoint: no messaging endpoint is deployed yet (the customer's Function/App Service will host it). To exercise the *bot channel* itself, publish a stub endpoint or wait for the orchestrator phase.

---

## 3. How to feed more corpus

Two supported patterns today: **push** (recommended for pilot) and **SharePoint indexer** (recommended for prod, requires SKU/network work).

### 3a. Push more docs (works today, seed pattern)

**Format**: any `.txt`, `.md`, `.docx`, or `.pdf` file with an optional first line `Title: ...` (falls back to the first non-blank line or the file name).

**Cracker backends** (auto-selected from file extension):
- `.txt` / `.md` — plain read
- `.docx` — parse `word/document.xml` via built-in `System.IO.Compression` (no external tools required)
- `.pdf` — [PdfPig](https://www.nuget.org/packages/PdfPig) 0.1.9, downloaded on first run into `deploy\lib\` (~7 MB)

**Steps**:
1. Drop files into `dod-faq-bot\sample-corpus\` (or point `-CorpusPath` at your own folder).
2. Run:
   ```powershell
   .\deploy\ingest-corpus.ps1 -CorpusPath 'C:\path\to\your\docs'
   ```
3. The script chunks (~2000 chars, 200 overlap), embeds via AOAI, and `mergeOrUpload`s into `faq-index`. Re-runs are idempotent — same source file + same chunk index = same doc ID.

**To reset the index** (nuke and re-seed):
```powershell
$sk = az search admin-key show --service-name srch-faqbot-pilot1-pbkgn5co6zxwe -g rg-faqbot-pilot1-eastus2 --query primaryKey -o tsv
Invoke-RestMethod -Method POST -Uri "https://srch-faqbot-pilot1-pbkgn5co6zxwe.search.windows.net/indexes/faq-index/docs/index?api-version=2024-07-01" `
    -Headers @{ 'api-key' = $sk; 'Content-Type' = 'application/json' } `
    -Body (@{ value = @( (Invoke-RestMethod -Uri "https://srch-faqbot-pilot1-pbkgn5co6zxwe.search.windows.net/indexes/faq-index/docs?api-version=2024-07-01&`$select=id&`$top=1000" -Headers @{'api-key'=$sk}).value | ForEach-Object { @{ '@search.action' = 'delete'; id = $_.id } }) } | ConvertTo-Json -Depth 10)
```

**Non-text formats (.docx, .pdf, .pptx)**: add a parser step. Simplest: install `pandoc` or use `Word.Application` COM to save-as .txt; drop into `sample-corpus`; re-run ingest. Not automated in the pilot script — the customer's DoD build will use Search built-in cracking (below).

### 3b. SharePoint indexer (target pattern for prod)

The customer wants a SharePoint list as the corpus. In production this becomes:

```
SharePoint doc library ─► AI Search SP indexer ─► #Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill ─► faq-index
                                                        │
                                                        └► calls AOAI text-embedding-3-large
```

**Prereqs for the SharePoint indexer to work here (not done today)**:
- **SKU**: AI Search **Standard S1** or higher (~$250/mo). Basic (what we have) does not support shared private link, which the indexer needs to reach a private-endpointed AOAI. If AOAI is public + IP-allowlisted, Basic can technically work.
- **Entra app registration** with `Sites.Read.All` (application) permission, admin-consented in the target tenant. Client secret in Key Vault.
- **SharePoint site** and library populated with the FAQ documents.
- **Data source, indexer, and skillset** configured on Search. Template lives in `bicep-pilot\modules\` — not wired for pilot but ready to enable.

**When we move to DoD (US Gov Virginia or DoD East)**:
- Use the M365 GCC-High / DoD tenant's SharePoint URL variant.
- Search + AOAI must both be in-region.
- Entra app registration is in the Gov tenant (`login.microsoftonline.us`).
- Private endpoints preferred over IP allowlist.

---

## 4. Common tasks

### 4a. Update your IP on the AOAI allowlist
Your public IP will change if you switch VPN. If AOAI calls suddenly return `403`, refresh the allowlist:
```powershell
$myIp = (Invoke-RestMethod https://api.ipify.org?format=json).ip
az cognitiveservices account network-rule add -n aoai-faqbot-pilot1-pbkgn5co6zxwe -g rg-faqbot-pilot1-eastus2 --ip-address $myIp
```

### 4b. Rotate the Search admin key
```powershell
az search admin-key renew --service-name srch-faqbot-pilot1-pbkgn5co6zxwe -g rg-faqbot-pilot1-eastus2 --key-kind primary
```
Ingest and query scripts pull the key fresh each run, so no code change needed.

### 4c. Grant another teammate access to query
```powershell
# Their Entra Object ID:
$oid = az ad user show --id someone@<sandbox-tenant>.onmicrosoft.com --query id -o tsv
az role assignment create --assignee $oid --role "Cognitive Services OpenAI User" --scope /subscriptions/<subscription-id>/resourceGroups/rg-faqbot-pilot1-eastus2/providers/Microsoft.CognitiveServices/accounts/aoai-faqbot-pilot1-pbkgn5co6zxwe
# Also add their public IP to the AOAI allowlist as in 4a.
# Data-plane RBAC propagation is 10-20 min. Confirmed behavior.
```

### 4d. Inspect what's in the index
```powershell
$sk = az search admin-key show --service-name srch-faqbot-pilot1-pbkgn5co6zxwe -g rg-faqbot-pilot1-eastus2 --query primaryKey -o tsv
$h = @{ 'api-key' = $sk }
# Count
Invoke-RestMethod -Uri "https://srch-faqbot-pilot1-pbkgn5co6zxwe.search.windows.net/indexes/faq-index/docs/`$count?api-version=2024-07-01" -Headers $h
# List titles + sources
(Invoke-RestMethod -Uri "https://srch-faqbot-pilot1-pbkgn5co6zxwe.search.windows.net/indexes/faq-index/docs?api-version=2024-07-01&`$select=id,title,source&`$top=100" -Headers $h).value | Format-Table
```

---

## 5. Verified query results (2026-07-27)

| # | Question | Mode | Top-1 hit | Grounded answer? | Tokens (P/C) |
|---|---|---|---|---|---|
| 1 | AOAI models in Gov + quota process | vector | AOAI Availability in Gov | ✅ with [1][2] cites | 556 / 170 |
| 2 | LLM response caching | hybrid | Cost Optimization + Response Caching Layers | ✅ describes L1/L2 correctly | 548 / 169 |
| 3 | Bot escalation flow | vector | Escalating Unanswered Questions | ✅ full flow with cite | 561 / 148 |
| 4 | "What's the price of Bitcoin?" | vector | (top-3 unrelated) | ✅ correctly refuses and escalates | 543 / 35 |

Full transcript is in `SMOKE-TEST.md`.

---

## 6. Housekeeping — pilot is temporary

- Teardown is scripted: `deploy\teardown-pilot.ps1 -Force`. Target date **~2026-09-28**.
- Before teardown, decide whether any of the seed corpus / RAG results are worth exporting for the customer briefing deck.
- After teardown: revert the AOAI IP allowlist entry (not strictly needed since account is deleted, but good hygiene if we redeploy).
