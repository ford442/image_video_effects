#!/usr/bin/env node
/**
 * verify-generated-sync.mjs — fail when a committed generated file differs from a fresh
 * regeneration. Covers:
 *
 *   src/renderer/multipassRegistry.ts          scripts/buildMultipassRegistry.js
 *   public/shader-lists/*.json                  scripts/generate_shader_lists.js
 *   public/shader-id-aliases.json (+ src/utils copy)   (written by generate_shader_lists.js)
 *   src/types/ShaderDefinition.ts, src/contracts/shaderDefinition.validate.js
 *                                               scripts/generate-shader-definition-types.mjs
 *
 * The generators write in place, so this snapshots the files, regenerates, compares, and always
 * restores the snapshot: running it never leaves the tree modified. Deliberately not covered:
 * reports/*.json (timestamps), public/shader-search-index.json (needs the CLIP model/network),
 * the unified manifest (gitignored) and README counts (rewritten by build:manifest).
 *
 * Determinism: SHADER_LIST_BASE_URL and friends would rewrite every url to absolute, so they are
 * removed from the environment; `_meta.generated_at` in the alias files is a date and is ignored.
 */
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { generate as generateTypes } from './generate-shader-definition-types.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const LISTS_DIR = path.join(ROOT, 'public', 'shader-lists');
const rel = (f) => path.relative(ROOT, f);

const FIXED = [
  'src/renderer/multipassRegistry.ts',
  'public/shader-id-aliases.json',
  'src/utils/shader-id-aliases.json',
  'src/types/ShaderDefinition.ts',
  'src/contracts/shaderDefinition.validate.js',
].map((f) => path.join(ROOT, f));

const read = (f) => (fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : null);
const listFiles = () =>
  fs.existsSync(LISTS_DIR)
    ? fs.readdirSync(LISTS_DIR).filter((f) => f.endsWith('.json')).sort().map((f) => path.join(LISTS_DIR, f))
    : [];
const normalize = (text) => text?.replace(/"generated_at":\s*"[^"]*"/, '"generated_at": "<date>"') ?? null;

function snapshot() {
  const snap = new Map();
  for (const f of [...FIXED, ...listFiles()]) snap.set(f, read(f));
  return snap;
}

function restore(snap) {
  for (const f of listFiles()) if (!snap.has(f)) fs.rmSync(f);
  for (const [f, text] of snap) {
    if (text === null) fs.rmSync(f, { force: true });
    else if (read(f) !== text) fs.writeFileSync(f, text);
  }
}

function run(cmd, args) {
  const env = { ...process.env };
  for (const k of ['SHADER_LIST_BASE_URL', 'REACT_APP_SHADER_BASE_URL', 'SHADER_BASE_URL']) delete env[k];
  const r = spawnSync(cmd, args, { cwd: ROOT, env, encoding: 'utf8' });
  if (r.status !== 0) {
    throw new Error(`${cmd} ${args.join(' ')} failed (${r.status}):\n${r.stdout}\n${r.stderr}`);
  }
}

function firstDifference(a, b) {
  const x = (a ?? '').split('\n');
  const y = (b ?? '').split('\n');
  for (let i = 0; i < Math.max(x.length, y.length); i += 1) {
    if (x[i] !== y[i]) {
      return `    line ${i + 1}\n      committed:   ${(x[i] ?? '<end of file>').slice(0, 140)}\n      regenerated: ${(y[i] ?? '<end of file>').slice(0, 140)}`;
    }
  }
  return '    (no line difference)';
}

async function main() {
  const before = snapshot();
  const stale = [];
  try {
    run('node', ['scripts/buildMultipassRegistry.js']);
    run('node', ['scripts/generate_shader_lists.js']);
    const typeOutputs = await generateTypes();
    for (const [f, text] of Object.entries(typeOutputs)) fs.writeFileSync(f, text);

    const after = snapshot();
    for (const f of new Set([...before.keys(), ...after.keys()])) {
      const a = before.get(f) ?? null;
      const b = after.get(f) ?? null;
      if (normalize(a) !== normalize(b)) {
        const why = a === null ? 'is missing from the repo' : b === null ? 'is no longer generated' : 'differs';
        stale.push(`  ${rel(f)} ${why}\n${firstDifference(normalize(a), normalize(b))}`);
      }
    }
  } finally {
    restore(before);
  }

  if (stale.length) {
    console.error(`verify-generated-sync: ${stale.length} committed generated file(s) are out of date:\n`);
    console.error(stale.join('\n'));
    console.error(
      '\nRegenerate and commit:\n' +
        '  node scripts/buildMultipassRegistry.js && node scripts/generate_shader_lists.js && \\\n' +
        '  node scripts/generate-shader-definition-types.mjs',
    );
    process.exit(1);
  }
  console.log('verify-generated-sync: committed generated files match a fresh regeneration');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
