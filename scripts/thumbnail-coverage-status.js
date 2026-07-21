#!/usr/bin/env node
/**
 * thumbnail-coverage-status.js — report thumbnail coverage vs full catalog.
 */

const fs = require('fs');
const path = require('path');

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

const catalog = loadAllCatalogIds();
const manifest = fs.existsSync(MANIFEST_PATH)
  ? JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'))
  : {};

let withThumb = 0;
const missingPng = [];

for (const id of catalog) {
  if (manifest[id]) {
    const pngPath = path.join(THUMB_DIR, `${id}.png`);
    if (!fs.existsSync(pngPath)) {
      missingPng.push(id);
    } else {
      withThumb++;
    }
  }
}

const orphanManifest = Object.keys(manifest).filter(id => {
  const pngPath = path.join(THUMB_DIR, `${id}.png`);
  return !fs.existsSync(pngPath);
});

const total = catalog.size;
const pct = total ? ((withThumb / total) * 100).toFixed(1) : '0.0';
const target80 = Math.ceil(total * 0.8);

console.log(`Thumbnail coverage: ${withThumb}/${total} (${pct}%)`);
console.log(`80% target: ${target80} thumbnails (${Math.max(0, target80 - withThumb)} remaining)`);

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
