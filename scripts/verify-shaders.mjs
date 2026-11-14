#!/usr/bin/env node
/**
 * verify-shaders.mjs — every blocking shader gate CI runs, in one local command.
 *
 * A shader batch used to learn about these gates from a red `main`: the naga
 * known-failure list, the prelude `pending` ledger and the workgroup audit each
 * failed a merge that had passed review (#1674). Run this before pushing a batch.
 *
 *   npm run verify:shaders          # run every gate, report all failures (does not stop at the first)
 *   npm run verify:shaders:fix      # first let the ledgers shrink themselves, then run every gate
 *   node scripts/verify-shaders.mjs --base origin/develop
 *   node scripts/verify-shaders.mjs --list
 *
 * --fix only ever removes entries that are provably done (a pending id that no
 * longer pastes the header; a naga known-failure that now validates). It never
 * adds an exemption, so it cannot hide a new break.
 *
 * GATES is the list; scripts/verify-shaders.test.mjs fails when a command here
 * is not also a step in .github/workflows/ci.yml, so the two cannot drift.
 * Some gates rewrite files under reports/ (as they do in CI).
 */

import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

/** `ci` is the exact command in ci.yml; `{base}` is the ref to diff against. `fix` is appended under --fix. */
export const GATES = [
  { name: 'WGSL include expanders (TS ↔ Python)', ci: 'node scripts/verify-wgsl-include.mjs' },
  { name: 'Prelude migration ledger', ci: 'python3 scripts/check_prelude_migration.py --base {base}', fix: '--fix' },
  { name: 'naga validation (full catalog)', ci: 'node scripts/verify-naga-wasm.mjs --all --report', fix: '--fix' },
  { name: 'Workgroup convention scan (full tree)', ci: 'python3 scripts/wgsl_precommit_gate.py --full-tree' },
  { name: 'WGSL pre-commit gate (changed files)', ci: 'python3 scripts/wgsl_precommit_gate.py --base {base} --skip-naga' },
  { name: 'Shader definitions (schema)', ci: 'node scripts/validate_shader_definitions.mjs' },
  { name: 'Catalog hygiene (defs ↔ WGSL)', ci: 'python3 scripts/audit_orphan_shader_defs.py --ci-gate' },
  { name: 'extraBuffer reserved zone', ci: 'python3 scripts/audit_extrabuffer.py' },
  { name: 'Dead sliders', ci: 'python3 scripts/audit_dead_sliders.py' },
  { name: 'Workgroup size limits', ci: 'python3 scripts/wgsl_workgroup_detector.py --gate' },
  { name: 'Catalog drift', ci: 'python3 scripts/audit_catalog_consistency.py --ensure-lists --gate' },
];

function parseArgs(argv) {
  const args = { fix: false, list: false, base: 'origin/main' };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--fix') args.fix = true;
    else if (a === '--list') args.list = true;
    else if (a === '--base') args.base = argv[++i];
    else if (a.startsWith('--base=')) args.base = a.slice('--base='.length);
    else throw new Error(`unknown argument: ${a}`);
  }
  return args;
}

export function commandFor(gate, { base, fix }) {
  const cmd = gate.ci.replace('{base}', base);
  return fix && gate.fix ? `${cmd} ${gate.fix}` : cmd;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.list) {
    for (const g of GATES) console.log(commandFor(g, args));
    return 0;
  }

  const failures = [];
  for (const gate of GATES) {
    const cmd = commandFor(gate, args);
    console.log(`\n━━ ${gate.name}\n   $ ${cmd}`);
    const [bin, ...rest] = cmd.split(' ');
    const r = spawnSync(bin, rest, { cwd: ROOT, stdio: 'inherit' });
    if (r.status !== 0) failures.push({ gate, cmd });
  }

  console.log('\n━━ Summary');
  if (failures.length === 0) {
    console.log(`✅ all ${GATES.length} shader gates pass`);
    return 0;
  }
  for (const { gate, cmd } of failures) console.log(`❌ ${gate.name}\n   $ ${cmd}`);
  if (!args.fix && failures.some((f) => f.gate.fix)) {
    console.log('\nA ledger gate failed. If it only asks for an entry to be removed: npm run verify:shaders:fix');
  }
  console.log(`\n${failures.length} of ${GATES.length} shader gates failed`);
  return 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exit(main());
}
