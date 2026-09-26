// Generates DoD-FAQ-Bot-Architecture.docx
const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, PageOrientation, LevelFormat,
  TabStopType, TabStopPosition, HeadingLevel, BorderStyle, WidthType,
  ShadingType, PageNumber, PageBreak, TableOfContents, ExternalHyperlink
} = require('docx');

const OUT = path.join(__dirname, 'DoD-FAQ-Bot-Architecture.docx');

// ------ palette ------
const NAVY = '1E2761';
const TEAL = '028090';
const SLATE = '36454F';
const LIGHT = 'F2F4F8';
const BORDER = 'CCCCCC';

const border = { style: BorderStyle.SINGLE, size: 4, color: BORDER };
const cellBorders = { top: border, bottom: border, left: border, right: border };

// ------ helpers ------
const p = (text, opts = {}) => new Paragraph({
  spacing: { after: 120 },
  ...opts,
  children: (Array.isArray(text) ? text : [new TextRun({ text, ...(opts.run || {}) })])
});

const h1 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_1,
  spacing: { before: 320, after: 160 },
  children: [new TextRun({ text })]
});

const h2 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_2,
  spacing: { before: 240, after: 120 },
  children: [new TextRun({ text })]
});

const bullet = (text, level = 0) => new Paragraph({
  numbering: { reference: 'bullets', level },
  spacing: { after: 60 },
  children: [new TextRun({ text })]
});

const numbered = (text) => new Paragraph({
  numbering: { reference: 'numbers', level: 0 },
  spacing: { after: 60 },
  children: [new TextRun({ text })]
});

// A table row with an optional header style.
const cell = (text, opts = {}) => new TableCell({
  borders: cellBorders,
  width: { size: opts.width, type: WidthType.DXA },
  shading: opts.header ? { fill: NAVY, type: ShadingType.CLEAR } : undefined,
  margins: { top: 80, bottom: 80, left: 120, right: 120 },
  children: [new Paragraph({
    children: [new TextRun({
      text,
      bold: opts.header || opts.bold || false,
      color: opts.header ? 'FFFFFF' : '212121',
      size: 20
    })]
  })]
});

// Build a table given column widths and rows (rows = array of arrays of strings).
const makeTable = (columnWidths, headerCells, dataRows) => {
  const totalWidth = columnWidths.reduce((a, b) => a + b, 0);
  return new Table({
    width: { size: totalWidth, type: WidthType.DXA },
    columnWidths,
    rows: [
      new TableRow({
        tableHeader: true,
        children: headerCells.map((t, i) => cell(t, { width: columnWidths[i], header: true }))
      }),
      ...dataRows.map(row => new TableRow({
        children: row.map((t, i) => cell(t, { width: columnWidths[i] }))
      }))
    ]
  });
};

// ------ document children ------
const children = [];

// Title block
children.push(new Paragraph({
  alignment: AlignmentType.CENTER,
  spacing: { before: 2400, after: 240 },
  children: [new TextRun({ text: 'CACHEBOT', bold: true, size: 56, color: NAVY, font: 'Arial' })]
}));
children.push(new Paragraph({
  alignment: AlignmentType.CENTER,
  spacing: { after: 120 },
  children: [new TextRun({ text: 'Reference Architecture — Azure Government (IL5)', size: 32, color: TEAL, font: 'Arial' })]
}));
children.push(new Paragraph({
  alignment: AlignmentType.CENTER,
  spacing: { after: 4800 },
  children: [new TextRun({ text: 'Teams + Web  •  Azure OpenAI GPT-4o  •  AI Search  •  SharePoint RAG', size: 22, color: SLATE, italics: true })]
}));
children.push(new Paragraph({
  alignment: AlignmentType.CENTER,
  children: [new TextRun({ text: 'Prepared by: Ralee Cook, Sr Cloud Solution Architect — Microsoft Federal CAIP', size: 20 })]
}));
children.push(new Paragraph({
  alignment: AlignmentType.CENTER,
  children: [new TextRun({ text: 'Date: 27 July 2026  •  Version: 0.1 (Draft)', size: 20 })]
}));
children.push(new Paragraph({ children: [new PageBreak()] }));

// TOC
children.push(h1('Table of Contents'));
children.push(new TableOfContents('Contents', { hyperlink: true, headingStyleRange: '1-2' }));
children.push(new Paragraph({ children: [new PageBreak()] }));

// 1. Executive Summary
children.push(h1('1. Executive Summary'));
children.push(p('This document describes the reference architecture, cost model, and deployment approach for an FAQ bot serving a U.S. Department of Defense (DoD) customer. The bot uses a retrieval-augmented generation (RAG) pattern with a Microsoft-hosted large language model, sourcing its authoritative content from a customer SharePoint Online document library. End users interact through Microsoft Teams and an embeddable web chat control.'));
children.push(p('The solution is deployed entirely inside the Azure Government DoD boundary, uses Azure Government-eligible services, and is designed to meet IL5 controls. The target monthly Azure run rate at "fairly high" usage (~50,000 queries/month) is approximately US$2,500.'));

children.push(h2('1.1 Key decisions'));
children.push(bullet('LLM: Azure OpenAI Service (Government), model gpt-4o for chat completions and text-embedding-3-large for RAG embeddings.'));
children.push(bullet('Retrieval: Azure AI Search, Standard S1, hybrid BM25 + vector with semantic ranker enabled.'));
children.push(bullet('Ingest: AI Search built-in SharePoint Online indexer, incremental crawl using the SharePoint change log.'));
children.push(bullet('Compute: Ubuntu 22.04 LTS on Azure VM Standard_D4s_v5 hosting a containerised orchestrator API (per user requirement to use an Azure VM).'));
children.push(bullet('Channels: Azure Bot Service with Microsoft Teams channel + Direct Line for a web-embed chat control.'));
children.push(bullet('Escalation: an "Escalate" button on every bot response opens a triage flow. Question, answer, retrieved chunks, and user identity are written to a SharePoint list, and a triage Teams channel receives an @mention with a deep link to the item.'));
children.push(bullet('Response caching (two-tier): L1 in-process LRU on the orchestrator VM for exact-match repeats; L2 semantic cache implemented as a second Azure AI Search index on the existing service, keyed by query embedding + source-docs version hash. No new Azure resources.'));
children.push(bullet('Region: usgovvirginia primary, usgovarizona for DR failover consideration.'));

// 2. Requirements
children.push(h1('2. Requirements'));
children.push(h2('2.1 Functional'));
children.push(bullet('Users in Microsoft Teams (DoD tenant) can ask questions in natural language and receive concise, cited answers.'));
children.push(bullet('The same bot serves an embeddable web chat control on a customer intranet page.'));
children.push(bullet('Every answer includes at least one citation linking back to the source SharePoint document.'));
children.push(bullet('The bot refuses to answer when retrieval confidence is below a configurable threshold, and offers to escalate to the human triage team instead.'));
children.push(bullet('Every response exposes an Escalate action. Users can flag either an incorrect answer or a completely unanswered question, optionally add a comment, and are told the item has been routed to the triage team.'));
children.push(bullet('The triage team receives every escalation in a dedicated SharePoint list plus an @mention in a Teams channel; each item captures the exchange, the retrieved passages, the model version, and the user identity so it can be triaged without re-interviewing the user.'));
children.push(bullet('Triage team can (a) reply directly to the user (proactive Teams message via Bot Framework), (b) edit or add a source document in SharePoint (re-index picks it up on the next crawl), or (c) close as no-action with a reason code.'));

children.push(h2('2.2 Non-functional'));
children.push(bullet('Deployed in Azure Government DoD; no data or telemetry leaves the boundary.'));
children.push(bullet('Meets DoD IL5 security controls (private endpoints, disabled local auth on AOAI, RBAC everywhere, managed identity on the VM).'));
children.push(bullet('Answer latency P95 < 4 seconds under normal load.'));
children.push(bullet('Cost ceiling ≈ US$2,500 per month at ~50k queries/month.'));
children.push(bullet('Documents in the source SharePoint library respect user-level access at click-through; the bot itself operates with a scoped service identity that only reads the designated library.'));

// 3. Architecture
children.push(h1('3. Architecture'));
children.push(p('The solution is a classic RAG pattern with a thin orchestrator sitting between the chat channel and the model + retriever. All data-plane traffic is contained inside the customer\'s Azure Government vNet via private endpoints.'));
children.push(h2('3.1 Logical view'));
children.push(p('[Insert architecture diagram — see slide 4 of DoD-FAQ-Bot-Overview.pptx or bicep/README.md for the deployed topology.]', { run: { italics: true, color: SLATE } }));

children.push(h2('3.2 Components'));
children.push(makeTable(
  [1800, 2400, 5160],
  ['Layer', 'Azure service', 'Purpose'],
  [
    ['Channel', 'Azure Bot Service (S1)', 'Multi-channel bot; Teams channel + Direct Line for web embed.'],
    ['Compute', 'Azure VM Standard_D4s_v5, Ubuntu 22.04', 'Hosts the containerised orchestrator API. System-assigned managed identity.'],
    ['LLM', 'Azure OpenAI (Gov) — gpt-4o + text-embedding-3-large', 'Chat completions + embeddings. Private endpoint, AAD auth only.'],
    ['Retrieval', 'Azure AI Search, Standard S1', 'Hybrid vector + BM25 index with semantic ranker.'],
    ['Ingest', 'AI Search SharePoint Online indexer', 'Incremental crawl of one or more libraries via SharePoint change log.'],
    ['Source', 'SharePoint Online (DoD / GCC-High)', 'The authoritative document library. Access preserved at click-through.'],
  ['Escalation store', 'SharePoint Online custom list "FAQ Escalations"', 'One row per escalation. Columns: question, answer, retrieved chunk IDs, user UPN, channel, status, triage owner, resolution notes.'],
  ['Escalation notify', 'Microsoft Graph -> Teams channel message', 'Bot app posts an @mention with a deep link to the SharePoint list item into a "CACHEBOT - Triage" Teams channel.'],
  ['Secrets', 'Azure Key Vault Premium', 'RBAC-only, purge-protected, private endpoint. Stores bot MSA secret and any bootstrap secrets.'],
  ['Observability', 'Log Analytics + Application Insights', 'Traces, cost signals, answer-quality telemetry, escalation-rate KPI.'],
  ['Identity', 'Microsoft Entra ID (Government)', 'Managed identity on the VM; app registration for the bot with Sites.Selected on the escalations list + ChannelMessage.Send.Group on the triage team.']
  ]
));

// 4. Data flow
children.push(h1('4. Data flow'));
children.push(h2('4.1 Indexing pipeline'));
children.push(numbered('The AI Search SharePoint indexer polls the designated library on a fixed schedule (e.g., every hour) using the SharePoint change log for incremental updates.'));
children.push(numbered('New or changed documents are cracked (text extracted), chunked (~1,000 tokens per chunk with ~100-token overlap), and embedded via the text-embedding-3-large deployment on AOAI.'));
children.push(numbered('Chunks with vector fields + metadata (source URL, title, last-modified) are written to the vector index in AI Search.'));

children.push(h2('4.2 Query pipeline'));
children.push(numbered('User posts a question in Teams or the web chat control.'));
children.push(numbered('Bot Service relays the activity to the orchestrator API endpoint on the VM.'));
children.push(numbered('Orchestrator embeds the query, issues a hybrid search against the AI Search index (top-k = 8, with semantic reranking), and assembles the top passages into a prompt template with citation instructions.'));
children.push(numbered('AOAI gpt-4o generates the answer. Orchestrator post-processes to strip hallucinated citations and returns the response with clickable SharePoint links.'));
children.push(numbered('Bot response is delivered as an Adaptive Card with two actions in the footer: "Helpful" (positive feedback signal) and "Escalate" (opens the escalation dialog).'));
children.push(numbered('All spans (retrieve, embed, complete) are traced to Application Insights.'));

children.push(h2('4.3 Escalation flow'));
children.push(numbered('User clicks Escalate on any bot response, or the orchestrator auto-offers escalation when retrieval confidence is below threshold. A short Adaptive Card dialog asks the user to pick a reason ("Answer is wrong", "Bot said it did not know", "Answer is incomplete", "Other") and add an optional comment.'));
children.push(numbered('Orchestrator writes a row to the "FAQ Escalations" SharePoint list using Microsoft Graph (Sites.Selected on that list only). The row captures: user UPN, channel (Teams or Web), timestamp, original question, generated answer, retrieved chunk IDs + source URLs, model + prompt-template version, reason code, and free-text comment.'));
children.push(numbered('Immediately after the write, the orchestrator posts an Adaptive Card into the "CACHEBOT — Triage" Teams channel with an @mention of the on-call triage owner group, a summary of the question, and a deep link to the SharePoint list item. Posting uses application-permissions ChannelMessage.Send.Group scoped to the single triage team.'));
children.push(numbered('The user sees a confirmation ("Thanks — this has been sent to the triage team as ticket #NNN. You will hear back in this chat when it is resolved.").'));
children.push(numbered('Triage team works the item in SharePoint. When they mark it Resolved, a lightweight Power Automate flow (or Logic App) triggers a Bot Framework proactive message back to the original user with the answer and, if the source docs were updated, a note that the bot will now answer this itself.'));

children.push(h2('4.4 Escalation-driven quality loop'));
children.push(bullet('Escalations are the primary source of ground-truth for content gaps. Weekly review by the customer\'s content owners.'));
children.push(bullet('Recurring escalations on the same topic surface as a KPI dashboard tile ("top 10 unanswered themes this week"). This drives edits to the source SharePoint library — no changes to the bot itself.'));
children.push(bullet('When a source doc is updated, the AI Search indexer re-crawls on its normal schedule and the bot answers correctly on the next attempt.'));

children.push(h2('4.5 Response caching (two-tier)'));
children.push(p('A two-tier semantic cache is included from the pilot. It cuts LLM cost on repeated questions (a heavily long-tailed distribution for FAQ workloads) and reduces P95 latency to tens of milliseconds on cache hits.'));

children.push(makeTable(
  [1200, 2000, 2200, 1400, 2560],
  ['Tier', 'Where', 'Hit criteria', 'TTL', 'Purpose'],
  [
    ['L1 exact', 'In-process LRU on the orchestrator VM (~10k entries, ~50 MB RAM).', 'Normalized-string equality of question.', '1 hour', 'Catch identical repeats; near-zero latency; zero infra cost.'],
    ['L2 semantic', 'Second Azure AI Search index (cachebot-cache) on the same S1 service.', 'Cosine similarity between query embedding and cached-query embedding >= 0.95.', '24 hours', 'Catch paraphrases; rides on the AI Search + private endpoint you already pay for.']
  ]
));

children.push(h2('4.5.1 Cache key and payload'));
children.push(bullet('Key: SHA-256 of normalized question + source-docs version hash + prompt-template version. When any source SharePoint document changes, the version hash rolls and the cache is effectively invalidated for that topic.'));
children.push(bullet('Payload stored: question, answer, citations, query embedding (for L2 similarity search), retrieved chunk IDs, sourceDocsVersion, promptVersion, modelVersion, createdAt.'));

children.push(h2('4.5.2 Cache-write rules (what NOT to cache)'));
children.push(bullet('Retrieval confidence below the escalation threshold — the answer is uncertain; do not amplify.'));
children.push(bullet('Cited source document carries a sensitivity label above a configurable threshold (e.g., anything above "Internal").'));
children.push(bullet('User is on the always-fresh allowlist (e.g., leadership) or query is flagged personal / time-sensitive.'));
children.push(bullet('Escalation was raised on this answer — the entry is immediately invalidated regardless of TTL.'));

children.push(h2('4.5.3 Cost + latency impact'));
children.push(makeTable(
  [3000, 3200, 3160],
  ['Cache hit rate', 'Monthly gpt-4o spend at 50k queries', 'Savings vs. no cache'],
  [
    ['0% (no cache)', '~$900', '—'],
    ['20%', '~$720', '~$180 / mo'],
    ['40%', '~$540', '~$360 / mo'],
    ['60%', '~$360', '~$540 / mo']
  ]
));
children.push(p('L1 latency: ~1 ms. L2 latency: ~30-60 ms (single vector call to AI Search on the private endpoint). Full pipeline (miss): 2-4 s.'));

// 5. Security & compliance
children.push(h1('5. Security & Compliance'));
children.push(bullet('Deployment target: Azure Government (usgovvirginia). All services chosen are IL5-eligible.'));
children.push(bullet('Private endpoints on AOAI, AI Search, Key Vault, and monitoring ingestion. Public network access disabled.'));
children.push(bullet('Local auth (API keys) disabled on Azure OpenAI. Orchestrator authenticates with AAD via its managed identity.'));
children.push(bullet('Key Vault: RBAC authorization only, soft-delete + purge protection on, network default-deny.'));
children.push(bullet('Least-privilege role assignments on the orchestrator managed identity: Cognitive Services OpenAI User, Search Index Data Reader, Key Vault Secrets User.'));
children.push(bullet('Bot app-registration Graph permissions: Sites.Selected (scoped to the FAQ Escalations list only, not the whole tenant) and ChannelMessage.Send.Group (scoped to the triage Teams channel only). Both require admin consent and are audit-logged.'));
children.push(bullet('Data classification treated as CUI. Sensitivity labels on source SharePoint documents propagate as retrieval metadata but are not exposed to end users beyond the citation click-through.'));
children.push(bullet('All logs go to a workspace-based Log Analytics with 90-day retention (extendable per customer archive policy).'));
children.push(bullet('Bot Framework relay itself is a global service; the Teams channel binding uses the DoD-approved deployment environment. This is called out as an assumption to be confirmed against the customer\'s ATO evidence set.'));

// 6. Cost model
children.push(h1('6. Cost Model'));
children.push(p('Monthly run-rate estimate at approximately 50,000 queries/month, with headroom for indexing bursts and observability. All prices are illustrative Azure Government retail; verify against your EA before commit.'));

children.push(makeTable(
  [3200, 3000, 3160],
  ['Item', 'Assumption', 'Est. USD / month'],
  [
    ['Azure OpenAI — gpt-4o chat', '~15M input + 3M output tokens', '$900'],
    ['Azure OpenAI — embeddings', '5M tokens (indexing + queries)', '$30'],
    ['Azure AI Search Standard S1', '1 replica, 1 partition, semantic on', '$370'],
    ['VM Standard_D4s_v5 (1-yr reserved)', 'Ubuntu, 4 vCPU / 16 GB', '$220'],
    ['Azure Bot Service', 'S1 tier', '$50'],
    ['Storage + bandwidth', 'Logs, blobs, PE traffic', '$60'],
    ['App Insights + Log Analytics', 'Moderate ingestion, 90-day retention', '$120'],
    ['Key Vault Premium + networking + DNS', 'Base + PE hours', '$80'],
    ['Subtotal', '', '~$1,830'],
    ['Buffer (spikes, re-indexing, growth)', '', '~$670'],
    ['Target monthly total', '', '~$2,500']
  ]
));

children.push(h2('6.1 Cost levers'));
children.push(bullet('Response caching is in from pilot (see section 4.5). At 40% hit rate, the LLM line drops from ~$900 to ~$540, giving ~$360/mo back.'));
children.push(bullet('Route ~80% of routine queries to gpt-4o-mini and reserve gpt-4o for high-complexity fallbacks; drops LLM spend a further ~85% on those routes.'));
children.push(bullet('Move the VM to a 3-year reserved instance for an additional ~20% off compute.'));
children.push(bullet('Downgrade AI Search to Basic if the semantic ranker is not needed — saves ~$120/mo but forfeits reranking quality and forces the L2 semantic cache onto a separate service.'));

// 7. Deployment
children.push(h1('7. Deployment Sequence'));
children.push(numbered('Confirm Azure Government subscription + IL5 enclave; verify SharePoint tenant is in DoD (or GCC-High) and reachable by AI Search.'));
children.push(numbered('Submit and land Azure OpenAI quota (see aoai-quota-request.md).'));
children.push(numbered('Register the bot app in Entra Gov with delegated permissions to read the target SharePoint library.'));
children.push(numbered('Deploy the infrastructure using the Bicep skeleton in bicep/ (subscription-scope deployment; see bicep/README.md).'));
children.push(numbered('Configure the SharePoint indexer on AI Search (data-plane configuration, not ARM). Provision the second AI Search index for the L2 semantic cache (cachebot-cache) using the schema in deploy/configure-cache-index.ps1.'));
children.push(numbered('Build and push the orchestrator container image to the customer\'s ACR; the VM cloud-init pulls and runs it. Orchestrator ships with L1 LRU + L2 semantic cache enabled by default; cache TTLs and no-cache allowlists are configurable via Key Vault.'));
children.push(numbered('Provision the "FAQ Escalations" SharePoint list, create the "CACHEBOT — Triage" Teams channel, grant Sites.Selected + ChannelMessage.Send.Group to the bot app registration, and validate an end-to-end escalation with a test user.'));
children.push(numbered('Wire the Bot Service Teams channel + Direct Line site; publish the Teams manifest and the web-embed HTML.'));
children.push(numbered('Pilot with a small user group, iterate on chunk size, top-k, and system prompt based on Application Insights telemetry. Track escalation rate as the primary quality KPI.'));

// 8. Risks
children.push(h1('8. Risks & Assumptions'));
children.push(makeTable(
  [1600, 4400, 3360],
  ['#', 'Risk / assumption', 'Mitigation'],
  [
    ['R1', 'AOAI quota (gpt-4o) not yet granted in the target Gov region.', 'File the quota request immediately (see aoai-quota-request.md); block-deploy AI Search + VM in parallel.'],
    ['R2', 'SharePoint tenant is not in the same compliance boundary as the Azure Gov subscription.', 'Confirm tenant is DoD or GCC-High before design freeze; otherwise re-scope ingestion (e.g., staged copy via a customer-owned service).'],
    ['R3', 'Bot Framework Teams channel binding for DoD requires the correct deployment environment.', 'Validate with a pilot Teams tenant; confirm channel is functional under the customer\'s ATO before broad rollout.'],
    ['R4', 'Answer quality degrades on long / structured documents (e.g., regulations).', 'Tune chunking, add semantic ranker, and evaluate periodically with a fixed 50-question regression set.'],
    ['R5', 'Cost overrun if usage exceeds 50k queries/mo.', 'Set an Azure budget alert at 90% of target; enable per-route model routing (gpt-4o-mini fallback).']
  ]
));

// 9. Appendix
children.push(h1('9. Appendix'));
children.push(h2('9.1 Related artefacts'));
children.push(bullet('bicep/ — Infrastructure-as-Code skeleton.'));
children.push(bullet('aoai-quota-request.md — Draft submission for Azure OpenAI (Gov) quota.'));
children.push(bullet('DoD-FAQ-Bot-Overview.pptx — Executive summary deck for stakeholders.'));

children.push(h2('9.2 Open questions for the customer'));
children.push(bullet('Confirm IL5 vs IL4 classification of the workload.'));
children.push(bullet('Confirm SharePoint tenant boundary (DoD vs GCC-High).'));
children.push(bullet('Expected concurrent users and peak QPS.'));
children.push(bullet('Preference for pay-as-you-go vs Provisioned Throughput Units (PTUs) on AOAI.'));
children.push(bullet('Web chat hosting location: existing internal portal or a new one?'));

// ------ document ------
const doc = new Document({
  creator: 'Ralee Cook',
  title: 'CACHEBOT — Reference Architecture',
  styles: {
    default: {
      document: { run: { font: 'Arial', size: 22 } }
    },
    paragraphStyles: [
      {
        id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 34, bold: true, color: NAVY, font: 'Arial' },
        paragraph: { spacing: { before: 320, after: 160 }, outlineLevel: 0 }
      },
      {
        id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 26, bold: true, color: TEAL, font: 'Arial' },
        paragraph: { spacing: { before: 240, after: 120 }, outlineLevel: 1 }
      }
    ]
  },
  numbering: {
    config: [
      {
        reference: 'bullets',
        levels: [
          { level: 0, format: LevelFormat.BULLET, text: '\u2022', alignment: AlignmentType.LEFT,
            style: { paragraph: { indent: { left: 540, hanging: 270 } } } },
          { level: 1, format: LevelFormat.BULLET, text: '\u25E6', alignment: AlignmentType.LEFT,
            style: { paragraph: { indent: { left: 1080, hanging: 270 } } } }
        ]
      },
      {
        reference: 'numbers',
        levels: [{
          level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 540, hanging: 270 } } }
        }]
      }
    ]
  },
  sections: [{
    properties: {
      page: {
        size: { width: 12240, height: 15840 },
        margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 }
      }
    },
    headers: {
      default: new Header({
        children: [new Paragraph({
          alignment: AlignmentType.RIGHT,
          children: [new TextRun({ text: 'CACHEBOT — Reference Architecture', size: 18, color: SLATE, italics: true })]
        })]
      })
    },
    footers: {
      default: new Footer({
        children: [new Paragraph({
          tabStops: [{ type: TabStopType.RIGHT, position: TabStopPosition.MAX }],
          children: [
            new TextRun({ text: 'Microsoft Federal — CAIP CSU', size: 18, color: SLATE }),
            new TextRun({ text: '\tPage ', size: 18, color: SLATE }),
            new TextRun({ children: [PageNumber.CURRENT], size: 18, color: SLATE }),
            new TextRun({ text: ' of ', size: 18, color: SLATE }),
            new TextRun({ children: [PageNumber.TOTAL_PAGES], size: 18, color: SLATE })
          ]
        })]
      })
    },
    children
  }]
});

Packer.toBuffer(doc).then(buf => {
  fs.writeFileSync(OUT, buf);
  console.log('Wrote', OUT, buf.length, 'bytes');
});
