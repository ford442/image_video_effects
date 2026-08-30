#!/usr/bin/env node
/**
 * Emit ESM copies of the TypeScript WASM bridge into wasm_renderer/ and public/wasm/.
 * Source of truth: src/wasm/bridge/*.ts + src/wasm/wasm_bridge.ts
 */
import * as esbuild from 'esbuild';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const srcWasm = path.join(repoRoot, 'src', 'wasm');
const bridgeDir = path.join(srcWasm, 'bridge');

export const BRIDGE_MODULES = [
  'api.js',
  'capture.js',
  'diagnostics.js',
  'init.js',
  'recording.js',
  'shader.js',
  'state.js',
  'uniforms.js',
  'wgslFormat.js',
];

function listTsEntries() {
  const bridgeEntries = fs
    .readdirSync(bridgeDir)
    .filter((name) => name.endsWith('.ts'))
    .map((name) => path.join(bridgeDir, name));
  return [path.join(srcWasm, 'wasm_bridge.ts'), ...bridgeEntries];
}

export async function emitWasmBridgeToDir(outDir) {
  fs.mkdirSync(outDir, { recursive: true });
  fs.mkdirSync(path.join(outDir, 'bridge'), { recursive: true });

  await esbuild.build({
    absWorkingDir: repoRoot,
    entryPoints: listTsEntries(),
    outdir: outDir,
    outbase: srcWasm,
    format: 'esm',
    platform: 'neutral',
    bundle: false,
    sourcemap: false,
    logLevel: 'silent',
    banner: {
      js: '// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)\n',
    },
  });

  fs.copyFileSync(
    path.join(srcWasm, 'wasm_bridge.d.ts'),
    path.join(outDir, 'wasm_bridge.d.ts'),
  );
}

function copyTree(fromDir, toDir) {
  fs.mkdirSync(path.join(toDir, 'bridge'), { recursive: true });
  fs.copyFileSync(path.join(fromDir, 'wasm_bridge.js'), path.join(toDir, 'wasm_bridge.js'));
  fs.copyFileSync(path.join(fromDir, 'wasm_bridge.d.ts'), path.join(toDir, 'wasm_bridge.d.ts'));
  for (const name of BRIDGE_MODULES) {
    fs.copyFileSync(path.join(fromDir, 'bridge', name), path.join(toDir, 'bridge', name));
  }
}

export async function emitWasmBridgeCopies() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pixelocity-wasm-bridge-'));
  try {
    await emitWasmBridgeToDir(tmp);
    copyTree(tmp, path.join(repoRoot, 'wasm_renderer'));
    copyTree(tmp, path.join(repoRoot, 'public', 'wasm'));
    const staleHeader = path.join(repoRoot, 'wasm_renderer', 'bridge', 'header.js');
    if (fs.existsSync(staleHeader)) fs.unlinkSync(staleHeader);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  emitWasmBridgeCopies()
    .then(() => {
      console.log('✅ Bridge modules emitted from src/wasm/*.ts → wasm_renderer + public/wasm');
    })
    .catch((err) => {
      console.error(err);
      process.exit(1);
    });
}
