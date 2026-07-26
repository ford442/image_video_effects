#!/usr/bin/env node
/**
 * thumbnail-coverage-status.js — report thumbnail coverage vs full catalog.
 */

const fs = require('fs');
const path = require('path');
const { loadThumbnailSkipIds } = require('./lib/thumbnailSkipAllowlist');

const ROOT = path.join(__dirname, '..');
const LISTS_DIR = path.join(ROOT, 'public', 'shader-lists');
const THUMB_DIR = path.join(ROOT, 'public', 'thumbnails');
const MANIFEST_PATH = path.join(THUMB_DIR, 'manifest.json');

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

const catalog = loadAllCatalogIds();
const skipIds = loadThumbnailSkipIds();
const eligible = new Set([...catalog].filter(id => !skipIds.has(id)));
const manifest = fs.existsSync(MANIFEST_PATH)
  ? JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'))
  : {};

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

console.log(`Thumbnail coverage: ${withThumb}/${total} (${pct}%)`);
console.log(`Eligible coverage (excl. skip list): ${withThumbEligible}/${eligibleTotal} (${eligiblePct}%)`);
console.log(`80% target: ${target80} thumbnails (${Math.max(0, target80 - withThumb)} remaining)`);
console.log(`80% eligible target: ${target80Eligible} (${Math.max(0, target80Eligible - withThumbEligible)} remaining)`);

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
