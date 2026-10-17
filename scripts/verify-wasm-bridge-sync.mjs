#!/usr/bin/env node
/**
 * Fail if generated WASM bridge copies drift from src/wasm TypeScript SoT, if the
 * contract-generated files (_generated.ts, _contracts.ts, contracts.h) are stale,
 * if the emitted module typings (public/wasm/pixelocity_wasm.d.ts, --emit-tsd)
 * disagree with wasm_exports.json, or if a bridge file calls ccall by hand.
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BRIDGE_MODULES, emitWasmBridgeToDir } from './emit-wasm-bridge.mjs';
import { emitAll, loadExportSignatures } from './emit-wasm-contracts.mjs';

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

// ── Contract-generated files are current ───────────────────────────────────
try {
  for (const [file, content] of Object.entries(emitAll())) {
    const current = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
    if (current !== content) errors.push(`stale generated file: ${path.relative(repoRoot, file)} (npm run wasm:contracts)`);
  }
} catch (err) {
  errors.push(`emit-wasm-contracts failed: ${err.message}`);
}

// ── --emit-tsd typings of the committed artifact match wasm_exports.json ─────
/** `_name(_0: number, ...): ret;` members of the emitted WasmModule interface. */
export function parseEmittedExports(dts) {
  const body = dts.match(/interface WasmModule \{([\s\S]*?)\n\}/);
  if (!body) return null;
  const out = new Map();
  for (const m of body[1].matchAll(/^\s*_(\w+)\(([^)]*)\):\s*(\w+);/gm)) {
    const arity = m[2].trim() ? m[2].split(',').length : 0;
    out.set(m[1], { arity, returns: m[3] });
  }
  return out;
}

const dtsRel = 'public/wasm/pixelocity_wasm.d.ts';
if (!exists(dtsRel)) {
  errors.push(`missing ${dtsRel} (the release build emits it with --emit-tsd; npm run wasm:build)`);
} else {
  const emitted = parseEmittedExports(fs.readFileSync(path.join(repoRoot, dtsRel), 'utf8'));
  const contract = JSON.parse(fs.readFileSync(path.join(repoRoot, 'src/contracts/wasm_exports.json'), 'utf8'));
  const runtimeOnly = new Set((contract.runtimeOnlyExports ?? []).map((n) => n.slice(1)));
  if (!emitted) {
    errors.push(`${dtsRel}: no WasmModule interface`);
  } else {
    for (const sig of loadExportSignatures(contract)) {
      const e = emitted.get(sig.name);
      if (!e) {
        errors.push(`${dtsRel} lacks _${sig.name}: the committed artifact predates wasm_exports.json (rebuild)`);
        continue;
      }
      if (e.arity !== sig.args.length) {
        errors.push(`_${sig.name}: C++ takes ${e.arity} args, wasm_exports.json lists ${sig.args.length}`);
      }
      if ((e.returns === 'void') !== (sig.returns === 'void')) {
        errors.push(`_${sig.name}: C++ returns ${e.returns}, wasm_exports.json says ${sig.returns}`);
      }
    }
    for (const name of emitted.keys()) {
      if (!runtimeOnly.has(name) && !(name in contract.exports)) {
        errors.push(`${dtsRel} exports _${name}, missing from wasm_exports.json exports`);
      }
    }
  }
}

// ── Only the call seam calls into the module ─────────────────────────────────
for (const name of fs.readdirSync(path.join(repoRoot, 'src/wasm/bridge'))) {
  if (!name.endsWith('.ts') || name.endsWith('.test.ts') || name === 'call.ts' || name === 'state.ts') continue;
  const src = fs.readFileSync(path.join(repoRoot, 'src/wasm/bridge', name), 'utf8');
  if (/\.ccall\s*\(/.test(src) || /\bcwrap\s*\(/.test(src)) {
    errors.push(`src/wasm/bridge/${name} calls ccall/cwrap by hand; use the generated wrappers (_generated.ts)`);
  }
}

if (errors.length > 0) {
  console.error('verify:wasm-bridge-sync failed:');
  for (const err of errors) console.error(`  ❌ ${err}`);
  process.exit(1);
}

console.log('✅ WASM bridge copies match src/wasm TypeScript source of truth');
