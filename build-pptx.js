// Generates DoD-FAQ-Bot-Overview.pptx
const pptxgen = require('pptxgenjs');
const path = require('path');

const OUT = path.join(__dirname, 'DoD-FAQ-Bot-Overview.pptx');

const p = new pptxgen();
p.author = 'Ralee Cook';
p.company = 'Microsoft Federal - CAIP';
p.title = 'DoD FAQ Bot - Overview';
p.layout = 'LAYOUT_WIDE'; // 13.333 x 7.5 in

// Palette: Ocean Gradient
const DEEP = '065A82';
const TEAL = '1C7293';
const MIDNIGHT = '21295C';
const CREAM = 'F5F7FA';
const WHITE = 'FFFFFF';
const MUTED = '6B7A99';
const ACCENT = '3AC0C0';

const FONT_H = 'Georgia';
const FONT_B = 'Calibri';

const footer = (slide, num, total) => {
  slide.addShape('rect', { x: 0, y: 7.15, w: 13.333, h: 0.35, fill: { color: MIDNIGHT }, line: { color: MIDNIGHT } });
  slide.addText('DoD FAQ Bot  |  Reference Architecture', {
    x: 0.4, y: 7.15, w: 8, h: 0.35, fontFace: FONT_B, fontSize: 10, color: 'CADCFC'
  });
  slide.addText(`${num} / ${total}`, {
    x: 12.4, y: 7.15, w: 0.6, h: 0.35, fontFace: FONT_B, fontSize: 10, color: 'CADCFC', align: 'right'
  });
};

const TOTAL = 10;

// ============ SLIDE 1 - Title ============
{
  const s = p.addSlide();
  s.background = { color: MIDNIGHT };
  // Accent bar
  s.addShape('rect', { x: 0, y: 0, w: 0.35, h: 7.5, fill: { color: ACCENT }, line: { color: ACCENT } });
  s.addText('DoD FAQ Bot', {
    x: 0.9, y: 2.4, w: 11.5, h: 1.4,
    fontFace: FONT_H, fontSize: 66, bold: true, color: WHITE
  });
  s.addText('Reference Architecture  //  Azure Government (IL5)', {
    x: 0.9, y: 3.85, w: 11.5, h: 0.6,
    fontFace: FONT_B, fontSize: 22, color: 'CADCFC'
  });
  s.addText('Teams + Web  //  Azure OpenAI GPT-4o  //  AI Search  //  SharePoint RAG', {
    x: 0.9, y: 4.55, w: 11.5, h: 0.5,
    fontFace: FONT_B, fontSize: 16, italic: true, color: ACCENT
  });
  s.addText([
    { text: 'Ralee Cook  //  Sr Cloud Solution Architect  //  Microsoft Federal CAIP', options: { fontSize: 14, color: 'CADCFC' } },
    { text: '\n27 July 2026  //  Draft v0.1', options: { fontSize: 12, color: MUTED } }
  ], {
    x: 0.9, y: 6.2, w: 11.5, h: 0.9, fontFace: FONT_B
  });
}

// ============ SLIDE 2 - The ask ============
{
  const s = p.addSlide();
  s.background = { color: CREAM };
  s.addText('The ask', {
    x: 0.5, y: 0.4, w: 12.3, h: 0.9, fontFace: FONT_H, fontSize: 40, bold: true, color: MIDNIGHT
  });

  const rows = [
    { icon: 'Q', label: 'Question', text: 'Stand up an FAQ bot for a DoD customer, accessible from Teams and a web chat control.' },
    { icon: 'D', label: 'Data', text: 'RAG grounded in a customer SharePoint document library.' },
    { icon: 'E', label: 'Escalation', text: 'Users can flag wrong or unanswered questions; triage team gets notified in Teams + SharePoint list.' },
    { icon: 'C', label: 'Cloud', text: 'Azure Government (DoD region), Azure VM for the orchestrator.' },
    { icon: 'B', label: 'Budget', text: '~$2,500 / month at fairly high usage (~50k queries/month).' }
  ];

  rows.forEach((r, i) => {
    const y = 1.55 + i * 1.05;
    s.addShape('ellipse', { x: 0.7, y, w: 0.8, h: 0.8, fill: { color: DEEP }, line: { color: DEEP } });
    s.addText(r.icon, {
      x: 0.7, y, w: 0.8, h: 0.8, fontFace: FONT_H, fontSize: 28, bold: true, color: WHITE, align: 'center', valign: 'middle'
    });
    s.addText(r.label, {
      x: 1.8, y: y + 0.02, w: 3, h: 0.45, fontFace: FONT_H, fontSize: 18, bold: true, color: MIDNIGHT
    });
    s.addText(r.text, {
      x: 1.8, y: y + 0.42, w: 10.9, h: 0.55, fontFace: FONT_B, fontSize: 13, color: '212121'
    });
  });
  footer(s, 2, TOTAL);
}

// ============ SLIDE 3 - Solution at a glance ============
{
  const s = p.addSlide();
  s.background = { color: WHITE };
  s.addText('Solution at a glance', {
    x: 0.5, y: 0.4, w: 12.3, h: 0.9, fontFace: FONT_H, fontSize: 40, bold: true, color: MIDNIGHT
  });

  // 2x2 card grid
  const cards = [
    { title: 'Channel', body: 'Azure Bot Service\nTeams channel + Direct Line for web embed', color: DEEP },
    { title: 'Model', body: 'Azure OpenAI (Gov)\ngpt-4o + text-embedding-3-large', color: TEAL },
    { title: 'Retrieval', body: 'Azure AI Search S1\nHybrid vector + BM25, semantic ranker on', color: MIDNIGHT },
    { title: 'Source', body: 'SharePoint Online (DoD)\nBuilt-in indexer, incremental crawl', color: ACCENT }
  ];

  const cardW = 5.9;
  const cardH = 2.5;
  cards.forEach((c, i) => {
    const col = i % 2;
    const row = Math.floor(i / 2);
    const x = 0.5 + col * (cardW + 0.4);
    const y = 1.6 + row * (cardH + 0.3);
    s.addShape('rect', { x, y, w: cardW, h: cardH, fill: { color: CREAM }, line: { color: 'D5D9E0', width: 1 } });
    s.addShape('rect', { x, y, w: 0.15, h: cardH, fill: { color: c.color }, line: { color: c.color } });
    s.addText(c.title, {
      x: x + 0.35, y: y + 0.2, w: cardW - 0.5, h: 0.5,
      fontFace: FONT_H, fontSize: 22, bold: true, color: c.color
    });
    s.addText(c.body, {
      x: x + 0.35, y: y + 0.8, w: cardW - 0.5, h: cardH - 0.9,
      fontFace: FONT_B, fontSize: 14, color: '212121'
    });
  });
  footer(s, 3, TOTAL);
}

// ============ SLIDE 4 - Architecture ============
{
  const s = p.addSlide();
  s.background = { color: WHITE };
  s.addText('Architecture', {
    x: 0.5, y: 0.4, w: 12.3, h: 0.9, fontFace: FONT_H, fontSize: 40, bold: true, color: MIDNIGHT
  });
  s.addText('All services deployed inside Azure Government DoD boundary via private endpoints.', {
    x: 0.5, y: 1.2, w: 12.3, h: 0.4, fontFace: FONT_B, fontSize: 13, italic: true, color: MUTED
  });

  // Boxes representing the data flow: Users -> Bot -> VM -> {AOAI, AI Search} <- SharePoint
  const box = (x, y, w, h, label, sub, fill, textColor) => {
    s.addShape('roundRect', { x, y, w, h, fill: { color: fill }, line: { color: fill }, rectRadius: 0.08 });
    s.addText(label, {
      x: x + 0.1, y: y + 0.1, w: w - 0.2, h: h * 0.5,
      fontFace: FONT_H, fontSize: 14, bold: true, color: textColor || WHITE, align: 'center', valign: 'middle'
    });
    if (sub) {
      s.addText(sub, {
        x: x + 0.1, y: y + h * 0.5, w: w - 0.2, h: h * 0.5,
        fontFace: FONT_B, fontSize: 10, color: textColor || 'CADCFC', align: 'center', valign: 'middle'
      });
    }
  };

  const arrow = (x1, y1, x2, y2) => {
    s.addShape('line', {
      x: x1, y: y1, w: x2 - x1, h: y2 - y1,
      line: { color: MUTED, width: 2, endArrowType: 'triangle' }
    });
  };

  // Users column
  box(0.5, 2.1, 2.0, 0.9, 'Teams users', 'DoD tenant', DEEP);
  box(0.5, 3.3, 2.0, 0.9, 'Web users', 'Embed control', DEEP);

  // Bot service
  box(3.0, 2.7, 2.2, 0.9, 'Azure Bot Service', 'Teams + Direct Line', TEAL);

  // Orchestrator VM
  box(5.7, 2.7, 2.5, 0.9, 'Orchestrator VM', 'D4s_v5  //  Docker', MIDNIGHT);

  // AOAI
  box(8.7, 1.6, 2.5, 0.9, 'Azure OpenAI', 'gpt-4o + embeddings', ACCENT, MIDNIGHT);
  // AI Search
  box(8.7, 2.9, 2.5, 0.9, 'Azure AI Search', 'Vector + BM25', ACCENT, MIDNIGHT);
  // SharePoint
  box(8.7, 4.2, 2.5, 0.9, 'SharePoint Online', 'DoD document library', DEEP);

  // Key Vault + Monitoring (support)
  box(5.7, 4.4, 2.5, 0.7, 'Key Vault + Log Analytics + App Insights', '', MUTED);

  // Arrows
  arrow(2.5, 2.55, 3.0, 3.0);   // Teams -> Bot
  arrow(2.5, 3.75, 3.0, 3.3);   // Web  -> Bot
  arrow(5.2, 3.15, 5.7, 3.15);  // Bot  -> VM
  arrow(8.2, 3.0, 8.7, 2.05);   // VM   -> AOAI
  arrow(8.2, 3.2, 8.7, 3.35);   // VM   -> Search
  arrow(11.2, 4.65, 11.2, 3.8); // SP   -> Search (indexer)
  arrow(8.2, 3.6, 8.2, 4.4);    // VM   -> KV/Logs (down)

  // Legend
  s.addText('Solid arrows: request flow  //  Ingest arrow: AI Search SharePoint indexer', {
    x: 0.5, y: 5.6, w: 12.3, h: 0.35, fontFace: FONT_B, fontSize: 11, italic: true, color: MUTED
  });

  // Callout
  s.addShape('rect', { x: 0.5, y: 6.1, w: 12.3, h: 0.9, fill: { color: CREAM }, line: { color: 'D5D9E0' } });
  s.addText('Private endpoints on AOAI, AI Search, Key Vault, Storage, and Monitor. AAD-only auth on AOAI (local keys disabled). Managed identity on the VM.', {
    x: 0.7, y: 6.1, w: 12.0, h: 0.9, fontFace: FONT_B, fontSize: 13, color: MIDNIGHT, valign: 'middle'
  });
  footer(s, 4, TOTAL);
}

// ============ SLIDE 5 - Escalation ============
{
  const s = p.addSlide();
  s.background = { color: WHITE };
  s.addText('Escalation flow', {
    x: 0.5, y: 0.4, w: 12.3, h: 0.9, fontFace: FONT_H, fontSize: 40, bold: true, color: MIDNIGHT
  });
  s.addText('Every response has an Escalate action. Wrong or unanswered questions become tickets the triage team owns.', {
    x: 0.5, y: 1.2, w: 12.3, h: 0.4, fontFace: FONT_B, fontSize: 13, italic: true, color: MUTED
  });

  // Horizontal flow: 5 numbered stages
  const stages = [
    { title: 'User escalates', body: 'Clicks Escalate on the bot response. Adaptive card asks reason + optional comment.' },
    { title: 'Bot captures context', body: 'Q, answer, retrieved chunks, model version, user UPN, channel, timestamp.' },
    { title: 'Row -> SharePoint list', body: '"FAQ Escalations" list. Graph Sites.Selected scoped to this one list.' },
    { title: 'Ping triage in Teams', body: '@mention in "FAQ Bot - Triage" channel with deep link to the item.' },
    { title: 'Resolve + reply back', body: 'Owner marks Resolved. Proactive Bot Framework message goes back to the user.' }
  ];
  const stageW = 2.4;
  stages.forEach((st, i) => {
    const x = 0.5 + i * (stageW + 0.1);
    // Number pill
    s.addShape('roundRect', { x, y: 1.8, w: stageW, h: 3.9, fill: { color: CREAM }, line: { color: 'D5D9E0' }, rectRadius: 0.1 });
    s.addShape('ellipse', { x: x + stageW/2 - 0.35, y: 1.95, w: 0.7, h: 0.7, fill: { color: ACCENT }, line: { color: ACCENT } });
    s.addText(String(i + 1), { x: x + stageW/2 - 0.35, y: 1.95, w: 0.7, h: 0.7,
      fontFace: FONT_H, fontSize: 24, bold: true, color: MIDNIGHT, align: 'center', valign: 'middle' });
    s.addText(st.title, { x: x + 0.1, y: 2.8, w: stageW - 0.2, h: 0.55,
      fontFace: FONT_H, fontSize: 15, bold: true, color: MIDNIGHT, align: 'center' });
    s.addText(st.body, { x: x + 0.2, y: 3.4, w: stageW - 0.4, h: 2.2,
      fontFace: FONT_B, fontSize: 11, color: '212121', align: 'center' });
    // Arrow between stages
    if (i < stages.length - 1) {
      const ax = x + stageW + 0.02;
      s.addShape('rightTriangle', {
        x: ax, y: 3.5, w: 0.08, h: 0.4,
        fill: { color: MUTED }, line: { color: MUTED }, rotate: 90
      });
    }
  });

  // Callout row
  s.addShape('rect', { x: 0.5, y: 5.95, w: 12.3, h: 1.05, fill: { color: MIDNIGHT }, line: { color: MIDNIGHT } });
  s.addText([
    { text: 'Why this design:  ', options: { bold: true, color: ACCENT, fontFace: FONT_H, fontSize: 14 } },
    { text: 'no new Azure resources  //  in-boundary  //  triage team uses tools they already know (SharePoint + Teams)  //  escalations feed the content-quality loop and drive doc edits, not bot rewrites.', options: { color: 'CADCFC', fontFace: FONT_B, fontSize: 13 } }
  ], { x: 0.75, y: 5.95, w: 11.85, h: 1.05, valign: 'middle' });

  footer(s, 5, TOTAL);
}

// ============ SLIDE 6 - Caching ============
{
  const s = p.addSlide();
  s.background = { color: WHITE };
  s.addText('Response caching  //  two tiers', {
    x: 0.5, y: 0.4, w: 12.3, h: 0.9, fontFace: FONT_H, fontSize: 40, bold: true, color: MIDNIGHT
  });
  s.addText('In from the pilot. Cuts LLM cost on repeats and drops cached-answer latency to tens of milliseconds.', {
    x: 0.5, y: 1.2, w: 12.3, h: 0.4, fontFace: FONT_B, fontSize: 13, italic: true, color: MUTED
  });

  // Two big cards
  const cardW = 6.1;
  const cards = [
    {
      title: 'L1  //  Exact match',
      subtitle: 'In-process LRU on the orchestrator VM',
      color: DEEP,
      rows: [
        ['Hit criteria', 'Normalized-string equality'],
        ['TTL', '1 hour'],
        ['Latency', '~1 ms'],
        ['Infra cost', '$0  //  ~50 MB RAM'],
        ['Best for', 'Identical repeats']
      ]
    },
    {
      title: 'L2  //  Semantic',
      subtitle: 'Second AI Search index (faq-cache)',
      color: TEAL,
      rows: [
        ['Hit criteria', 'Cosine similarity >= 0.95'],
        ['TTL', '24 hours'],
        ['Latency', '~30-60 ms'],
        ['Infra cost', '$0  //  rides on S1 already deployed'],
        ['Best for', 'Paraphrases']
      ]
    }
  ];

  cards.forEach((c, i) => {
    const x = 0.5 + i * (cardW + 0.3);
    s.addShape('roundRect', { x, y: 1.75, w: cardW, h: 3.55, fill: { color: CREAM }, line: { color: 'D5D9E0' }, rectRadius: 0.12 });
    s.addShape('rect', { x, y: 1.75, w: 0.18, h: 3.55, fill: { color: c.color }, line: { color: c.color } });
    s.addText(c.title, {
      x: x + 0.35, y: 1.85, w: cardW - 0.5, h: 0.5,
      fontFace: FONT_H, fontSize: 22, bold: true, color: c.color
    });
    s.addText(c.subtitle, {
      x: x + 0.35, y: 2.35, w: cardW - 0.5, h: 0.4,
      fontFace: FONT_B, fontSize: 13, italic: true, color: MUTED
    });
    // Detail rows
    c.rows.forEach((r, j) => {
      const y = 2.85 + j * 0.42;
      s.addText(r[0], {
        x: x + 0.4, y, w: 1.7, h: 0.35, fontFace: FONT_B, fontSize: 12, bold: true, color: MIDNIGHT
      });
      s.addText(r[1], {
        x: x + 2.15, y, w: cardW - 2.35, h: 0.35, fontFace: FONT_B, fontSize: 12, color: '212121'
      });
    });
  });

  // Impact strip along the bottom
  s.addShape('rect', { x: 0.5, y: 5.55, w: 12.3, h: 1.45, fill: { color: MIDNIGHT }, line: { color: MIDNIGHT } });
  s.addText('At 50k queries/mo  //  gpt-4o savings by hit rate', {
    x: 0.7, y: 5.6, w: 12.0, h: 0.4, fontFace: FONT_H, fontSize: 14, bold: true, color: ACCENT
  });
  const impact = [
    { rate: '0%', spend: '$900', save: 'baseline' },
    { rate: '20%', spend: '$720', save: '~$180' },
    { rate: '40%', spend: '$540', save: '~$360' },
    { rate: '60%', spend: '$360', save: '~$540' }
  ];
  impact.forEach((tile, i) => {
    const x = 0.85 + i * 3.0;
    s.addText(tile.rate, {
      x, y: 6.0, w: 2.8, h: 0.35, fontFace: FONT_H, fontSize: 14, color: 'CADCFC'
    });
    s.addText(tile.spend, {
      x, y: 6.3, w: 2.8, h: 0.4, fontFace: FONT_H, fontSize: 20, bold: true, color: WHITE
    });
    s.addText(tile.save, {
      x, y: 6.68, w: 2.8, h: 0.3, fontFace: FONT_B, fontSize: 11, italic: true, color: ACCENT
    });
  });

  footer(s, 6, TOTAL);
}

// ============ SLIDE 7 - Cost ============
{
  const s = p.addSlide();
  s.background = { color: WHITE };
  s.addText('Cost model  //  ~$2,500 / month', {
    x: 0.5, y: 0.4, w: 12.3, h: 0.9, fontFace: FONT_H, fontSize: 40, bold: true, color: MIDNIGHT
  });
  s.addText('~50,000 queries / month  //  Azure Government retail  //  Verify against EA before commit.', {
    x: 0.5, y: 1.2, w: 12.3, h: 0.4, fontFace: FONT_B, fontSize: 13, italic: true, color: MUTED
  });

  // Big stat callout on left
  s.addShape('roundRect', { x: 0.5, y: 1.8, w: 4.2, h: 4.9, fill: { color: MIDNIGHT }, line: { color: MIDNIGHT }, rectRadius: 0.15 });
  s.addText('~$2,500', {
    x: 0.5, y: 2.3, w: 4.2, h: 1.2, fontFace: FONT_H, fontSize: 72, bold: true, color: ACCENT, align: 'center'
  });
  s.addText('per month', {
    x: 0.5, y: 3.6, w: 4.2, h: 0.5, fontFace: FONT_B, fontSize: 18, color: 'CADCFC', align: 'center'
  });
  s.addText('at ~50k queries', {
    x: 0.5, y: 4.05, w: 4.2, h: 0.5, fontFace: FONT_B, fontSize: 14, italic: true, color: 'CADCFC', align: 'center'
  });
  s.addText([
    { text: 'Subtotal', options: { color: 'CADCFC', fontSize: 13 } },
    { text: '   ~$1,830', options: { color: WHITE, fontSize: 13, bold: true } },
    { text: '\nBuffer', options: { color: 'CADCFC', fontSize: 13 } },
    { text: '     ~$670', options: { color: WHITE, fontSize: 13, bold: true } }
  ], {
    x: 0.5, y: 5.4, w: 4.2, h: 1.1, fontFace: FONT_B, align: 'center'
  });

  // Table of items on right
  const rows = [
    ['AOAI  //  gpt-4o chat', '$900'],
    ['AOAI  //  embeddings', '$30'],
    ['AI Search Standard S1', '$370'],
    ['VM D4s_v5 (1-yr RI)', '$220'],
    ['Azure Bot Service S1', '$50'],
    ['Storage + bandwidth', '$60'],
    ['App Insights + LAW', '$120'],
    ['Key Vault + net + DNS', '$80']
  ];
  const tableData = [
    [
      { text: 'Item', options: { bold: true, color: WHITE, fill: { color: MIDNIGHT }, fontFace: FONT_B, fontSize: 13 } },
      { text: 'USD / mo', options: { bold: true, color: WHITE, fill: { color: MIDNIGHT }, fontFace: FONT_B, fontSize: 13, align: 'right' } }
    ],
    ...rows.map(r => [
      { text: r[0], options: { color: '212121', fontFace: FONT_B, fontSize: 13 } },
      { text: r[1], options: { color: '212121', fontFace: FONT_B, fontSize: 13, align: 'right', bold: true } }
    ])
  ];
  s.addTable(tableData, {
    x: 5.0, y: 1.8, w: 7.8, colW: [5.4, 2.4],
    border: { pt: 0.5, color: 'D5D9E0' }, rowH: 0.4
  });
  footer(s, 7, TOTAL);
}

// ============ SLIDE 8 - Deployment plan ============
{
  const s = p.addSlide();
  s.background = { color: WHITE };
  s.addText('Deployment plan  //  ~6 weeks', {
    x: 0.5, y: 0.4, w: 12.3, h: 0.9, fontFace: FONT_H, fontSize: 40, bold: true, color: MIDNIGHT
  });

  const steps = [
    { n: '1', w: 'Wk 1', title: 'Foundations', body: 'Confirm IL5 + tenant boundary. Submit AOAI quota. Register Entra Gov bot app.' },
    { n: '2', w: 'Wk 2', title: 'Infra land', body: 'Bicep deployment: vNet, PE, Key Vault, AOAI, AI Search, VM, Bot Service.' },
    { n: '3', w: 'Wk 3', title: 'Ingest + cache', body: 'SharePoint indexer + faq-cache index. Escalation list + triage channel.' },
    { n: '4', w: 'Wk 4', title: 'Orchestrator', body: 'Deploy orchestrator container with L1 + L2 caching. Wire Teams + Direct Line.' },
    { n: '5', w: 'Wk 5', title: 'Pilot', body: 'Pilot user group. Measure cache hit rate + escalation rate. Prompt tuning.' },
    { n: '6', w: 'Wk 6', title: 'Launch', body: 'Broad rollout. Budget alert at 90%. Observability dashboards published.' }
  ];

  const stepW = 2.0;
  steps.forEach((step, i) => {
    const x = 0.5 + i * (stepW + 0.05);
    s.addShape('roundRect', { x, y: 1.7, w: stepW, h: 4.7, fill: { color: CREAM }, line: { color: 'D5D9E0' }, rectRadius: 0.1 });
    s.addShape('ellipse', { x: x + stepW/2 - 0.4, y: 1.9, w: 0.8, h: 0.8, fill: { color: DEEP }, line: { color: DEEP } });
    s.addText(step.n, { x: x + stepW/2 - 0.4, y: 1.9, w: 0.8, h: 0.8,
      fontFace: FONT_H, fontSize: 28, bold: true, color: WHITE, align: 'center', valign: 'middle' });
    s.addText(step.w, { x, y: 2.85, w: stepW, h: 0.35,
      fontFace: FONT_B, fontSize: 11, color: TEAL, align: 'center', bold: true });
    s.addText(step.title, { x: x + 0.1, y: 3.2, w: stepW - 0.2, h: 0.5,
      fontFace: FONT_H, fontSize: 16, bold: true, color: MIDNIGHT, align: 'center' });
    s.addText(step.body, { x: x + 0.15, y: 3.75, w: stepW - 0.3, h: 2.5,
      fontFace: FONT_B, fontSize: 11, color: '212121', align: 'center' });
  });
  footer(s, 8, TOTAL);
}

// ============ SLIDE 9 - Risks & open questions ============
{
  const s = p.addSlide();
  s.background = { color: WHITE };
  s.addText('Risks + open questions', {
    x: 0.5, y: 0.4, w: 12.3, h: 0.9, fontFace: FONT_H, fontSize: 40, bold: true, color: MIDNIGHT
  });

  // Two columns
  s.addText('Top risks', {
    x: 0.5, y: 1.4, w: 6.0, h: 0.5, fontFace: FONT_H, fontSize: 22, bold: true, color: DEEP
  });
  const risks = [
    'AOAI quota (gpt-4o) not yet granted in Azure Gov  //  block-deploy AI Search + VM in parallel.',
    'SharePoint tenant must be in the same compliance boundary (DoD or GCC-High).',
    'Bot Framework Teams channel binding for DoD requires the correct deployment env.',
    'Answer quality on long / structured docs — tune chunk size, run regression set.',
    'Cost overrun if usage exceeds 50k queries/mo — budget alert + gpt-4o-mini fallback.'
  ];
  s.addText(risks.map(r => ({ text: r, options: { bullet: { code: '25AA' }, breakLine: true } })), {
    x: 0.5, y: 1.95, w: 6.0, h: 4.5, fontFace: FONT_B, fontSize: 13, color: '212121', paraSpaceAfter: 6
  });

  s.addText('Confirm with customer', {
    x: 6.8, y: 1.4, w: 6.0, h: 0.5, fontFace: FONT_H, fontSize: 22, bold: true, color: TEAL
  });
  const qs = [
    'IL5 vs IL4 classification of the workload.',
    'SharePoint tenant boundary — DoD or GCC-High?',
    'Expected concurrent users and peak QPS.',
    'AOAI billing preference — PAYG or Provisioned Throughput Units.',
    'Web chat hosting — existing intranet portal, or new one?'
  ];
  s.addText(qs.map(q => ({ text: q, options: { bullet: { code: '25AA' }, breakLine: true } })), {
    x: 6.8, y: 1.95, w: 6.0, h: 4.5, fontFace: FONT_B, fontSize: 13, color: '212121', paraSpaceAfter: 6
  });
  footer(s, 9, TOTAL);
}

// ============ SLIDE 10 - Next steps ============
{
  const s = p.addSlide();
  s.background = { color: MIDNIGHT };
  s.addShape('rect', { x: 0, y: 0, w: 0.35, h: 7.5, fill: { color: ACCENT }, line: { color: ACCENT } });

  s.addText('Next steps', {
    x: 0.9, y: 0.6, w: 11.5, h: 1.0, fontFace: FONT_H, fontSize: 50, bold: true, color: WHITE
  });
  s.addText('Two blockers to unblock in parallel this week.', {
    x: 0.9, y: 1.55, w: 11.5, h: 0.5, fontFace: FONT_B, fontSize: 18, italic: true, color: 'CADCFC'
  });

  const actions = [
    { title: 'File the AOAI quota request', body: 'Submit gpt-4o + text-embedding-3-large in usgovvirginia. Draft in aoai-quota-request.md.' },
    { title: 'Confirm customer boundaries', body: 'IL level, SharePoint tenant compliance, concurrency. Send the open-questions list.' },
    { title: 'Land the Bicep skeleton in a dev sub', body: 'Deploy vNet + Key Vault + Search + VM to validate the topology while quota lands.' },
    { title: 'Loop in Steve St Jean and John Spinella', body: 'Principal CSAs on the CAIP Fed team; strongest peers for architecture review.' }
  ];
  actions.forEach((a, i) => {
    const y = 2.4 + i * 1.1;
    s.addShape('ellipse', { x: 0.9, y, w: 0.7, h: 0.7, fill: { color: ACCENT }, line: { color: ACCENT } });
    s.addText(String(i + 1), {
      x: 0.9, y, w: 0.7, h: 0.7, fontFace: FONT_H, fontSize: 24, bold: true, color: MIDNIGHT, align: 'center', valign: 'middle'
    });
    s.addText(a.title, {
      x: 1.85, y: y - 0.05, w: 11.0, h: 0.5, fontFace: FONT_H, fontSize: 20, bold: true, color: WHITE
    });
    s.addText(a.body, {
      x: 1.85, y: y + 0.4, w: 11.0, h: 0.5, fontFace: FONT_B, fontSize: 13, color: 'CADCFC'
    });
  });

  s.addText('Ralee Cook  //  raleecook@microsoft.com  //  Microsoft Federal CAIP', {
    x: 0.9, y: 6.9, w: 11.5, h: 0.4, fontFace: FONT_B, fontSize: 12, color: MUTED
  });
}

p.writeFile({ fileName: OUT }).then(f => console.log('Wrote', f));
