#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { gzipSync } from 'node:zlib';

const DEFAULT_MAIN_GZIP_LIMIT_KIB = 320;
const buildDir = path.resolve(process.argv[2] || 'build');
const manifestPath = path.join(buildDir, 'asset-manifest.json');

function fail(message) {
  console.error(`Bundle policy failed: ${message}`);
  process.exitCode = 1;
}

function normalizeAsset(asset) {
  return asset.replace(/^\.\//, '');
}

function readAsset(manifest, key) {
  const asset = manifest.files?.[key];
  if (typeof asset !== 'string') {
    fail(`asset-manifest.json does not contain ${JSON.stringify(key)}.`);
    return null;
  }

  const relativePath = normalizeAsset(asset);
  const absolutePath = path.resolve(buildDir, relativePath);
  if (!absolutePath.startsWith(`${buildDir}${path.sep}`) || !fs.existsSync(absolutePath)) {
    fail(`${key} points to a missing or invalid asset: ${asset}`);
    return null;
  }

  const contents = fs.readFileSync(absolutePath);
  return {
    key,
    relativePath,
    rawBytes: contents.length,
    gzipBytes: gzipSync(contents, { level: 9 }).length,
  };
}

if (!fs.existsSync(manifestPath)) {
  console.error(`Bundle policy failed: missing ${manifestPath}. Run the production build first.`);
  process.exit(1);
}

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const entrypoints = new Set((manifest.entrypoints || []).map(normalizeAsset));
const limitKib = Number(process.env.MAIN_BUNDLE_GZIP_LIMIT_KIB || DEFAULT_MAIN_GZIP_LIMIT_KIB);
if (!Number.isFinite(limitKib) || limitKib <= 0) {
  console.error('Bundle policy failed: MAIN_BUNDLE_GZIP_LIMIT_KIB must be a positive number.');
  process.exit(1);
}
const limitBytes = Math.round(limitKib * 1024);

const main = readAsset(manifest, 'main.js');
const lazyAssets = ['auto-dj.js', 'transformers.js', 'web-llm.js']
  .map(key => readAsset(manifest, key))
  .filter(Boolean);

if (main) {
  if (!entrypoints.has(main.relativePath)) {
    fail(`${main.relativePath} is not listed as a CRA entrypoint.`);
  }
  if (main.gzipBytes > limitBytes) {
    fail(
      `${main.relativePath} is ${(main.gzipBytes / 1024).toFixed(2)} KiB gzip; ` +
        `the limit is ${limitKib.toFixed(2)} KiB.`
    );
  }
}

for (const asset of lazyAssets) {
  if (entrypoints.has(asset.relativePath)) {
    fail(`${asset.relativePath} is an entrypoint; AI code must remain lazy-loaded.`);
  }
}

if (process.exitCode) {
  process.exit(process.exitCode);
}

console.log('Bundle policy passed:');
console.log(
  `  main: ${(main.gzipBytes / 1024).toFixed(2)} KiB gzip / ${limitKib.toFixed(2)} KiB budget`
);
for (const asset of lazyAssets) {
  console.log(`  lazy (excluded): ${asset.key} ${(asset.gzipBytes / 1024).toFixed(2)} KiB gzip`);
}

