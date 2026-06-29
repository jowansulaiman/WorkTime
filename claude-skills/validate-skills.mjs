#!/usr/bin/env node
// Simuliert die Skill-Discovery von Claude Code: liest jede
// .claude/skills/<slug>/SKILL.md VON DER PLATTE (unabhängig vom Generator),
// parst das YAML-Frontmatter und prüft, dass Claude Code den Skill laden würde.
//   node claude-skills/validate-skills.mjs   # exit 1 bei Problemen
//
// Prüft pro Skill: Frontmatter vorhanden, name == Verzeichnis & valider Slug,
// description nicht leer & <=1024, Pointer-Quelle existiert.

import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = dirname(dirname(fileURLToPath(import.meta.url)));
const SKILLS_DIR = join(REPO, '.claude', 'skills');

function parseFrontmatter(text) {
  if (!text.startsWith('---\n')) return null;
  const end = text.indexOf('\n---', 4);
  if (end < 0) return null;
  const block = text.slice(4, end);
  const fm = {};
  for (const line of block.split('\n')) {
    const m = line.match(/^([a-zA-Z_]+):\s*(.*)$/);
    if (!m) continue;
    let v = m[2].trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      v = v.slice(1, -1);
    }
    fm[m[1]] = v;
  }
  return fm;
}

const problems = [];
const ok = [];

if (!existsSync(SKILLS_DIR)) {
  console.error(`Kein Skills-Verzeichnis: ${SKILLS_DIR}`);
  process.exit(1);
}

const dirs = readdirSync(SKILLS_DIR).filter((d) => {
  try { return statSync(join(SKILLS_DIR, d)).isDirectory(); } catch { return false; }
});

for (const dir of dirs) {
  const md = join(SKILLS_DIR, dir, 'SKILL.md');
  if (!existsSync(md)) { problems.push(`${dir}: keine SKILL.md`); continue; }
  const text = readFileSync(md, 'utf-8');
  const fm = parseFrontmatter(text);
  if (!fm) { problems.push(`${dir}: kaputtes/fehlendes Frontmatter`); continue; }

  if (!fm.name) problems.push(`${dir}: kein name im Frontmatter`);
  else if (fm.name !== dir) problems.push(`${dir}: name "${fm.name}" != Verzeichnis`);
  else if (!/^[a-z0-9-]+$/.test(fm.name)) problems.push(`${dir}: ungültiger slug "${fm.name}"`);

  if (!fm.description) problems.push(`${dir}: keine description`);
  else if (fm.description.length > 1024) problems.push(`${dir}: description zu lang (${fm.description.length})`);
  else if (fm.description.length < 40) problems.push(`${dir}: description verdächtig kurz`);

  // Pointer auf den Quell-Prompt: erstes `claude-skills/...md` im Body muss existieren.
  const ref = text.match(/`(claude-skills\/[^`]+\.md)`/);
  if (!ref) problems.push(`${dir}: kein Quell-Pointer (claude-skills/...md) im Body`);
  else if (!existsSync(resolve(REPO, ref[1]))) problems.push(`${dir}: Quelle fehlt: ${ref[1]}`);

  if (!problems.some((p) => p.startsWith(dir + ':'))) ok.push(fm.name);
}

console.log(`Geprüft: ${dirs.length} Skill-Verzeichnisse, valide: ${ok.length}`);
ok.sort().forEach((n) => console.log(`  /${n}`));
if (problems.length) {
  console.error('\nProbleme:\n' + problems.map((p) => '  - ' + p).join('\n'));
  process.exit(1);
}
console.log('\nDiscovery-Check OK: alle Skills würden von Claude Code geladen.');
