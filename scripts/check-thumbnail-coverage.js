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
const { loadThumbnailSkipIds } = require('./lib/thumbnailSkipAllowlist');

const ROOT = path.join(__dirname, '..');
const LISTS_DIR = path.join(ROOT, 'public', 'shader-lists');
const THUMB_DIR = path.join(ROOT, 'public', 'thumbnails');
const THUMB_MANIFEST_PATH = path.join(THUMB_DIR, 'manifest.json');
const INTEGRITY_PATH = path.join(ROOT, 'reports', 'thumbnail_integrity_audit.json');
const DEFERRALS_PATH = path.join(ROOT, 'reports', 'thumbnail_deferrals.json');

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

/**
 * Load base integrity flags from git ref
 */
function loadBaseIntegrityFlags(ref) {
  const integrity = readGitJson(ref, 'reports/thumbnail_integrity_audit.json');
  return new Set((integrity?.entries || []).map(e => e.id));
}

/**
 * Load current integrity flags
 */
function loadCurrentIntegrityFlags() {
  if (!fs.existsSync(INTEGRITY_PATH)) {
    return new Set();
  }
  const integrity = JSON.parse(fs.readFileSync(INTEGRITY_PATH, 'utf8'));
  return new Set((integrity?.entries || []).map(e => e.id));
}

/**
 * Load deferral entries and validate them for current PR
 */
function loadDeferralEntries() {
  if (!fs.existsSync(DEFERRALS_PATH)) {
    return { valid: new Set(), all: [] };
  }
  const data = JSON.parse(fs.readFileSync(DEFERRALS_PATH, 'utf8'));
  const entries = data.entries || [];
  
  const today = new Date().toISOString().split('T')[0];
  const valid = new Set();
  
  for (const entry of entries) {
    if (!entry.id || !entry.expires) {
      continue; // Skip invalid entries
    }
    
    // Only include non-expired deferrals
    if (entry.expires >= today) {
      valid.add(entry.id);
    }
  }
  
  return { valid, all: entries };
}

function healthyIds(catalog, pngs, manifest, flaggedIds) {
  return new Set([...catalog].filter(id => pngs.has(id) && Boolean(manifest[id]) && !flaggedIds.has(id)));
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

  // Load eligibility (catalog minus skip list)
  const skipIds = loadThumbnailSkipIds();
  const currentCatalog = loadCurrentCatalog();
  const currentEligible = new Set([...currentCatalog].filter(id => !skipIds.has(id)));
  const baseEligible = new Set([...baseCatalog].filter(id => !skipIds.has(id)));
  
  // Load integrity flags and deferrals
  const currentIntegrity = loadCurrentIntegrityFlags();
  const baseIntegrity = loadBaseIntegrityFlags(baseRef);
  const deferrals = loadDeferralEntries();
  
  // Calculate healthy thumbnails
  const baseHealthy = healthyIds(baseEligible, loadBasePngs(baseRef), loadBaseThumbManifest(baseRef), baseIntegrity);
  const currentHealthy = healthyIds(currentEligible, loadCurrentPngs(), loadCurrentThumbManifest(), currentIntegrity);
  
  const basePct = (baseHealthy.size / baseCatalog.size) * 100;
  const currentPct = (currentHealthy.size / currentCatalog.size) * 100;
  
  // Calculate newly eligible IDs (not in skip list, not in base)
  const newlyEligible = new Set([...currentEligible].filter(id => !baseEligible.has(id)));
  
  console.log(
    `Thumbnail PR baseline: ${baseHealthy.size}/${baseCatalog.size} (${basePct.toFixed(1)}%)`,
  );
  console.log(
    `Thumbnail PR head: ${currentHealthy.size}/${currentCatalog.size} (${currentPct.toFixed(1)}%)`,
  );

  let exitCode = 0;

  // RULE 1: Check newly eligible IDs for healthy thumbnails or deferrals
  if (newlyEligible.size > 0) {
    const offendingIds = [];
    for (const id of newlyEligible) {
      const hasHealthyThumb = currentHealthy.has(id);
      const hasDeferral = deferrals.valid.has(id);
      
      if (!hasHealthyThumb && !hasDeferral) {
        offendingIds.push(id);
      }
    }
    
    if (offendingIds.length > 0) {
      console.error(
        `❌ New eligible shaders without thumbnails (${offendingIds.length}): ` +
        offendingIds.join(', '),
      );
      exitCode = 1;
    } else {
      console.log(`✓ ${newlyEligible.size} new eligible shader(s) have thumbnails or deferrals`);
    }
  } else {
    console.log('No newly eligible shaders in this pull request; coverage check is informational.');
  }

  // RULE 2: Check for thumbnail deletions
  const currentPngs = loadCurrentPngs();
  const basePngs = loadBasePngs(baseRef);
  const deletedPngs = new Set([...basePngs].filter(id => !currentPngs.has(id) && baseHealthy.has(id)));
  
  if (deletedPngs.size > 0) {
    console.error(
      `❌ Thumbnails deleted for healthy shaders (${deletedPngs.size}): ` +
      [...deletedPngs].join(', '),
    );
    exitCode = 1;
  }

  // RULE 3: Healthy count should not decrease
  if (currentHealthy.size < baseHealthy.size) {
    console.error(
      `❌ Healthy thumbnail count decreased: ${baseHealthy.size} → ${currentHealthy.size}`,
    );
    exitCode = 1;
  }

  if (exitCode === 0) {
    console.log('✓ Thumbnail coverage regression check passed');
  } else {
    console.error('❌ Thumbnail coverage regression check FAILED');
  }
  
  process.exitCode = exitCode;
}

if (require.main === module) main();

module.exports = {
  healthyIds,
  loadCurrentCatalog,
  parseArgs,
  loadDeferralEntries,
};
