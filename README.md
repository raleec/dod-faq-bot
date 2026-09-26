# CACHEBOT — Reference Architecture + Pilot

A reference architecture and working pilot for a **RAG-based FAQ bot deployable to the Azure**. Users ask questions through Teams or a web chat channel; answers are grounded in a corpus indexed from a SharePoint list (or any doc set) using Azure AI Search + Azure OpenAI; unanswered/incorrect items can be escalated to a triage team.

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
                                       │  └────────────────────┘   │    (cachebot-cache)
                                       │           │               │
                                       │           ▼               │───▶ AI Search
                                       │  ┌────────────────────┐   │    (cachebot-index)
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

## Response caching (L1 exact + L2 semantic)

Two-tier cache in front of the LLM. **L1** is a SHA-256 lookup on the normalized
question — instantly hits repeat asks. **L2** is a vector search over prior
question embeddings — hits *paraphrases* of previously answered questions.
Together they cut LLM spend + median latency dramatically on any topic with a
long tail of similar phrasings (which is exactly the FAQ-bot workload).

### Request flow

```
                 ┌─────────────────────┐
 user question ─▶│ normalize + SHA-256 │──┐
                 └─────────────────────┘  │
                                          ▼
                                    ┌──────────┐   hit   ┌──────────────────┐
                                    │   L1     │────────▶│ return cached    │  ~120 ms
                                    │  filter  │         │ answer, bump hit │  0 tokens
                                    └────┬─────┘         └──────────────────┘
                                         │ miss
                                         ▼
                              ┌────────────────────┐
                              │ embed question via │
                              │ text-embedding-3-  │
                              │ large (3072-d)     │
                              └──────────┬─────────┘
                                         │
                                         ▼
                                    ┌──────────┐   hit   ┌──────────────────┐
                                    │   L2     │────────▶│ return cached    │  ~600 ms
                                    │  vector  │ ≥ 0.85  │ answer, bump hit │  ~1k tokens
                                    │  search  │ cosine  │ + PROMOTE hash   │  (embed only)
                                    └────┬─────┘         │ into L1 aliases  │
                                         │ miss          └──────────────────┘
                                         ▼
                                  ┌──────────────┐
                                  │  cachebot-index   │──▶ chat completion ──▶ answer
                                  │  retrieval   │                        + write cache
                                  └──────────────┘   ~2–4 s, ~1k prompt + ~150 completion tokens
```

Every miss writes back into the cache so the *next* similar question wins on
L1 or L2. **On an L2 hit, the current question's hash is promoted into the
winning entry's L1 alias list** (FIFO-capped at `MAX_L1_ALIASES=32`) — so the
*next* time that same paraphrase is asked, it wins on L1 (no embed step, no
vector search). Over time, hot canonical answers accumulate their common
paraphrasings and the fast path becomes broader without duplicating cached
answers.

### `cachebot-cache` index schema (14 fields, HNSW cosine profile)

Both caches live in the **same Azure AI Search index** (`cachebot-cache`, sibling to
`cachebot-index`). No additional Azure resources — the vector search piggybacks on
the AI Search Basic instance.

| Field | Purpose |
|---|---|
| `id` | Random GUID (primary key) |
| `cacheKeyHash` | **List** of SHA-256 hashes for the normalized question and any promoted L2-alias paraphrases (FIFO cap `MAX_L1_ALIASES=32`) — **L1 filter** via `cacheKeyHash/any(h: h eq '<sha>')` |
| `questionEmbedding` | 3072-d vector on `text-embedding-3-large` — **L2 vector field** (HNSW / cosine) |
| `question` | Raw question text (for debugging / audit) |
| `answer` | Cached LLM response |
| `citations` | Source doc filenames returned |
| `retrievedChunkIds` | Chunks that produced the original answer |
| `sourceDocsVersion` | Corpus version tag — bump to force full cache miss on reindex |
| `promptVersion` | System-prompt version — bump when you change the prompt |
| `modelVersion` | e.g. `gpt-4o-2024-11-20` — bump when you rev the model |
| `sensitivityLabel` | e.g. `unclassified`, `cui` — used to gate cache reuse in mixed-audience deployments |
| `hitCount` | Incremented on every hit (informs cache eviction / warmup analytics) |
| `createdAt` | UTC timestamp |
| `expiresAt` | UTC timestamp — filtered on every lookup (default TTL **336 h / 14 days**, override via `CACHE_TTL_HOURS`) |

Both L1 and L2 lookups also filter on `promptVersion` + `modelVersion` + `expiresAt`
so **a prompt tweak or model rev automatically invalidates prior entries** — no
manual purge, no stale answers.

### L2 tuning — `text-embedding-3-large` cosine is compressed

The industry-default L2 threshold of `0.92` **almost never fires** on this
embedding model. Empirically-observed ranges from the pilot (`text-embedding-3-large`):

| Question pair | Observed cosine |
|---|---|
| Identical text | 1.00 |
| Close paraphrase (same intent, ≈70 % overlap) | 0.95–0.98 |
| Same topic, different framing | 0.82–0.88 |
| Related but different question | 0.65–0.75 |
| Unrelated | 0.45–0.60 |

**Default threshold is `0.85`.** Ratchet down to widen recall (more cache reuse,
some risk of false-positives on nuance); ratchet up to tighten precision.
Adjust via `L2_THRESHOLD` env var (orchestrator) or `-L2Threshold` (PowerShell
CLI). Azure AI Search returns cosine as `@search.score = 1 / (2 - cosine)`;
both the Python (`rag.py`) and PowerShell (`rag-query.ps1`) implementations
invert that back to raw cosine before applying the threshold.

### Overriding behavior

| Knob | Where | Default | Effect |
|---|---|---|---|
| `-SkipCache` / `SKIP_CACHE=1` | CLI / env | off | Bypass both L1 and L2; always call the LLM |
| `-L2Threshold 0.85` / `L2_THRESHOLD` | CLI / env | `0.85` | Cosine cutoff for L2 hit |
| `-CacheTtlHours 336` / `CACHE_TTL_HOURS` | CLI / env | `336` (14 days) | How long an entry stays hit-eligible |
| `-PromptVersion v2` / `PROMPT_VERSION` | CLI / env | `v1` | Bump to invalidate all cached entries answered under the old prompt |
| `SENSITIVITY_LABEL` | env | `unclassified` | Stamped on writes; gate reads by policy |
| `SOURCE_DOCS_VERSION` | env | `seed-2026-07-27` | Bump on reindex to force a rebuild |
| `MAX_L1_ALIASES` | env | `32` | Cap on how many paraphrase hashes get promoted onto a single canonical cache entry (FIFO-evict oldest) |

### Pilot numbers (from `SMOKE-TEST.md` §7)

| Metric | Miss | L1 hit | L2 hit |
|---|---|---|---|
| Latency | 2 900 ms | **121 ms** | ~600 ms |
| Chat tokens | 712 prompt + 169 completion | **0** | 0 |
| Embed tokens | ~50 | 0 | ~50 |
| Search reads | 1 vector + 1 chat + 1 cache write | 1 filter + 1 merge | 1 vector + 1 merge |
| Approx. cost/query (gpt-4o + embed) | ~$0.006 | **~$0.00003** | ~$0.00004 |

At ~40 % combined hit rate (conservative estimate for a real FAQ workload), the
cache pays for itself against the AI Search Basic tier within the first few
thousand queries and turns median latency into a sub-second experience.

### Long TTLs (weeks–months) — tradeoffs and mitigations

FAQ answers change on the timescale of policy/product updates, not hours. The
default TTL is therefore **14 days**, and there are cases (stable KB, semantic-
search-replacement workload, small trusted user base) where **60–90 days** is
reasonable. The tradeoffs shift as you extend TTL:

| Risk | Grows with TTL? | Why | Mitigation |
|---|---|---|---|
| **Answer staleness** — cache returns policy/pricing/contact info that has since changed in the KB | **Yes, sharply** | Long TTL means most weight sits on `sourceDocsVersion` for invalidation | Bump `SOURCE_DOCS_VERSION` on **every material corpus change**; wire the ingest job to increment it automatically |
| **Retrieval drift** — new/better chunks now exist in `cachebot-index` but the cache serves the old synthesis | Yes | Cache entry pins `retrievedChunkIds` at write time | Add "citation-integrity check": on cache read, verify all `retrievedChunkIds` still exist in `cachebot-index`; drop cache read if any are gone |
| **Model regression** — AOAI ships a new `gpt-4o-YYYY-MM-DD` and the cached answer no longer matches a fresh call | Yes | `modelVersion` comes from the AOAI response header; auto-invalidates on rev, so this is mostly handled | Pin your deployment to a specific model rev (not "latest") so `modelVersion` is stable and you invalidate deliberately |
| **Prompt/guardrail drift** — tightened safety filter, new PII rule, updated tone | Yes | Only fix is `PROMPT_VERSION` bump | Treat `PROMPT_VERSION` as a semver on the system prompt; bump on any material change |
| **L2 false positives** — a 0.86-cosine paraphrase turns out to have subtly different intent | Yes | Larger cache = larger candidate set for near-matches | Raise `L2_THRESHOLD` as the cache grows (0.85 → 0.87 → 0.88); log cosine per hit and correlate with 👎 feedback |
| **Cache poisoning** — a first-time wrong answer serves paraphrases for weeks | **Yes, sharply** | No automatic quality gate today | Wire 👎 / 🚩 signals from the adaptive card to a `negFeedbackCount` field; auto-evict on ≥ N thumbs-down or on any escalation triggered by a cache hit |
| **Personalization leakage** — user A gets an answer that should have been personalized to their role/tenant | Yes | Cache key is question-only, not user-scoped | Either add `audienceKey` to the hash (destroys hit rate) or classify answers as "audience-agnostic" and only cache those. For the FAQ workload most items are shared-audience — the leak surface is small if you enforce `sensitivityLabel` |
| **Regulatory / audit surface** — cached content inherits source doc sensitivity, must be purgeable | Yes | Long-lived derived data = longer retention obligation | Honor `sensitivityLabel` filter on reads; document that `az search index reset` on `cachebot-cache` is part of the DR / classified-doc-retract runbook |
| **Storage cost** | ~none | Basic AI Search: $73/mo flat, 2 GB / ~130 k entries at ~15 KB/entry. At 500 unique Qs/day + 14-day TTL = ~7 k entries. Even at 90 days = ~45 k. Well inside Basic. | Move to Standard S1 (25 GB) only above ~130 k live entries |
| **Cold-start bias** — early users' phrasing locks in for weeks | Yes | First writer wins on L2 | Seed the cache at deploy time with a curated FAQ list (one embedding per canonical question) |
| **Thundering-herd on miss** — 100 users hit the same brand-new Q simultaneously, all miss, all call the LLM | Independent of TTL | Miss path has no in-flight de-dup today | Add per-replica in-flight lookup map keyed on question hash; first request goes to LLM, others await |

### Recommended long-TTL configuration

| Setting | Value | Reason |
|---|---|---|
| `CACHE_TTL_HOURS` | **`336` (14 d) → `2160` (90 d)** as confidence grows | Start at 14 d default; extend after 2 weeks of feedback data |
| `L2_THRESHOLD` | `0.85` → `0.87` after ≥ 5 k cache entries | Compensate for growing near-neighbor set |
| `SOURCE_DOCS_VERSION` bump | **Automated in ingest** (e.g. `seed-YYYY-MM-DD-hhmm` from `ingest-corpus.ps1`) | Removes the "did the operator remember to bump?" failure mode |
| `PROMPT_VERSION` bump | Manual, versioned in Git | Prompt is source code, not data |
| 👎 feedback wiring | **Required** at long TTL | Only automatic guard against a bad answer serving weeks of traffic |
| Curated cache seed | On first deploy | Kills cold-start bias |
| Citation-integrity check | Recommended | Cheap (one Search filter per hit); prevents retrieval-drift class of failures |
| Escalation → cache eviction | Recommended | Any escalated answer's source cache entry gets deleted |

For the "replacing a semantic-search-only system" scenario specifically: the
prior system had **no invalidation at all** — you're already ahead of it as
long as `SOURCE_DOCS_VERSION` bumps on reindex. The prompt/model-version
filters are pure upside vs the legacy system, and 👎 wiring gives you a quality
signal the old system never had.

---

## Key design decisions

1. **AAD everywhere, not keys.** AOAI + Search both use managed-identity access from the Container App. `disableLocalAuth=true` on AOAI is enforced by policy.
2. **Two-tier answer cache** — see the [Response caching](#response-caching-l1-exact--l2-semantic) section above.
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
az acr build --registry $env:ACR --image cachebot-orchestrator:0.1.0 .

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
