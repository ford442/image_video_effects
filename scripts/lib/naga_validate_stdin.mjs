#!/usr/bin/env node
/**
 * Validate WGSL texts with the committed naga-wasm artifact.
 *
 * stdin:  JSON array of { key, source }
 * stdout: JSON object { [key]: { ok, kind, error } } where `error` is the
 *         first line of naga's message (no source locations, so the same
 *         defect before and after a line-shifting rewrite compares equal).
 *
 * Used by scripts/migrate_to_prelude.py --naga to compare each shader's naga
 * verdict before and after the prelude migration.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const { createNagaValidator } = await import(pathToFileURL(path.join(ROOT, 'public/wasm/naga_wasm.js')).href);
const { validate } = await createNagaValidator({ bytes: fs.readFileSync(path.join(ROOT, 'public/wasm/naga_wasm.wasm')) });

const input = JSON.parse(fs.readFileSync(0, 'utf8'));
const out = {};
for (const { key, source } of input) {
  const diag = validate(source);
  out[key] = diag.ok
    ? { ok: true, kind: null, error: null }
    : { ok: false, kind: diag.kind ?? null, error: String(diag.message ?? '').split('\n')[0].trim() };
}
process.stdout.write(JSON.stringify(out));
