#!/usr/bin/env node
/**
 * generate-extrabuffer-triage-md.mjs — human-readable summary of dynamic-index triage baseline.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dynamicPath = path.join(repoRoot, 'reports', 'extrabuffer_dynamic_index_baseline.json');
const baselinePath = path.join(repoRoot, 'reports', 'extrabuffer_write_audit_baseline.json');
const outPath = path.join(repoRoot, 'reports', 'extrabuffer_dynamic_index_triage.md');

function loadJson(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function main() {
  const dynamic = loadJson(dynamicPath);
  const baseline = loadJson(baselinePath);
  const entries = dynamic.entries ?? [];

  const byFile = new Map();
  for (const e of entries) {
    if (!byFile.has(e.file)) byFile.set(e.file, []);
    byFile.get(e.file).push(e);
  }

  const lines = [
    '# extraBuffer dynamic-index triage',
    '',
    `Generated from \`reports/extrabuffer_dynamic_index_baseline.json\` (${entries.length} write sites).`,
    'Machine-readable baseline is SoT; this file is documentation only.',
    '',
    '## Verdict',
    '',
    'All baselined dynamic-index writes use const-indexed spring/state slots at `extraBuffer[133..138]`.',
    'Static analysis cannot prove the index stays in the safe zone; human triage accepted bounded slots.',
    '',
    '## Baseline sections (`extrabuffer_write_audit_baseline.json`)',
    '',
    `- **engine_owned** — ${baseline.engine_owned?.entries?.length ?? 0} file(s): FFT-zone writes documented as engine/audio coupling. Do not add entries.`,
    `- **shader_bug** — ${baseline.shader_bug?.entries?.length ?? 0} file(s): persistent state in reserved/FFT zone; remap to \`[133..255]\` when rewritten.`,
    '',
    '## Per-file dynamic writes',
    '',
  ];

  for (const [file, rows] of [...byFile.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
    lines.push(`### \`${file}\``);
    lines.push('');
    lines.push('| Line | Expression | Triage |');
    lines.push('|-----:|------------|--------|');
    for (const row of rows.sort((a, b) => a.line - b.line)) {
      const verdict = row.reason ?? 'bounded safe zone (133+)';
      lines.push(`| ${row.line} | \`${row.expr}\` | ${verdict} |`);
    }
    lines.push('');
  }

  fs.writeFileSync(outPath, `${lines.join('\n')}\n`);
  console.log(`Wrote ${path.relative(repoRoot, outPath)}`);
}

main();
