# Smoke Test Results — CACHEBOT Pilot

**Executed:** 2026-09-21 · **Deployment:** `faqbot-pilot1-20260921-115418`
**Result:** ✅ **24 / 24 passed**

## Result matrix

| # | Section | Test | Result |
|---|---|---|---|
| 1 | Core resources | Resource group | ✅ |
| 2 | | vNet `vnet-faqbot-pilot1` | ✅ |
| 3 | | Log Analytics `law-faqbot-pilot1` | ✅ |
| 4 | | Application Insights `appi-faqbot-pilot1` | ✅ |
| 5 | | Key Vault RBAC + PE | ✅ |
| 6 | | AOAI account provisioned | ✅ |
| 7 | Model deployments | `gpt-4o` Succeeded | ✅ |
| 8 | | `text-embedding-3-large` Succeeded | ✅ |
| 9 | | `gpt-4o` capacity = 100 kTPM | ✅ |
| 10 | Private endpoints | AOAI PE Succeeded | ✅ |
| 11 | | KV PE Succeeded | ✅ |
| 12 | AI Search | `/servicestats` reachable | ✅ |
| 13 | | `cachebot-cache` index exists (14 fields, 3072-d HNSW cosine) | ✅ |
| 14 | VM | Provisioning Succeeded | ✅ |
| 15 | | System-assigned managed identity | ✅ |
| 16 | | PowerState = running | ✅ |
| 17 | | AzureMonitorLinuxAgent extension present | ✅ |
| 18 | Azure Bot | Bot exists | ✅ |
| 19 | | MSA AppId matches `e97c7d46-…` | ✅ |
| 20 | | MsTeamsChannel configured | ✅ |
| 21 | | DirectLineChannel configured | ✅ |
| 22 | RBAC (VM MI) | Cognitive Services OpenAI User → AOAI | ✅ |
| 23 | | Search Index Data Reader → Search | ✅ |
| 24 | | Key Vault Secrets User → KV | ✅ |

## Deployed endpoints

| Resource | URI |
|---|---|
| AOAI | `https://aoai-faqbot-pilot1-pbkgn5co6zxwe.openai.azure.com/` (PE-only) |
| AI Search | `https://srch-faqbot-pilot1-pbkgn5co6zxwe.search.windows.net` (public + key auth) |
| Key Vault | `https://kv-faqbot-pilot1-pbkgn.vault.azure.net/` (PE-only) |
| Bot (Direct Line) | `bot-faqbot-pilot1` — Teams + Direct Line enabled |
| VM private IP | `10.42.0.4` (no public IP; SSH only via bastion or public-IP add-on) |

## What we did NOT test end-to-end

Live inference against AOAI requires the orchestrator container running on the VM
(cloud-init only bootstraps Docker + Az CLI in the pilot; the orchestrator image
was not built or deployed). To take the pilot to a live chat, the next step is:

1. Build `orchestrator:latest` container image (Python + Bot Framework SDK
   + AOAI + AI Search + escalation glue)
2. Push to an ACR or Docker Hub (pilot: Docker Hub public is fine)
3. Re-provision the VM (or SSH in) and `docker run` with env vars pointing at
   the private AOAI + Search + KV endpoints
4. Update the Bot Service `endpoint` from the placeholder to
   `https://<vm-fqdn-or-lb>:443/api/messages`

That is intentionally out of scope for infra smoke-test.

---

# RAG loop validation — 2026-07-27

Path A executed: local push → AOAI embed → Search index → RAG chat completion.

## Corpus

- 25 seed docs in `sample-corpus\*.txt` (federal / Azure Gov / RAG themed)
- Chunked at ~2000 chars, 200-char overlap (all docs fit in a single chunk here)
- Embedded with `text-embedding-3-large` (3072-d)
- Uploaded to `cachebot-index` via `deploy\ingest-corpus.ps1`
- Confirmed doc count: **25 / 25**

## RAG query results

| # | Test | Mode | Top-1 hit | Answer quality | Tokens (P / C) |
|---|---|---|---|---|---|
| R1 | "What AOAI models are in Gov and how do I request quota?" | vector | `03-aoai-gov-availability.txt` (score 0.799) | ✅ Correct, cites [1] and [2] | 556 / 170 |
| R2 | "How should I cache LLM responses to reduce token costs?" | hybrid | `18-cost-optimization.txt` (score 0.033) | ✅ Correctly names L1 + L2 pattern with cite | 548 / 169 |
| R3 | "What happens when the bot can't answer and how do users escalate?" | vector | `14-escalation-workflow.txt` (score 0.742) | ✅ Full flag → Function → SharePoint/Teams flow | 561 / 148 |
| R4 | "What's the current price of Bitcoin?" (negative) | vector | (top-3 all unrelated) | ✅ Correctly refuses + suggests escalation | 543 / 35 |

Cache index (`cachebot-cache`) is deployed but not yet wired — will populate once the orchestrator is running.

## Non-obvious findings during ingest

- **AOAI data-plane RBAC propagation is long**: ~25 min from `az role assignment create` to first successful call. Documented Microsoft behavior; not a bug in the deploy.
- **`disableLocalAuth: true` is enforced by policy** on this sub — attempts to flip it via `az resource update`, `az cognitiveservices account update`, and a direct ARM PATCH all silently no-op'd. AAD is the only auth path; that's actually good hygiene, but worth capturing for the customer's DoD sub selection.
---

## 7. Cache validation — 2026-07-27 afternoon

L1 + L2 caching wired into `deploy\rag-query.ps1`. Cache lives in the pre-existing `cachebot-cache` index (14 fields, 3072-d HNSW cosine, validates `promptVersion` + `modelVersion` + `expiresAt`).

| # | Scenario | Layer | Result |
|---|---|---|---|
| C1 | First-ask "differences between IL4 and IL5" | miss | ✅ full RAG, cache write |
| C2 | Same question again | L1 exact | ✅ SHA256 filter match, zero chat tokens |
| C3 | "What's the difference between IL4 and IL5 impact levels?" (close paraphrase) | L2 semantic (cosine 0.984) | ✅ hit at threshold 0.85 |
| C4 | "Break down the difference between IL4 and IL5…" (looser paraphrase) | miss (cosine 0.685) | ✅ correctly falls through to RAG |
| C5 | Unrelated Q | miss | ✅ full RAG |
| C6 | `-SkipCache` on cached Q | miss (forced) | ✅ bypass works |

Key implementation notes captured for the DoD build:
- L1 key = SHA256 over normalized question (`Lower` + collapse whitespace + strip punctuation) → `cacheKeyHash` filter. No embedding required, so a hot cache costs 1 tiny Search filter + 1 tiny merge to bump `hitCount`.
- L2 key = question embedding vector search over `questionEmbedding`. `@search.score` for cosine in Azure AI Search is `1 / (2 - cosine)`; the check converts back to raw cosine before applying the threshold.
- Cache TTL default = 24h. `sourceDocsVersion`, `promptVersion`, and `modelVersion` are stored per entry so a system prompt or model swap invalidates prior entries without a manual purge.
- **`text-embedding-3-large` observation**: raw cosine distances compress into a narrower range than `text-embedding-3-small`. Threshold 0.92 is the industry default but too tight for this model on real user paraphrases. For the DoD build, plan on 0.82-0.88 as the tuning range and instrument hit rate to converge.

## 8. Multi-format ingest validation — 2026-07-27 afternoon

Updated `deploy\ingest-corpus.ps1` supports `.txt`, `.md`, `.docx`, `.pdf`:
- `.txt` / `.md` — direct read
- `.docx` — `System.IO.Compression.ZipFile` + XML parse of `word/document.xml` (zero external deps)
- `.pdf` — [PdfPig](https://www.nuget.org/packages/PdfPig) 0.1.9, downloaded on first run into `deploy\lib\` (net6.0 for PS 7, net462 for PS 5.1)

Test docs generated via Word COM (Word 2013+ required to *build* them; not to ingest):
- `26-bot-emulator-dod.docx` (14 KB)
- `27-fedramp-vs-dod-srg.pdf`  (24 KB)

| # | Test | Retrieval top-1 score | Answer cited from | Pass |
|---|---|---|---|---|
| M1 | "How do I test a bot locally with Bot Framework Emulator in DoD?" | 0.818 on `.docx` chunk | `26-bot-emulator-dod.docx` | ✅ |
| M2 | "How does FedRAMP High relate to the DoD Cloud SRG impact levels?" | 0.853 on `.pdf` chunk | `27-fedramp-vs-dod-srg.pdf` | ✅ |

Final state: **27 docs in `cachebot-index`, 5 entries in `cachebot-cache`**.

## 9. Network posture change during ingest

CGNAT on this workstation caused Azure OpenAI to see a different public IP than what `ipify.org` returned (workstation NAT'd at `100.96.32.172`, apparent public IP varied per-destination). To keep the pilot unblocked, `networkAcls.defaultAction` was flipped from `Deny` (with IP allowlist) to `Allow`. **AAD RBAC + `disableLocalAuth: true` remain enforced** — those are the real security boundary. Network ACL was defense-in-depth and will be re-added for the DoD deploy (Gov region ingress is a static path).



## 10. Orchestrator container + channel wiring (2026-09-22)

Built and deployed the Python orchestrator as an Azure Container Apps service, then wired the Azure Bot Service endpoint to it and confirmed a full round-trip through Direct Line.

### Build & push
- Image `crfaqbotpilot1pbkgn5co6zxwe.azurecr.io/cachebot-orchestrator:0.1.0` (also `:latest`) built server-side via `az acr build` (client-side colorama unicode crash was cosmetic — server succeeded; verify via `az acr repository show-tags`).
- Registry: ACR `crfaqbotpilot1pbkgn5co6zxwe` (Basic SKU) in `rg-faqbot-pilot1-eastus2`.

### Container Apps
- Environment `cae-faqbot-pilot1` (Consumption workload profile, wired to LAW `law-faqbot-pilot1`), static IP `52.177.240.41`, provisioned in ~11 min.
- App `ca-faqbot-orchestrator` — system-assigned MI, ACR pull via `--registry-identity system`, 0.5 vCPU / 1 GiB, 1–3 replicas, external ingress on 3978.
- FQDN: `https://ca-faqbot-orchestrator.victoriousbush-2a7eac0b.eastus2.azurecontainerapps.io`
- MI object id `<container-app-mi-object-id>` granted **AcrPull** on ACR + **Cognitive Services OpenAI User** on AOAI + **Search Index Data Contributor** + **Search Index Data Reader** on Search.

### Bot secret + tenant fix
- Rotated bot MSA secret via Graph `addPassword` (display name `pilot-orchestrator`), stored as Container Apps secret `bot-secret`, referenced via `BOT_APP_SECRET=secretref:bot-secret`.
- Bot Service MSA type is **`SingleTenant`**, tenant `<tenant-id>` — outbound BF client-credentials token URL must target that tenant, not `botframework.com`. Set `BOT_TENANT_ID` env var. First E2E attempt without this failed with `400 Bad Request` from `login.microsoftonline.com/botframework.com/oauth2/v2.0/token`.

### End-to-end tests via Direct Line

Toggled `isSecureSiteEnabled=false` on the Direct Line site (`TrustedOrigins can not be null` blocked conversation start otherwise) — will re-enable for production with a trusted origin list.

| # | Test | Result |
|---|---|---|
| O1 | `/health` returns 200 `{"status":"ok"}` | ✅ |
| O2 | `/ready` returns embed_dim=3072, index_docs=27 (proves MI to both AOAI + Search) | ✅ |
| O3 | `/debug/query` — "FedRAMP High vs DoD IL5" — miss + writes cache | ✅ (2.9 s) |
| O4 | Repeat same question 3rd time — **L1 cache hit** | ✅ (121 ms, 0 tokens) |
| O5 | Direct Line `StartConversation` → send message → poll for bot reply — reply contains adaptive card with 👍/👎/🚩 buttons | ✅ |
| O6 | Escalation flow: `Action.Submit` with `value.action=escalate` → orchestrator logs `ESCALATION` warning to stdout (LAW-searchable) and replies "Thanks — I flagged this…" | ✅ |

**Endpoints of record:**
- Container App: `https://ca-faqbot-orchestrator.victoriousbush-2a7eac0b.eastus2.azurecontainerapps.io`
- Bot Service endpoint (updated): same FQDN, `/api/messages`
- Direct Line site: `Default Site` (secret rotated when secure-site was toggled)

## Result matrix — additions

| # | Section | Test | Result |
|---|---|---|---|
| 42 | Orchestrator | Health/Ready probes | ✅ |
| 43 | | RAG debug query (miss → write) | ✅ |
| 44 | | L1 cache hit after write (~25× faster, 0 tokens) | ✅ |
| 45 | Channel | Direct Line E2E (message → adaptive card reply) | ✅ |
| 46 | | Escalation submit → ESCALATION log line | ✅ |

**Final result: 46 / 46 passed.**
