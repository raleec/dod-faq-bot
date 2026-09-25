# Generates 25 sample FAQ text files under ..\sample-corpus\
# Content is federal / Azure Gov / RAG / SharePoint / bot themed.
$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..\sample-corpus'
New-Item -ItemType Directory -Force -Path $root | Out-Null

$docs = [ordered]@{
'01-azure-gov-regions.txt' = @"
Title: Azure Government Regions Overview

Azure Government is a dedicated cloud for U.S. federal, state, local, and tribal governments and their partners. As of 2026, generally available Azure Government regions include US Gov Virginia, US Gov Arizona, US Gov Texas, and US DoD East / US DoD Central for DoD IL5 workloads. Access requires validated eligibility and a separate portal at portal.azure.us.

FAQ answers about Azure Government should always disambiguate between Azure Government (IL2/IL4/IL5) and the two DoD-only regions (IL5). Never conflate portal.azure.com (Commercial) with portal.azure.us (Gov) or portal.azure.microsoft.scloud (Secret).
"@

'02-il4-vs-il5.txt' = @"
Title: DoD Impact Levels IL4 vs IL5

DoD Impact Level 4 (IL4) covers Controlled Unclassified Information (CUI), including export-controlled data. IL5 covers CUI that requires higher confidentiality, integrity, and availability, and National Security Systems information up to Secret when not otherwise classified.

Azure Government supports IL4 across all Gov regions. IL5 workloads must run in the US DoD East, US DoD Central, or IL5-accredited Gov regions with dedicated infrastructure and personnel. Choose IL5 only when the customer's mission owner authorization letter (MOAL) requires it, as the accreditation surface is smaller and pricing is higher.
"@

'03-aoai-gov-availability.txt' = @"
Title: Azure OpenAI Availability in Government

Azure OpenAI Service (AOAI) is available in Azure Government in US Gov Virginia and US Gov Arizona for IL4 workloads. IL5 accreditation for AOAI is progressing; check the Azure Gov compliance offerings page for the current status.

Model availability differs from Commercial. As of 2026, GPT-4o, GPT-4o-mini, text-embedding-3-large, and text-embedding-3-small are typically available in Gov. Bring-your-own-fine-tune and DALL-E are limited. Always confirm the current model list in the Azure Gov docs before writing a customer proposal.
"@

'04-aoai-quota-process.txt' = @"
Title: Requesting AOAI Quota in Azure Government

AOAI quota in Azure Government is not automatically granted. Customers must submit the AOAI Government Access & Quota form, attach a signed sponsor letter, and provide use-case details. Typical processing time is 5-15 business days.

For DoD customers on IL5, quota requests must specify DoD region, model, TPM (tokens per minute) target, and expected concurrent users. Requests for TPM > 300,000 usually require an architectural review with the AOAI Gov team.
"@

'05-rag-architecture-basics.txt' = @"
Title: RAG Architecture Basics

Retrieval-Augmented Generation (RAG) grounds a large language model's response in an approved corpus. A minimal RAG pattern is: user query -> embed query -> vector search over corpus -> pass top-k passages to LLM as context -> return grounded answer with citations.

In Azure, the reference implementation is: Azure AI Search (with a vector index) as the retrieval layer, Azure OpenAI (embeddings + chat model) as the LLM layer, and an orchestrator (Azure Function, Web App, or Bot) that chains them. Store the raw corpus in SharePoint or Blob Storage; use a Search indexer or a custom pipeline to keep the index fresh.
"@

'06-sharepoint-as-corpus.txt' = @"
Title: Using SharePoint as a RAG Corpus

SharePoint document libraries are a common corpus source for federal customers because they already hold ATO'd content and inherit existing access controls. Azure AI Search has a SharePoint Online indexer that supports incremental refresh.

Caveats: the SP indexer requires a Microsoft Entra app registration with Sites.Read.All (delegated or application), the indexer runs on Search-managed identity or an app-only Graph token, and DoD-region SP tenants (M365 GCC-High / DoD) require the Gov/DoD variant of the connector. Document-level ACL trimming is available but requires additional configuration.
"@

'07-bot-service-channels.txt' = @"
Title: Azure Bot Service Channels

Azure Bot Service supports multiple channels including Microsoft Teams, Web Chat, Direct Line, Direct Line Speech, Slack, and Email. For federal / DoD deployments, only a subset is available and each channel has its own compliance boundary.

For a Teams + Web multi-channel FAQ bot, register the bot in Azure Bot Service, enable the Teams channel, and either enable Web Chat directly or front the bot with Direct Line and host your own Web Chat control on a compliant web tier. In DoD, the Teams channel connects to Teams for GCC-High or Teams for DoD; do not mix commercial Teams with a Gov bot.
"@

'08-teams-app-manifest.txt' = @"
Title: Teams App Manifest for Bots

A Teams-side app manifest (manifest.json) declares the bot ID, scopes (personal / team / group chat), commands, and permissions. For a bot deployed via Azure Bot Service, the bot id in the manifest is the Entra AppId, not the Bot Service resource name.

Upload the app package (manifest + icons) through the Teams Admin Center for org-wide deployment. In DoD tenants, side-loading may be disabled by policy; the recommended path is publishing through Teams Admin Center with an approved appId.
"@

'09-key-vault-secrets.txt' = @"
Title: Managing Secrets with Key Vault

For a RAG bot, store the AOAI API key (if key auth is used), Bot Service Microsoft App password, and any third-party API secrets in Azure Key Vault. Grant the compute (Function, App Service, VM, Container App) a managed identity and assign the Key Vault Secrets User RBAC role.

Prefer AAD auth to AOAI over API key auth in production. When possible, set disableLocalAuth = true on the Cognitive Services account so only Entra-authenticated calls are accepted. This closes off a common exfiltration path.
"@

'10-vector-search-tuning.txt' = @"
Title: Vector Search Tuning in Azure AI Search

Azure AI Search vector fields default to HNSW with cosine similarity. Common tuning knobs are m (default 4), efConstruction (default 400), and efSearch (default 500). For most FAQ / documentation corpora with < 100k chunks, defaults are fine.

For hybrid search, populate both the search parameter (BM25 keyword) and the vectorQueries parameter. Use semanticConfiguration for reranking when quality matters more than latency. Semantic ranking is a per-query billed feature; check current pricing before enabling globally.
"@

'11-embedding-model-choice.txt' = @"
Title: Choosing an Embedding Model

For English FAQ corpora, text-embedding-3-large (3072 dims) gives higher retrieval quality than text-embedding-3-small (1536 dims) at ~2x the token cost. Small is a strong default when the corpus is < 10k chunks or latency budget is tight.

Do not mix embeddings from different models in the same index. If you upgrade the embedding model, reindex the entire corpus so all vectors share the same semantic space.
"@

'12-chunking-strategies.txt' = @"
Title: Chunking Strategies

Simple fixed-size chunking (~500 tokens with ~50 tokens of overlap) is a strong baseline for FAQ-style content. For long-form policy documents, semantic chunking on heading boundaries preserves context better.

Store metadata alongside each chunk: source document ID, source URL, section heading, page number, last-modified timestamp. This metadata powers citations in the bot response and enables filtered search (e.g., only return chunks from the current fiscal year's policy).
"@

'13-caching-layers.txt' = @"
Title: Response Caching Layers

Two cache layers are common in production RAG systems. L1 is an in-process semantic cache (near-exact match on normalized query) kept in the orchestrator's memory or in Redis. L2 is a vector-based similarity cache: store past (query, answer) pairs as vectors and reuse the answer when a new query's embedding is within a similarity threshold (e.g., cosine > 0.92) of a cached query.

L1 catches exact re-asks, L2 catches paraphrased re-asks. Both dramatically cut AOAI token spend on high-frequency FAQ traffic while preserving freshness through a TTL.
"@

'14-escalation-workflow.txt' = @"
Title: Escalating Unanswered Questions

Users should be able to flag a bot answer as incorrect or unhelpful. A standard escalation pattern is: bot renders a Flag button -> click posts to an escalation Function -> Function writes a row to a SharePoint list or Dataverse table and posts a Teams notification to the FAQ owners channel.

Include: original question, retrieved chunks, LLM answer, user identity (if consented), and a link back to the conversation. Owners triage, author a corrected answer, and either update the source doc in SharePoint (recommended, self-healing on next indexer run) or add an entry to a curated overrides index.
"@

'15-ato-basics.txt' = @"
Title: Federal ATO Basics

An Authority to Operate (ATO) is a formal decision by an authorizing official (AO) that a system may operate in production and accept residual risk. Federal ATOs are typically issued under NIST SP 800-37 (Risk Management Framework) and require completing a security package (SSP, SAR, POA&M).

Azure Government has FedRAMP High provisional ATO; workloads deployed on top must still complete their own ATO. Reuse the underlying platform's inheritable controls to reduce customer-side burden. For DoD, the analogous framework is the DoD RMF and the Cloud Computing SRG for cloud eligibility.
"@

'16-cmmc-overview.txt' = @"
Title: CMMC Overview

The Cybersecurity Maturity Model Certification (CMMC) applies to DoD contractors handling FCI and CUI. CMMC 2.0 defines three levels: Level 1 (Foundational, self-assessed), Level 2 (Advanced, third-party assessed for prioritized contracts), and Level 3 (Expert, government assessed).

Azure Government supports customer CMMC compliance up to Level 2 for CUI workloads. Level 3 typically requires additional controls the customer implements on top of the platform. Point customers to the CMMC readiness assessment offering and the Azure compliance blueprints.
"@

'17-msi-vs-key-auth.txt' = @"
Title: Managed Identity vs Key Auth

Managed identities (MI) let Azure resources authenticate to other Azure resources without secrets. There are system-assigned MIs (lifecycle tied to the resource) and user-assigned MIs (shared across resources). Prefer MI over API keys wherever supported.

For AOAI and Azure AI Search, both support Entra-based RBAC. Data-plane RBAC propagation can take 5 to 20 minutes; test after the assignment settles. If a workload cannot use MI (e.g., legacy client, cross-tenant), fall back to Key Vault-managed API keys and rotate on a schedule.
"@

'18-cost-optimization.txt' = @"
Title: Cost Optimization for RAG Bots

For an FAQ bot at ~10k monthly queries, cost is dominated by AOAI tokens (chat + embeddings) and Search compute. Levers: (a) cache aggressively (L1 exact + L2 semantic), (b) prefer smaller chat models where quality allows (gpt-4o-mini over gpt-4o), (c) trim top-k passages before sending to the LLM, (d) use lower-dim embeddings for L1/L2 caches to cut storage cost.

Budget guidance for ~10k queries/month with a 25-doc corpus: AOAI ~$150-400, Search Basic $75, App Service or Function ~$50, Bot Service free tier, Key Vault + monitoring < $10. Add ~30% headroom for spikes.
"@

'19-monitoring-observability.txt' = @"
Title: Monitoring and Observability

Instrument every RAG hop with Application Insights: query received, cache hit/miss (L1, L2), retrieval latency, top-k chunk IDs and scores, LLM latency and token counts, final answer length, user feedback signal.

Track per-tenant metrics if the bot serves multiple orgs. Add a weekly Kusto (KQL) report of top questions, top low-confidence queries, and cache hit rate. Low-confidence queries are the pipeline into the escalation queue.
"@

'20-privacy-and-pii.txt' = @"
Title: Privacy and PII Handling

Do not log full user messages or LLM responses without a redaction pass. Use Azure AI Language PII detection or a regex+ML combo to redact SSNs, DoD IDs, CAC numbers, phone numbers, and email addresses from telemetry.

For DoD, avoid capturing user identity beyond what the ATO requires. Session correlation IDs are typically sufficient. If you must store conversation transcripts, encrypt at rest with a customer-managed key (CMK) in Key Vault and enforce a retention policy.
"@

'21-sharepoint-indexer-limits.txt' = @"
Title: SharePoint Indexer Limits

The Azure AI Search SharePoint Online indexer supports .docx, .pptx, .xlsx, .pdf, .html, .txt, and a few image formats via OCR skill. Individual document size limit is 16 MB for indexer parsing.

The indexer runs on a schedule (min every 5 minutes) or on demand. It supports incremental refresh via SharePoint change tokens. Item-level ACLs are not applied to search results by default; use the securityTrimming feature and pass the caller's group SIDs at query time if the customer requires ACL trimming.
"@

'22-basic-vs-standard-search.txt' = @"
Title: Search SKU: Basic vs Standard

Azure AI Search Basic (~$75/mo) is fine for a pilot with < 1M documents and low QPS. Standard S1 (~$250/mo) unlocks higher storage, more partitions/replicas, and (critically for RAG) shared private link support so a Search skillset can call a private-endpointed AOAI or Cognitive Services account.

SKU upgrades are not in-place. To move Basic to Standard, provision a new Standard service, replicate indexes and indexers, cut over endpoints, then delete the Basic service. Plan the cutover for a maintenance window.
"@

'23-defender-for-cloud.txt' = @"
Title: Defender for Cloud Baseline

Microsoft Defender for Cloud provides secure score, regulatory compliance dashboards (FedRAMP, NIST 800-53, CMMC L2, DoD IL4/IL5), and workload protection plans for AI services, App Service, Key Vault, and Storage.

Enable Defender for AI services once AOAI is deployed. It surfaces prompt-injection attempts, jailbreak patterns, and abnormal token consumption. Configure alerts to the SOC's SIEM (Sentinel or Splunk) via a Log Analytics workspace export.
"@

'24-network-isolation.txt' = @"
Title: Network Isolation Patterns

For a locked-down RAG deployment, put AOAI, Search, Key Vault, and Storage behind private endpoints in a hub VNet. Front the bot with an App Gateway or Front Door with WAF. VM-based orchestrators need only private IPs; use Azure Bastion for admin access.

Note: AI Search Basic does not support shared private link to reach a private-endpointed AOAI from a skillset. If you need indexer-side enrichment against private-only AOAI, use Search Standard S1 or higher.
"@

'25-teardown-checklist.txt' = @"
Title: Pilot Teardown Checklist

At the end of a pilot, delete: the resource group (removes all contained resources), the bot Microsoft Entra app registration (does not live in the RG), any soft-deleted Key Vaults (purge to release the name), and any soft-deleted Cognitive Services accounts (purge to release the name and free the subscription-level quota for that model).

Also review: role assignments (do the identities still need access to anything else?), custom Entra app consents, DNS records, budget alerts, and diagnostic settings pointing to a Log Analytics workspace outside the pilot RG. Document the teardown timestamp and the final cost in the pilot closeout report.
"@
}

foreach ($f in $docs.Keys) {
    $path = Join-Path $root $f
    Set-Content -Path $path -Value $docs[$f] -Encoding UTF8
}
Write-Host "Wrote $($docs.Count) files to $root"
