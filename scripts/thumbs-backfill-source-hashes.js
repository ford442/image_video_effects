#!/usr/bin/env node
'use strict';
/**
 * thumbs-backfill-source-hashes.js — one-time migration.
 *
 * Existing entries in public/thumbnails/manifest.json have no `source_hash`,
 * so every thumbnail would look "unknown". For each such entry this stamps the
 * current hash ONLY when git shows no commit to the shader's source files after
 * the thumbnail's `generated_at` (and the files are not dirty). Everything else
 * stays unstamped and is treated as needing a new capture.
 *
 *   npm run thumbs:backfill-hashes              # git-checked (recommended)
 *   npm run thumbs:backfill-hashes -- --dry-run
 *   npm run thumbs:backfill-hashes -- --assume-fresh   # stamp everything, no git check
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { ROOT, createHashContext, computeSourceHash, sourceFilesFor } = require('./lib/shaderSourceHash');

const MANIFEST_PATH = path.join(ROOT, 'public', 'thumbnails', 'manifest.json');
const UNHEALTHY_PATH = path.join(ROOT, 'public', 'thumbnails', 'unhealthy.json');

/** Black / error PNGs found by scripts/audit_thumbnail_integrity.py — never stamp these fresh. */
function unhealthyIds() {
  if (!fs.existsSync(UNHEALTHY_PATH)) return new Set();
  return new Set(JSON.parse(fs.readFileSync(UNHEALTHY_PATH, 'utf8')).ids || []);
}

function git(args) {
  return execFileSync('git', args, { cwd: ROOT, stdio: ['ignore', 'pipe', 'ignore'] }).toString();
}

function dirtyFiles() {
  const out = new Set();
  for (const line of git(['status', '--porcelain', '--', 'public/shaders', 'shader_definitions']).split('\n')) {
    if (line.length > 3) out.add(line.slice(3).trim());
  }
  return out;
}

function main() {
  const argv = process.argv.slice(2);
  const dryRun = argv.includes('--dry-run');
  const assumeFresh = argv.includes('--assume-fresh');
  const manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
  const ctx = createHashContext();
  const dirty = assumeFresh ? new Set() : dirtyFiles();
  const unhealthy = unhealthyIds();

  let stamped = 0;
  let stale = 0;
  let noSource = 0;
  let unhealthySkipped = 0;
  for (const [id, entry] of Object.entries(manifest)) {
    if (entry.source_hash) continue;
    if (unhealthy.has(id)) { unhealthySkipped++; continue; }
    const hash = computeSourceHash(id, ctx);
    if (!hash) { noSource++; continue; }
    if (!assumeFresh) {
      const files = sourceFilesFor(id, ctx);
      if (files.some(f => dirty.has(f))) { stale++; continue; }
      const last = git(['log', '-1', '--format=%cI', '--', ...files]).trim();
      if (last && entry.generated_at && new Date(last) > new Date(entry.generated_at)) { stale++; continue; }
    }
    entry.source_hash = hash;
    stamped++;
  }

  if (!dryRun) fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + '\n');
  console.log(
    `[backfill] stamped=${stamped} changed-since-capture=${stale} unhealthy=${unhealthySkipped} ` +
    `no-source=${noSource}${dryRun ? ' (dry run)' : ''}`,
  );
  if (stale + unhealthySkipped > 0) {
    console.log('[backfill] Changed-since-capture and unhealthy thumbnails stay unstamped → queued for recapture.');
  }
}

if (require.main === module) main();
