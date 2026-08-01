#!/usr/bin/env node
/**
 * thumbnail-coverage-status.js — report thumbnail coverage vs full catalog.
 */

const fs = require('fs');
const crypto = require('crypto');
const path = require('path');
const { loadThumbnailSkipIds } = require('./lib/thumbnailSkipAllowlist');

const ROOT = path.join(__dirname, '..');
const LISTS_DIR = path.join(ROOT, 'public', 'shader-lists');
const THUMB_DIR = path.join(ROOT, 'public', 'thumbnails');
const MANIFEST_PATH = path.join(THUMB_DIR, 'manifest.json');
const INTEGRITY_PATH = path.join(ROOT, 'reports', 'thumbnail_integrity_audit.json');

function loadAllCatalogIds() {
  const files = fs.readdirSync(LISTS_DIR).filter(f => f.endsWith('.json'));
  const ids = new Set();
  for (const file of files) {
    const list = JSON.parse(fs.readFileSync(path.join(LISTS_DIR, file), 'utf8'));
    for (const entry of list) {
      if (entry?.id) ids.add(entry.id);
    }
  }
  return ids;
}

function hasThumbFile(id, manifest) {
  if (!manifest[id]) return false;
  return fs.existsSync(path.join(THUMB_DIR, `${id}.png`));
}

function thumbnailFingerprint(files) {
  const digest = crypto.createHash('sha256');
  for (const file of files) {
    digest.update(file, 'utf8');
    digest.update(Buffer.from([0]));
    digest.update(fs.readFileSync(path.join(THUMB_DIR, file)));
    digest.update(Buffer.from([0]));
  }
  return digest.digest('hex');
}

const catalog = loadAllCatalogIds();
const skipIds = loadThumbnailSkipIds();
const eligible = new Set([...catalog].filter(id => !skipIds.has(id)));
const manifest = fs.existsSync(MANIFEST_PATH)
  ? JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'))
  : {};
const integrity = fs.existsSync(INTEGRITY_PATH)
  ? JSON.parse(fs.readFileSync(INTEGRITY_PATH, 'utf8'))
  : null;

let withThumb = 0;
let withThumbEligible = 0;
const missingPng = [];

for (const id of catalog) {
  if (hasThumbFile(id, manifest)) {
    withThumb++;
    if (eligible.has(id)) withThumbEligible++;
  } else if (manifest[id]) {
    missingPng.push(id);
  }
}

const orphanManifest = Object.keys(manifest).filter(id => {
  return !fs.existsSync(path.join(THUMB_DIR, `${id}.png`));
});

const total = catalog.size;
const eligibleTotal = eligible.size;
const pct = total ? ((withThumb / total) * 100).toFixed(1) : '0.0';
const eligiblePct = eligibleTotal
  ? ((withThumbEligible / eligibleTotal) * 100).toFixed(1)
  : '0.0';
const target80 = Math.ceil(total * 0.8);
const target80Eligible = Math.ceil(eligibleTotal * 0.8);
const pngFiles = fs.readdirSync(THUMB_DIR).filter(file => file.endsWith('.png')).sort();
const pngCount = pngFiles.length;
const pngFingerprint = thumbnailFingerprint(pngFiles);
const integrityCurrent = integrity && integrity.scanned === pngCount &&
  integrity.png_fingerprint === pngFingerprint;
const flaggedIds = integrityCurrent
  ? new Set((integrity.entries || []).map(entry => entry.id))
  : new Set();
const flaggedEligible = [...flaggedIds].filter(id => eligible.has(id) && hasThumbFile(id, manifest)).length;
const healthyEligible = withThumbEligible - flaggedEligible;
const healthyEligiblePct = eligibleTotal
  ? ((healthyEligible / eligibleTotal) * 100).toFixed(1)
  : '0.0';

console.log(`Thumbnail coverage: ${withThumb}/${total} (${pct}%)`);
console.log(`Eligible coverage (excl. skip list): ${withThumbEligible}/${eligibleTotal} (${eligiblePct}%)`);
console.log(`80% target: ${target80} thumbnails (${Math.max(0, target80 - withThumb)} remaining)`);
console.log(`80% eligible target: ${target80Eligible} (${Math.max(0, target80Eligible - withThumbEligible)} remaining)`);

if (integrityCurrent) {
  const auditLabel = integrity.generated_at ? `; audit ${integrity.generated_at}` : '';
  console.log(
    `Healthy eligible coverage (excl. ${flaggedEligible} integrity flags${auditLabel}): ` +
    `${healthyEligible}/${eligibleTotal} (${healthyEligiblePct}%)`,
  );
  console.log(
    `80% healthy target: ${target80Eligible} ` +
    `(${Math.max(0, target80Eligible - healthyEligible)} remaining)`,
  );
} else if (integrity) {
  console.log(
    `Integrity audit is stale for the current ${pngCount} PNG files; ` +
    'run python3 scripts/audit_thumbnail_integrity.py',
  );
}

if (skipIds.size > 0) {
  console.log(`Skip allowlist: ${skipIds.size} shader(s) excluded from eligible denominator`);
}

if (missingPng.length > 0) {
  console.log(`Manifest entries missing PNG: ${missingPng.length}`);
  if (missingPng.length <= 10) {
    for (const id of missingPng) console.log(`  - ${id}`);
  }
}

if (orphanManifest.length > 0) {
  console.log(`Orphan manifest entries (no PNG): ${orphanManifest.length}`);
  if (orphanManifest.length <= 10) {
    for (const id of orphanManifest) console.log(`  - ${id}`);
  }
}
