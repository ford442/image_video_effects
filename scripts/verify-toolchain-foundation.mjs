#!/usr/bin/env node
// Runs every foundation gate and reports all failures, not just the first.
// (Replaces a 13-command `&&` chain in package.json that stopped at the first red gate.)
import { spawnSync } from 'node:child_process';

const GATES = [
  'verify:dependency-boundaries',
  'verify:css',
  'verify:shader-list-urls',
  'verify:shader-definitions',
  'verify:generated-sync',
  'verify:catalog-counts',
  'verify:wasm-bridge-sync',
  'verify:bundle-size',
  'verify:wasm-invariants',
  'verify:wgsl-include',
  'verify:prelude-migration',
  'verify:naga-wasm:all',
  'verify:thumbs-deferrals',
];

const only = process.argv.slice(2);
const gates = only.length ? GATES.filter(g => only.includes(g)) : GATES;
const failed = [];

for (const gate of gates) {
  console.log(`\n=== ${gate} ===`);
  const started = Date.now();
  const result = spawnSync('npm', ['run', '--silent', gate], { stdio: 'inherit', shell: process.platform === 'win32' });
  const seconds = ((Date.now() - started) / 1000).toFixed(1);
  if (result.status !== 0) {
    failed.push(gate);
    console.error(`--- ${gate} FAILED (exit ${result.status}, ${seconds}s)`);
  } else {
    console.log(`--- ${gate} ok (${seconds}s)`);
  }
}

console.log(`\nverify:toolchain-foundation: ${gates.length - failed.length}/${gates.length} gates passed`);
if (failed.length) {
  console.error(`Failed gates:\n${failed.map(g => `  - ${g}`).join('\n')}`);
  process.exit(1);
}
