#!/usr/bin/env node
'use strict';
/**
 * build-shader-source-hashes.js
 *
 * Writes public/thumbnails/source-hashes.json — the current content hash of
 * every shader plus its last recorded upgrade date. The in-app Shader Scanner
 * compares these against public/thumbnails/manifest.json to find thumbnails
 * that are missing or out of date. Runs in prestart / prebuild.
 *
 * Generated file (gitignored): regenerate with `npm run build:source-hashes`.
 */
const fs = require('fs');
const path = require('path');
const { ROOT, HASH_ALGORITHM, createHashContext, computeAllSourceHashes } = require('./lib/shaderSourceHash');
const { loadThumbnailSkipIds } = require('./lib/thumbnailSkipAllowlist');

const OUT_PATH = path.join(ROOT, 'public', 'thumbnails', 'source-hashes.json');
const LEDGER_PATH = path.join(ROOT, 'reports', 'shader-upgrade-ledger.json');

function lastUpgradedFromLedger() {
  if (!fs.existsSync(LEDGER_PATH)) return {};
  try {
    const ledger = JSON.parse(fs.readFileSync(LEDGER_PATH, 'utf8'));
    const out = {};
    for (const [id, rec] of Object.entries(ledger.shaders || {})) {
      const last = (rec.history || []).filter(h => h.event === 'upgraded').pop();
      if (last) out[id] = { date: last.date, note: last.note || null, count: rec.history.filter(h => h.event === 'upgraded').length };
    }
    return out;
  } catch {
    return {};
  }
}

function main() {
  const started = Date.now();
  const ctx = createHashContext();
  const hashes = computeAllSourceHashes(ctx);
  const missingWgsl = [...ctx.definitions.keys()].filter(id => !hashes[id]).sort();
  const payload = {
    generated_at: new Date().toISOString(),
    algorithm: HASH_ALGORITHM,
    hashes,
    upgrades: lastUpgradedFromLedger(),
    // The in-app scanner has no filesystem access, so it reads the skip allowlist from here.
    skip: [...loadThumbnailSkipIds()].sort(),
  };
  fs.mkdirSync(path.dirname(OUT_PATH), { recursive: true });
  fs.writeFileSync(OUT_PATH, JSON.stringify(payload));
  console.log(
    `[source-hashes] ${Object.keys(hashes).length} shaders hashed, ${missingWgsl.length} missing WGSL, ` +
    `${payload.skip.length} skipped, in ${Date.now() - started}ms → ${path.relative(ROOT, OUT_PATH)}`,
  );
  if (missingWgsl.length > 0) console.warn(`[source-hashes] no WGSL for: ${missingWgsl.join(', ')}`);
}

if (require.main === module) main();
module.exports = { OUT_PATH, LEDGER_PATH };
