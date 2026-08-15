#!/usr/bin/env node
/**
 * Fail a pull request when adding shader definitions lowers thumbnail coverage.
 *
 * The base tree is read through git so this check compares the PR with the
 * actual target branch, rather than relying on a hand-maintained baseline.
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const LISTS_DIR = path.join(ROOT, 'public', 'shader-lists');
const THUMB_DIR = path.join(ROOT, 'public', 'thumbnails');
const THUMB_MANIFEST_PATH = path.join(THUMB_DIR, 'manifest.json');

function gitText(args) {
  return execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
}

function readGitJson(ref, file) {
  try {
    return JSON.parse(gitText(['show', `${ref}:${file}`]));
  } catch {
    return null;
  }
}

function loadCurrentCatalog() {
  const ids = new Set();
  for (const file of fs.readdirSync(LISTS_DIR).filter(name => name.endsWith('.json'))) {
    const list = JSON.parse(fs.readFileSync(path.join(LISTS_DIR, file), 'utf8'));
    for (const entry of list) {
      if (entry?.id) ids.add(entry.id);
    }
  }
  return ids;
}

function loadBaseCatalog(ref) {
  const manifest = readGitJson(ref, 'public/shader-manifest-unified.json');
  if (manifest?.shaders) {
    return new Set(manifest.shaders.map(shader => shader.id).filter(Boolean));
  }

  const ids = new Set();
  for (const file of gitText(['ls-tree', '-r', '--name-only', ref, 'public/shader-lists'])
    .split('\n')
    .filter(name => name.endsWith('.json'))) {
    const list = readGitJson(ref, file);
    for (const entry of list || []) {
      if (entry?.id) ids.add(entry.id);
    }
  }
  return ids;
}

function loadBasePngs(ref) {
  return new Set(
    gitText(['ls-tree', '-r', '--name-only', ref, 'public/thumbnails'])
      .split('\n')
      .filter(file => file.endsWith('.png'))
      .map(file => path.basename(file, '.png')),
  );
}

function loadCurrentPngs() {
  return new Set(
    fs.readdirSync(THUMB_DIR)
      .filter(file => file.endsWith('.png'))
      .map(file => path.basename(file, '.png')),
  );
}

function loadBaseThumbManifest(ref) {
  return readGitJson(ref, 'public/thumbnails/manifest.json') || {};
}

function loadCurrentThumbManifest() {
  return fs.existsSync(THUMB_MANIFEST_PATH)
    ? JSON.parse(fs.readFileSync(THUMB_MANIFEST_PATH, 'utf8'))
    : {};
}

function healthyIds(catalog, pngs, manifest) {
  return new Set([...catalog].filter(id => pngs.has(id) && Boolean(manifest[id])));
}

function changedAddedDefinitionIds(ref) {
  return gitText(['diff', '--diff-filter=A', '--name-only', `${ref}...HEAD`, '--', 'shader_definitions'])
    .split('\n')
    .filter(file => file.endsWith('.json'))
    .map(file => {
      try {
        const value = JSON.parse(fs.readFileSync(path.join(ROOT, file), 'utf8'));
        return Array.isArray(value) ? value[0]?.id : value?.id;
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

function parseArgs(argv) {
  const baseIndex = argv.indexOf('--base-ref');
  return {
    baseRef: baseIndex >= 0 ? argv[baseIndex + 1] : 'origin/main',
  };
}

function main() {
  const { baseRef } = parseArgs(process.argv.slice(2));
  const baseCatalog = loadBaseCatalog(baseRef);
  if (baseCatalog.size === 0) {
    throw new Error(`Could not load a shader catalog from git ref "${baseRef}"`);
  }

  const currentCatalog = loadCurrentCatalog();
  const baseHealthy = healthyIds(baseCatalog, loadBasePngs(baseRef), loadBaseThumbManifest(baseRef));
  const currentHealthy = healthyIds(currentCatalog, loadCurrentPngs(), loadCurrentThumbManifest());
  const basePct = (baseHealthy.size / baseCatalog.size) * 100;
  const currentPct = (currentHealthy.size / currentCatalog.size) * 100;
  const addedIds = changedAddedDefinitionIds(baseRef);
  const missingAddedIds = addedIds.filter(id => !currentHealthy.has(id));

  console.log(
    `Thumbnail PR baseline: ${baseHealthy.size}/${baseCatalog.size} (${basePct.toFixed(1)}%)`,
  );
  console.log(
    `Thumbnail PR head: ${currentHealthy.size}/${currentCatalog.size} (${currentPct.toFixed(1)}%)`,
  );

  if (addedIds.length === 0) {
    console.log('No new shader definitions in this pull request; coverage check is informational.');
    return;
  }

  if (missingAddedIds.length > 0) {
    console.error(
      `New shader definitions without healthy thumbnails (${missingAddedIds.length}): ` +
      missingAddedIds.join(', '),
    );
    process.exitCode = 1;
  }

  if (currentPct + 1e-9 < basePct) {
    console.error(
      `Thumbnail coverage regressed by ${(basePct - currentPct).toFixed(2)} percentage points.`,
    );
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = {
  healthyIds,
  loadCurrentCatalog,
  parseArgs,
};
