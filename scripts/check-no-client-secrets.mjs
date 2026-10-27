#!/usr/bin/env node
/**
 * Fail when a signing secret (or the code that used one) reaches the public
 * bundle. The storage webhook HMAC secret used to be inlined via
 * REACT_APP_WEBHOOK_SECRET; uploads now use server-issued tokens.
 *
 * Usage: node scripts/check-no-client-secrets.mjs [distDir]   (default: dist)
 *
 * Also greps for the *values* of STORAGE_WEBHOOK_SECRET / REACT_APP_WEBHOOK_SECRET
 * when they are set in the environment (CI can pass the real secret in), so a
 * leak is caught even under a different variable name.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

export const FORBIDDEN_MARKERS = [
  'REACT_APP_WEBHOOK_SECRET',
  'your-webhook-secret-here',
  'X-Hub-Signature-256',
];
export const SECRET_VALUE_ENV = ['STORAGE_WEBHOOK_SECRET', 'REACT_APP_WEBHOOK_SECRET'];
const SCANNED = /\.(?:js|mjs|cjs|html|json|map|css|txt)$/;

function* walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) yield* walk(p);
    else if (SCANNED.test(entry.name)) yield p;
  }
}

/** @returns {Array<{ file: string, needle: string }>} */
export function scanForSecrets(distDir, env = process.env) {
  const needles = [...FORBIDDEN_MARKERS];
  for (const key of SECRET_VALUE_ENV) {
    const v = env[key];
    if (v && v.length >= 8) needles.push(v);
  }
  const hits = [];
  for (const file of walk(distDir)) {
    const text = fs.readFileSync(file, 'utf8');
    for (const needle of needles) {
      if (text.includes(needle)) {
        const shown = FORBIDDEN_MARKERS.includes(needle) ? needle : '<value of a secret env var>';
        hits.push({ file: path.relative(distDir, file), needle: shown });
      }
    }
  }
  return hits;
}

function main() {
  const distDir = path.resolve(ROOT, process.argv[2] ?? 'dist');
  if (!fs.existsSync(distDir)) {
    console.error(`❌ ${path.relative(ROOT, distDir)} does not exist — run the build first`);
    process.exit(1);
  }
  const hits = scanForSecrets(distDir);
  if (hits.length > 0) {
    for (const h of hits) console.error(`❌ ${h.file}: contains ${h.needle}`);
    console.error('\nSecrets must never be inlined into the client bundle. Storage writes use server-issued upload tokens.');
    process.exit(1);
  }
  console.log(`✓ no client secrets in ${path.relative(ROOT, distDir) || distDir}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
