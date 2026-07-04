#!/usr/bin/env node
// Statischer Doku-Site-Generator fuer WorkTime.
//
// Liest `docs/manifest.json` + die Markdown-Artikel und erzeugt eine
// eigenstaendige, gebrandete HTML-Doku unter `docs-site/` (kein externes CDN,
// oeffenbar per file:// oder ueber jeden statischen Webserver / Firebase
// Hosting). Dieselbe Markdown-Quelle speist auch den In-App-Viewer.
//
// Aufruf:  node scripts/build-docs-site.mjs
// Ausgabe: docs-site/index.html, docs-site/<slug>.html, docs-site/assets/*

import { readFileSync, writeFileSync, mkdirSync, existsSync, rmSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const DOCS = join(ROOT, 'docs')
const OUT = join(ROOT, 'docs-site')

// -------------------------- Markdown -> HTML --------------------------
function escapeHtml(s) {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

const INLINE_RE = /(`[^`]+`)|(\[[^\]]+\]\([^)]+\))|(\*\*[^*]+\*\*)|(\*[^*\n]+\*)/g
const LINK_RE = /^\[([^\]]+)\]\(([^)]+)\)$/

function renderInline(text) {
  let out = ''
  let last = 0
  for (const m of text.matchAll(INLINE_RE)) {
    if (m.index > last) out += escapeHtml(text.slice(last, m.index))
    const t = m[0]
    if (t.startsWith('`')) {
      out += `<code>${escapeHtml(t.slice(1, -1))}</code>`
    } else if (t.startsWith('[')) {
      const link = t.match(LINK_RE)
      if (link) {
        const label = escapeHtml(link[1])
        let href = link[2].trim()
        if (href.startsWith('article:')) {
          out += `<a href="${escapeHtml(href.slice(8))}.html">${label}</a>`
        } else {
          out += `<a href="${escapeHtml(href)}" target="_blank" rel="noopener">${label}</a>`
        }
      } else {
        out += escapeHtml(t)
      }
    } else if (t.startsWith('**')) {
      out += `<strong>${escapeHtml(t.slice(2, -2))}</strong>`
    } else {
      out += `<em>${escapeHtml(t.slice(1, -1))}</em>`
    }
    last = m.index + t.length
  }
  if (last < text.length) out += escapeHtml(text.slice(last))
  return out
}

const HEADING_RE = /^(#{1,3})\s+(.*)$/
const UL_RE = /^\s*[-*]\s+(.*)$/
const OL_RE = /^\s*\d+\.\s+(.*)$/
const TABLE_SEP_RE = /^\s*\|?[\s:|-]+\|?\s*$/
const CALLOUT_RE = /^\[!(TIP|NOTE|WARNING|IMPORTANT|CAUTION)\]\s*(.*)$/

function cells(line) {
  let t = line.trim()
  if (t.startsWith('|')) t = t.slice(1)
  if (t.endsWith('|')) t = t.slice(0, -1)
  return t.split('|').map((c) => c.trim())
}

function renderMarkdown(src) {
  const lines = src.replace(/\r\n/g, '\n').split('\n')
  const html = []
  let i = 0
  while (i < lines.length) {
    const line = lines[i]
    const trimmed = line.trim()
    if (trimmed === '') { i++; continue }

    if (trimmed.startsWith('```')) {
      const buf = []
      i++
      while (i < lines.length && !lines[i].trim().startsWith('```')) { buf.push(lines[i]); i++ }
      i++
      html.push(`<pre><code>${escapeHtml(buf.join('\n'))}</code></pre>`)
      continue
    }
    if (trimmed === '---' || trimmed === '***' || trimmed === '___') {
      html.push('<hr>'); i++; continue
    }
    const h = line.match(HEADING_RE)
    if (h) {
      const level = h[1].length
      const id = slugifyHeading(h[2])
      html.push(`<h${level} id="${id}">${renderInline(h[2].trim())}</h${level}>`)
      i++; continue
    }
    if (trimmed.startsWith('>')) {
      const raw = []
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        raw.push(lines[i].trim().replace(/^>\s?/, '')); i++
      }
      let kind = 'QUOTE'
      const m = raw.length ? raw[0].trim().match(CALLOUT_RE) : null
      if (m) {
        kind = m[1]
        raw[0] = m[2].trim()
        if (raw[0] === '') raw.shift()
      }
      const paras = joinSoft(raw).map((p) => `<p>${renderInline(p)}</p>`).join('')
      html.push(`<blockquote class="callout callout-${kind.toLowerCase()}"><span class="callout-badge">${calloutLabel(kind)}</span>${paras}</blockquote>`)
      continue
    }
    if (trimmed.includes('|') && i + 1 < lines.length && TABLE_SEP_RE.test(lines[i + 1]) && lines[i + 1].includes('-')) {
      const header = cells(line)
      i += 2
      const rows = []
      while (i < lines.length && lines[i].trim().includes('|') && lines[i].trim() !== '') { rows.push(cells(lines[i])); i++ }
      const thead = `<thead><tr>${header.map((c) => `<th>${renderInline(c)}</th>`).join('')}</tr></thead>`
      const tbody = `<tbody>${rows.map((r) => `<tr>${header.map((_, c) => `<td>${renderInline(r[c] || '')}</td>`).join('')}</tr>`).join('')}</tbody>`
      html.push(`<div class="table-wrap"><table>${thead}${tbody}</table></div>`)
      continue
    }
    if (UL_RE.test(line)) {
      const items = []
      while (i < lines.length && UL_RE.test(lines[i])) { items.push(lines[i].match(UL_RE)[1].trim()); i++ }
      html.push(`<ul>${items.map((it) => `<li>${renderInline(it)}</li>`).join('')}</ul>`)
      continue
    }
    if (OL_RE.test(line)) {
      const items = []
      while (i < lines.length && OL_RE.test(lines[i])) { items.push(lines[i].match(OL_RE)[1].trim()); i++ }
      html.push(`<ol>${items.map((it) => `<li>${renderInline(it)}</li>`).join('')}</ol>`)
      continue
    }
    const para = []
    while (i < lines.length) {
      const l = lines[i]; const t = l.trim()
      if (t === '' || t.startsWith('```') || t.startsWith('>') || t === '---' || HEADING_RE.test(l) || UL_RE.test(l) || OL_RE.test(l)) break
      para.push(t); i++
    }
    if (para.length) html.push(`<p>${renderInline(para.join(' '))}</p>`)
  }
  return html.join('\n')
}

function joinSoft(raw) {
  const out = []; let cur = []
  for (const l of raw) {
    if (l.trim() === '') { if (cur.length) { out.push(cur.join(' ')); cur = [] } }
    else cur.push(l.trim())
  }
  if (cur.length) out.push(cur.join(' '))
  return out
}

function calloutLabel(kind) {
  return { TIP: 'Tipp', NOTE: 'Hinweis', WARNING: 'Achtung', IMPORTANT: 'Wichtig', CAUTION: 'Vorsicht', QUOTE: 'Zitat' }[kind] || 'Hinweis'
}

function slugifyHeading(s) {
  return s.toLowerCase().replace(/[^a-z0-9äöüß]+/g, '-').replace(/^-|-$/g, '')
}

// -------------------------- Seiten-Templates --------------------------
function pageShell({ title, nav, content, activeSlug }) {
  return `<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)} · WorkTime Wissen</title>
<link rel="stylesheet" href="assets/style.css">
</head>
<body data-active="${escapeHtml(activeSlug || '')}">
<header class="topbar">
  <a class="brand" href="index.html">WorkTime <span>Wissen</span></a>
  <input id="search" type="search" placeholder="Wissen durchsuchen …" autocomplete="off">
  <button id="menu-toggle" aria-label="Menü">☰</button>
</header>
<div class="layout">
  <aside class="sidebar" id="sidebar">${nav}</aside>
  <main class="content">
    <div id="search-results" hidden></div>
    <article class="doc">${content}</article>
  </main>
</div>
<script src="assets/search-index.js"></script>
<script src="assets/app.js"></script>
</body>
</html>`
}

function buildNav(manifest, activeSlug) {
  const groups = { mitarbeiter: [], entwickler: [] }
  for (const s of manifest.sections) {
    const links = s.articles
      .map((a) => `<a class="nav-article${a.slug === activeSlug ? ' active' : ''}" href="${a.slug}.html">${escapeHtml(a.title)}</a>`)
      .join('')
    groups[s.audience === 'entwickler' ? 'entwickler' : 'mitarbeiter'].push(
      `<div class="nav-section"><div class="nav-section-title">${escapeHtml(s.title)}</div>${links}</div>`
    )
  }
  let out = `<div class="nav-group-title">Anleitungen</div>${groups.mitarbeiter.join('')}`
  if (groups.entwickler.length) {
    out += `<div class="nav-group-title dev">Technik (für Entwickler)</div>${groups.entwickler.join('')}`
  }
  return out
}

function buildIndexContent(manifest) {
  const cards = manifest.sections
    .map((s) => {
      const items = s.articles.map((a) => `<li><a href="${a.slug}.html">${escapeHtml(a.title)}</a></li>`).join('')
      return `<section class="index-card ${s.audience}">
        <h2>${escapeHtml(s.title)}</h2>
        <ul>${items}</ul>
      </section>`
    })
    .join('')
  return `<h1>WorkTime – Wissen & Handbuch</h1>
<p class="lead">Vollständige Doku für Mitarbeiter und Entwickler. Wählen Sie ein Kapitel oder nutzen Sie die Suche oben.</p>
<div class="index-grid">${cards}</div>`
}

const STYLE = `:root{
  --navy:#12324a; --ink:#1c2b36; --paper:#faf7f0; --white:#ffffff;
  --blue:#2f6db3; --green:#2f8f5b; --yellow:#e6b422; --line:#e4ded3;
  --muted:#5c6b76; --bg:#f6f2ea; --code:#f0ece3;
}
*{box-sizing:border-box}
body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Noto Sans",sans-serif;color:var(--ink);background:var(--bg);line-height:1.6}
a{color:var(--blue);text-decoration:none}
a:hover{text-decoration:underline}
.topbar{position:sticky;top:0;z-index:10;display:flex;align-items:center;gap:16px;padding:12px 20px;background:var(--navy);color:var(--white)}
.brand{color:var(--white);font-weight:800;font-size:18px}
.brand span{color:var(--yellow);font-weight:600}
#search{flex:1;max-width:520px;padding:9px 14px;border:none;border-radius:999px;font-size:15px;background:rgba(255,255,255,.15);color:var(--white)}
#search::placeholder{color:rgba(255,255,255,.7)}
#menu-toggle{display:none;background:none;border:none;color:#fff;font-size:22px;cursor:pointer}
.layout{display:flex;max-width:1180px;margin:0 auto;align-items:flex-start}
.sidebar{width:290px;flex:none;padding:24px 12px 60px;position:sticky;top:57px;max-height:calc(100vh - 57px);overflow-y:auto}
.nav-group-title{font-size:12px;text-transform:uppercase;letter-spacing:.08em;color:var(--blue);font-weight:800;margin:18px 12px 8px}
.nav-group-title.dev{color:var(--green)}
.nav-section{margin-bottom:6px}
.nav-section-title{font-weight:700;font-size:13px;color:var(--muted);padding:8px 12px 2px}
.nav-article{display:block;padding:6px 12px;border-radius:8px;font-size:14px;color:var(--ink)}
.nav-article:hover{background:var(--code);text-decoration:none}
.nav-article.active{background:var(--blue);color:#fff;font-weight:600}
.content{flex:1;min-width:0;padding:28px 32px 80px;background:var(--white);border-left:1px solid var(--line);min-height:calc(100vh - 57px)}
.doc{max-width:760px}
.doc h1{font-size:30px;line-height:1.25;margin:0 0 8px}
.doc h2{font-size:22px;margin:34px 0 10px;padding-bottom:6px;border-bottom:1px solid var(--line)}
.doc h3{font-size:18px;margin:24px 0 8px}
.doc p{margin:12px 0}
.doc ul,.doc ol{margin:12px 0;padding-left:24px}
.doc li{margin:5px 0}
.doc code{background:var(--code);padding:1px 6px;border-radius:5px;font-size:.92em;font-family:"SF Mono",Menlo,Consolas,monospace}
.doc pre{background:#0f2233;color:#e7edf2;padding:16px;border-radius:12px;overflow-x:auto}
.doc pre code{background:none;padding:0;color:inherit}
.lead{font-size:18px;color:var(--muted)}
.callout{margin:16px 0;padding:12px 16px;border-radius:12px;border-left:4px solid var(--muted);background:var(--code)}
.callout .callout-badge{display:inline-block;font-size:12px;font-weight:800;text-transform:uppercase;letter-spacing:.05em;margin-bottom:4px}
.callout p{margin:4px 0}
.callout-tip{background:#e6f4ec;border-color:var(--green)} .callout-tip .callout-badge{color:var(--green)}
.callout-warning,.callout-caution{background:#fdf3dd;border-color:var(--yellow)} .callout-warning .callout-badge,.callout-caution .callout-badge{color:#a9791a}
.callout-note,.callout-important{background:#e7f0fa;border-color:var(--blue)} .callout-note .callout-badge,.callout-important .callout-badge{color:var(--blue)}
.table-wrap{overflow-x:auto;margin:16px 0}
table{border-collapse:collapse;width:100%;font-size:14px}
th,td{border:1px solid var(--line);padding:8px 12px;text-align:left}
th{background:var(--code);font-weight:800}
.index-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:16px;margin-top:24px}
.index-card{border:1px solid var(--line);border-radius:14px;padding:16px 18px;background:var(--white)}
.index-card h2{font-size:16px;margin:0 0 8px;border:none}
.index-card.entwickler{background:#f4f8f5}
.index-card ul{list-style:none;padding:0;margin:0}
.index-card li{margin:4px 0}
#search-results{margin-bottom:20px}
.search-hit{display:block;padding:10px 14px;border:1px solid var(--line);border-radius:10px;margin-bottom:8px;background:var(--white)}
.search-hit b{display:block;color:var(--ink)}
.search-hit small{color:var(--muted)}
@media(max-width:860px){
  .sidebar{position:fixed;left:0;top:57px;bottom:0;background:var(--white);border-right:1px solid var(--line);z-index:9;transform:translateX(-100%);transition:transform .2s}
  body.nav-open .sidebar{transform:none}
  #menu-toggle{display:block}
  .content{border-left:none;padding:20px}
}`

const APP_JS = `(function(){
  var toggle=document.getElementById('menu-toggle');
  if(toggle){toggle.addEventListener('click',function(){document.body.classList.toggle('nav-open')})}
  document.querySelectorAll('.sidebar a').forEach(function(a){a.addEventListener('click',function(){document.body.classList.remove('nav-open')})});
  var input=document.getElementById('search');
  var results=document.getElementById('search-results');
  var article=document.querySelector('.doc');
  if(!input||!window.SEARCH_INDEX)return;
  function score(item,terms){var s=0;var t=item.title.toLowerCase();var k=(item.keywords||[]).join(' ').toLowerCase();var su=(item.summary||'').toLowerCase();terms.forEach(function(term){if(t.indexOf(term)>=0)s+=10;if(t.indexOf(term)===0)s+=5;if(k.indexOf(term)>=0)s+=6;if(su.indexOf(term)>=0)s+=3});return s}
  input.addEventListener('input',function(){
    var q=input.value.trim().toLowerCase();
    if(!q){results.hidden=true;if(article)article.hidden=false;return}
    var terms=q.split(/\\s+/).filter(Boolean);
    var hits=window.SEARCH_INDEX.map(function(it){return{it:it,s:score(it,terms)}}).filter(function(x){return x.s>0}).sort(function(a,b){return b.s-a.s});
    if(article)article.hidden=true;results.hidden=false;
    if(!hits.length){results.innerHTML='<p>Keine Treffer.</p>';return}
    results.innerHTML=hits.slice(0,25).map(function(x){return '<a class="search-hit" href="'+x.it.slug+'.html"><b>'+x.it.title+'</b><small>'+(x.it.section||'')+' · '+(x.it.summary||'')+'</small></a>'}).join('');
  });
})();`

// -------------------------- Build --------------------------
function build() {
  const manifest = JSON.parse(readFileSync(join(DOCS, 'manifest.json'), 'utf8'))
  if (existsSync(OUT)) rmSync(OUT, { recursive: true, force: true })
  mkdirSync(join(OUT, 'assets'), { recursive: true })

  const searchIndex = []
  let written = 0
  let missing = 0

  for (const s of manifest.sections) {
    for (const a of s.articles) {
      searchIndex.push({ slug: a.slug, title: a.title, section: s.title, summary: a.summary || '', keywords: a.keywords || [] })
      const mdPath = join(DOCS, a.file)
      let content
      if (existsSync(mdPath)) {
        content = renderMarkdown(readFileSync(mdPath, 'utf8'))
        written++
      } else {
        content = `<h1>${escapeHtml(a.title)}</h1><p class="lead">Dieser Artikel wird gerade erstellt.</p><p>${escapeHtml(a.summary || '')}</p>`
        missing++
      }
      const nav = buildNav(manifest, a.slug)
      writeFileSync(join(OUT, `${a.slug}.html`), pageShell({ title: a.title, nav, content, activeSlug: a.slug }))
    }
  }

  writeFileSync(join(OUT, 'index.html'), pageShell({ title: 'Übersicht', nav: buildNav(manifest, null), content: buildIndexContent(manifest), activeSlug: null }))
  writeFileSync(join(OUT, 'assets', 'style.css'), STYLE)
  writeFileSync(join(OUT, 'assets', 'app.js'), APP_JS)
  writeFileSync(join(OUT, 'assets', 'search-index.js'), `window.SEARCH_INDEX=${JSON.stringify(searchIndex)};`)

  console.log(`docs-site erzeugt: ${written} Artikel gerendert, ${missing} noch offen (Platzhalter). Ausgabe: ${OUT}`)
}

build()
