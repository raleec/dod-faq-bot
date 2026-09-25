# DoD FAQ Bot — Reference Architecture + Pilot

A reference architecture and working pilot for a **RAG-based FAQ bot deployable to the Azure DoD region**. Users ask questions through Teams or a web chat channel; answers are grounded in a corpus indexed from a SharePoint list (or any doc set) using Azure AI Search + Azure OpenAI; unanswered/incorrect items can be escalated to a triage team.

The pilot in this repo was deployed to Azure Commercial (`eastus2`) as a proof-of-pattern before the customer's DoD build-out — the Bicep, orchestrator code, and runbook translate 1:1 to `usgovvirginia` / `usdodeast` with only region + endpoint substitutions.

---

## Architecture at a glance

```
 ┌──────────────┐   ┌──────────────┐   ┌───────────────────────────┐
 │  MS Teams    │──▶│              │──▶│  Container App            │
 └──────────────┘   │  Azure Bot   │   │  (Python aiohttp)         │
 ┌──────────────┐   │  Service     │   │                           │
 │  Web / DL    │──▶│              │   │  ┌────────────────────┐   │
 └──────────────┘   └──────────────┘   │  │  L1 hash cache     │   │
                                       │  │  L2 vector cache   │───┼──▶ AI Search
                                       │  └────────────────────┘   │    (faq-cache)
                                       │           │               │
                                       │           ▼               │───▶ AI Search
                                       │  ┌────────────────────┐   │    (faq-index)
                                       │  │  Vector retrieval  │───┼──▶ AOAI embeddings
                                       │  │  Chat completion   │───┼──▶ AOAI gpt-4o
                                       │  └────────────────────┘   │
                                       │           │               │
                                       │           ▼               │───▶ Log Analytics
                                       │  ┌────────────────────┐   │    (ESCALATION rows)
                                       │  │  Adaptive Card     │   │
                                       │  │  👍 👎 🚩 Escalate │   │
                                       │  └────────────────────┘   │
                                       └───────────────────────────┘
```

Full component diagram + deployment runbook in [`DEPLOYMENT-RUNBOOK.md`](./DEPLOYMENT-RUNBOOK.md) and [`DoD-FAQ-Bot-Architecture.docx`](./DoD-FAQ-Bot-Architecture.docx).

---

## What's in the box

| Path | Purpose |
|---|---|
| `bicep/` | **Reference (DoD-region) IaC** — full production topology: private endpoints, KV with purge protection, LAW+App Insights, Bot Service with Teams channel, AOAI with `disableLocalAuth`, AI Search Basic, jump-VM |
| `bicep-pilot/` | **Pilot (commercial) IaC** — same shape as reference, public endpoints for simpler validation, used for the smoke-tested deployment |
| `orchestrator/` | Python 3.12 aiohttp app: RAG pipeline, L1+L2 caching, adaptive-card feedback + escalation, Dockerfile |
| `deploy/` | PowerShell scripts: `rag-query.ps1` (baseline), `ingest-corpus.ps1` (multi-format cracker for `.txt` / `.md` / `.docx` / `.pdf`), `teardown-pilot.ps1` |
| `sample-corpus/` | Seed knowledge base — DoD / Azure Gov policy notes used during the pilot smoke tests |
| `DEPLOYMENT-RUNBOOK.md` | End-to-end deployment steps for the DoD build-out |
| `SMOKE-TEST.md` | Full test matrix from the commercial pilot — 46 / 46 passed (infra, cache, multi-format ingest, orchestrator, Direct Line E2E) |
| `ACCESS-AND-INGEST.md` | Operator guide for querying, ingesting new docs, and adjusting cache thresholds |
| `aoai-quota-request.md` | Template for the AOAI capacity request in the DoD region |
| `DoD-FAQ-Bot-Architecture.docx` | Customer-facing architecture deliverable |
| `DoD-FAQ-Bot-Overview.pptx` | Customer-facing exec summary deck |

---

## Key design decisions

1. **AAD everywhere, not keys.** AOAI + Search both use managed-identity access from the Container App. `disableLocalAuth=true` on AOAI is enforced by policy.
2. **Two-tier answer cache.**
   - **L1** = SHA-256 hash of the normalized question → sub-second exact-match hit (~120 ms E2E, 0 tokens).
   - **L2** = cosine-similarity vector search on question embeddings (default threshold `0.85` — tuned for `text-embedding-3-large`'s compressed cosine range).
3. **Container Apps over VM/AKS** for the pilot — cheap idle floor, scales to zero-ish, single-command deploy, MI-native.
4. **Escalation as a sink, not a workflow.** The bot logs an `ESCALATION` warning to LAW (queryable by the triage team). A webhook stub is included for integration with ServiceNow / Teams channel / whatever.
5. **Costs modeled at ~$2,500/month** for fairly high usage: gpt-4o pay-as-you-go dominates; AI Search Basic + Container Apps + Bot Standard are ~$300/mo combined. Idle floor is ~$180/mo (Search + LAW retention + KV + ACR).

---

## Quick start — pilot deployment

Prereqs: Azure subscription, `az` CLI, PowerShell 7+, Docker (optional for local orchestrator build).

```powershell
# 1. Provision the pilot RG + services (10–15 min)
cd bicep-pilot
az deployment sub create --location eastus2 --template-file main.bicep --parameters main.bicepparam

# 2. Seed the corpus
cd ../deploy
.\ingest-corpus.ps1 -Path ..\sample-corpus

# 3. Build + push the orchestrator container
cd ../orchestrator
az acr build --registry $env:ACR --image faq-orchestrator:0.1.0 .

# 4. Deploy Container App + wire Bot Service endpoint (see DEPLOYMENT-RUNBOOK.md §7)

# 5. Smoke-test via Direct Line — see SMOKE-TEST.md §10
```

Tear down when done:

```powershell
cd deploy
.\teardown-pilot.ps1
```

---

## Status

- **Commercial pilot:** ✅ deployed + smoke-tested (46/46) + torn down. See `SMOKE-TEST.md`.
- **DoD deployment:** ⏳ pending customer quota approval — see `aoai-quota-request.md`.

## License

Internal / customer-specific. All corpus content is illustrative only; not customer data.
