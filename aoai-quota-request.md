# Azure OpenAI (Gov) Quota Request — DoD FAQ Bot

Use this content when submitting the **Azure OpenAI Service Request Form** for
Azure Government / DoD. The current intake is at:

- Azure Gov customers: https://aka.ms/oaigovaccess (or the tenant's
  Microsoft AI Sales POC will route the request internally).
- Model-specific TPM increases go through the standard Azure Portal support
  request path under `Service and subscription limits (quotas) → Cognitive
  Services`.

---

**Requested API permissions on the bot app registration**

| Permission | Type | Scope | Purpose |
|---|---|---|---|
| `Sites.Selected` | Application | The single "FAQ Escalations" list only | Write escalation rows |
| `ChannelMessage.Send.Group` | Application | The single triage Team only | Post @mention into the triage channel |

(Neither permission grants tenant-wide read.)

---

## Form field draft

**Requestor name / email**
Ralee Cook — raleecook@microsoft.com

**Microsoft Federal team**
Cloud & AI Platforms CSU (CAIP), Federal (dept USPSI_COGS_CSU_CAIP_FED_1001).
Manager: TJ Lindroos.

**Customer / tenant name**
[CUSTOMER NAME] — DoD organization operating in Azure Government.
Tenant ID: [TENANT-GUID]

**Azure subscription ID(s)**
[SUB-GUID-1] (production)
[SUB-GUID-2] (non-production, if applicable)

**Deployment cloud**
Azure Government (DoD).

**Requested region(s)**
- Primary: `usgovvirginia`
- Secondary (failover): `usgovarizona`

**Compliance boundary**
- DoD IL5 workload.
- Data classification: CUI (Controlled Unclassified Information).
- All ingest and inference traffic remains inside the Azure Gov boundary via
  private endpoints; no data leaves the enclave.

---

## Models & quota requested

| Model | Version | Deployment SKU | Quota requested (TPM) | Purpose |
|---|---|---|---|---|
| `gpt-4o` | 2024-11-20 | Standard | **240,000** TPM | Chat completions for the FAQ bot answer generation |
| `text-embedding-3-large` | 1 | Standard | **120,000** TPM | Document + query embeddings for the RAG index |

Rationale for the TPM figures:

- ~50,000 user queries per month at peak.
- Average request: ~300 input + 60 output tokens = ~360 tokens/query.
- Peak concurrency assumed ~10 QPS during business hours, giving a working
  ceiling of ~216,000 TPM. Requesting **240,000 TPM** provides ~10% headroom
  and room to enable answer-with-citations expansion prompts.
- Embeddings TPM covers full re-indexing bursts (~500k documents × ~1,000
  tokens over a 24-hour window) plus per-query embed cost.

If **Provisioned Throughput Units (PTUs)** are required by DoD tenant policy
in place of pay-as-you-go, the equivalent request is:
- gpt-4o: **50 PTUs**
- embeddings: pay-as-you-go retained.

---

## Business justification

The customer is a DoD organization standardizing on Microsoft Federal cloud
services. Their end-user population needs a single, authoritative Q&A surface
across a large SharePoint document library. Existing "search the intranet"
UX yields low answer quality and drives ticket volume to support desks.

An Azure OpenAI-powered FAQ bot with SharePoint-grounded RAG will:

- Deflect an estimated 30–40% of tier-1 support tickets.
- Give users a single Teams + web experience for policy, HR, and technical
  documentation queries.
- Preserve document-level authorization by citing every answer back to the
  source SharePoint item (users click through to the record they already have
  access to).

Deployment is architected against Azure Government IL5 controls with all
private endpoints, disabled local auth on AOAI, and Entra Gov managed
identities on the orchestrator VM. Architecture doc:
`DoD-FAQ-Bot-Architecture.docx`.

---

## Timeline

- Quota decision needed by: **[REQUESTED-DATE, e.g., 15 Aug 2026]**
- Pilot go-live target: **~6 weeks after quota + subscription readiness**
- Estimated first-year run rate: ~$30k (matches the ~$2.5k/mo Cost Model in
  the architecture doc).

---

## Contacts

| Role | Name | Email |
|---|---|---|
| Requesting CSA | Ralee Cook | raleecook@microsoft.com |
| Manager | TJ Lindroos | TJ.Lindroos@microsoft.com |
| Peer / architecture reviewer | John Spinella (Principal CSA, CAIP Fed) | John.Spinella@microsoft.com |
| Customer technical POC | [CUSTOMER NAME] | [customer@email.mil] |

---

## Attachments to include with the submission

1. Architecture design doc (`DoD-FAQ-Bot-Architecture.docx`).
2. Executive summary deck (`DoD-FAQ-Bot-Overview.pptx`).
3. Signed customer authorization letter (if required by intake).
4. Network diagram excerpt showing private-endpoint topology (page 4 of the
   architecture doc).
