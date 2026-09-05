#!/usr/bin/env node
/**
 * Fail if generated WASM bridge copies drift from src/wasm TypeScript SoT.
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BRIDGE_MODULES, emitWasmBridgeToDir } from './emit-wasm-bridge.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const errors = [];

function read(rel) {
  return fs.readFileSync(path.join(repoRoot, rel));
}

function exists(rel) {
  return fs.existsSync(path.join(repoRoot, rel));
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pixelocity-wasm-bridge-verify-'));

try {
  await emitWasmBridgeToDir(tmp);

  const targets = [
    ['wasm_renderer/wasm_bridge.js', 'wasm_bridge.js'],
    ['public/wasm/wasm_bridge.js', 'wasm_bridge.js'],
    ['wasm_renderer/wasm_bridge.d.ts', 'wasm_bridge.d.ts'],
    ['public/wasm/wasm_bridge.d.ts', 'wasm_bridge.d.ts'],
  ];

  for (const name of BRIDGE_MODULES) {
    targets.push([`wasm_renderer/bridge/${name}`, `bridge/${name}`]);
    targets.push([`public/wasm/bridge/${name}`, `bridge/${name}`]);
  }

  for (const [rel, emitted] of targets) {
    if (!exists(rel)) {
      errors.push(`missing generated copy: ${rel}`);
      continue;
    }
    const expected = fs.readFileSync(path.join(tmp, emitted));
    const actual = read(rel);
    if (!expected.equals(actual)) {
      errors.push(`drift: ${rel} does not match emit from src/wasm`);
    }
  }

  const srcDts = read('src/wasm/wasm_bridge.d.ts');
  if (!srcDts.equals(read('wasm_renderer/wasm_bridge.d.ts'))) {
    errors.push('src/wasm/wasm_bridge.d.ts != wasm_renderer/wasm_bridge.d.ts');
  }

  const wrJs = read('wasm_renderer/wasm_bridge.js');
  const pubJs = read('public/wasm/wasm_bridge.js');
  if (!wrJs.equals(pubJs)) {
    errors.push('wasm_renderer/wasm_bridge.js != public/wasm/wasm_bridge.js');
  }

  for (const dirRel of ['wasm_renderer/bridge', 'public/wasm/bridge']) {
    const dir = path.join(repoRoot, dirRel);
    if (!fs.existsSync(dir)) {
      errors.push(`missing directory: ${dirRel}`);
      continue;
    }
    const extra = fs.readdirSync(dir).filter((name) => !BRIDGE_MODULES.includes(name));
    if (extra.length > 0) {
      errors.push(`unexpected files in ${dirRel}: ${extra.join(', ')}`);
    }
  }

  if (exists('src/wasm/wasm_bridge.js')) {
    errors.push('src/wasm/wasm_bridge.js must not be generated — webpack compiles wasm_bridge.ts');
  }
  const srcBridgeJs = fs
    .readdirSync(path.join(repoRoot, 'src/wasm/bridge'))
    .filter((name) => name.endsWith('.js'));
  if (srcBridgeJs.length > 0) {
    errors.push(`hand-edited/generated JS still in src/wasm/bridge: ${srcBridgeJs.join(', ')}`);
  }
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}

if (errors.length > 0) {
  console.error('verify:wasm-bridge-sync failed:');
  for (const err of errors) console.error(`  ❌ ${err}`);
  process.exit(1);
}

console.log('✅ WASM bridge copies match src/wasm TypeScript source of truth');
