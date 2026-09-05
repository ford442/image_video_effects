#!/usr/bin/env node
/**
 * Fail a pull request when newly eligible shaders lack a healthy thumbnail
 * and have no unexpired deferral. Does not gate on global coverage %.
 */

const crypto = require('crypto');
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
const COVERAGE_MD_PATH = path.join(ROOT, 'reports', 'thumbnail_coverage.md');

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

function loadBaseIntegrityFlags(ref) {
  const integrity = readGitJson(ref, 'reports/thumbnail_integrity_audit.json');
  return new Set((integrity?.entries || []).map(e => e.id));
}

function isIntegrityCurrent(integrity, pngFiles) {
  if (!integrity) return false;
  return integrity.scanned === pngFiles.length &&
    integrity.png_fingerprint === thumbnailFingerprint(pngFiles);
}

function loadCurrentIntegrityFlags() {
  if (!fs.existsSync(INTEGRITY_PATH)) {
    return { flagged: new Set(), stale: false };
  }
  const integrity = JSON.parse(fs.readFileSync(INTEGRITY_PATH, 'utf8'));
  const pngFiles = fs.readdirSync(THUMB_DIR).filter(file => file.endsWith('.png')).sort();
  if (!isIntegrityCurrent(integrity, pngFiles)) {
    return { flagged: new Set(), stale: true };
  }
  return { flagged: new Set((integrity.entries || []).map(e => e.id)), stale: false };
}

function deferralExpiry(entry) {
  return entry.expires || entry.until || null;
}

function loadDeferralEntries() {
  if (!fs.existsSync(DEFERRALS_PATH)) {
    return { valid: new Set(), all: [] };
  }
  const data = JSON.parse(fs.readFileSync(DEFERRALS_PATH, 'utf8'));
  const entries = data.entries || [];

  const today = new Date().toISOString().split('T')[0];
  const valid = new Set();

  for (const entry of entries) {
    if (!entry.id) continue;
    const expires = deferralExpiry(entry);
    if (!expires) continue;
    if (expires >= today) {
      valid.add(entry.id);
    }
  }

  return { valid, all: entries };
}

function healthyIds(catalog, pngs, manifest, flaggedIds) {
  return new Set([...catalog].filter(id => pngs.has(id) && Boolean(manifest[id]) && !flaggedIds.has(id)));
}

function evaluateNewlyEligible(newlyEligible, currentHealthy, validDeferrals) {
  const offending = [];
  for (const id of newlyEligible) {
    if (!currentHealthy.has(id) && !validDeferrals.has(id)) {
      offending.push(id);
    }
  }
  return offending.sort();
}

function writeCoverageMarkdown(report) {
  const lines = [
    '# Thumbnail coverage',
    '',
    `- Catalog: **${report.catalog}**`,
    `- Skip allowlist: **${report.skip}**`,
    `- Eligible: **${report.eligible}**`,
    `- Healthy: **${report.healthy}** (${report.healthyPct}%)`,
    `- Unexpired deferrals: **${report.deferred}**`,
    `- Missing (no healthy PNG, no deferral): **${report.missing}**`,
    `- Newly eligible: **${report.newlyEligible}**`,
    `- Newly eligible without thumb or deferral: **${report.offending.length}**`,
    '',
  ];
  if (report.integrityStale) {
    lines.push('Integrity audit is stale for the current PNG set; flags were not applied.');
    lines.push('');
  }
  if (report.offending.length > 0) {
    lines.push('## Newly eligible missing');
    lines.push('');
    for (const id of report.offending) lines.push(`- \`${id}\``);
    lines.push('');
  }
  fs.mkdirSync(path.dirname(COVERAGE_MD_PATH), { recursive: true });
  fs.writeFileSync(COVERAGE_MD_PATH, lines.join('\n'));
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

  const skipIds = loadThumbnailSkipIds();
  const currentCatalog = loadCurrentCatalog();
  const currentEligible = new Set([...currentCatalog].filter(id => !skipIds.has(id)));
  const baseEligible = new Set([...baseCatalog].filter(id => !skipIds.has(id)));

  const { flagged: currentIntegrity, stale: integrityStale } = loadCurrentIntegrityFlags();
  const baseIntegrity = loadBaseIntegrityFlags(baseRef);
  const deferrals = loadDeferralEntries();

  const currentPngs = loadCurrentPngs();
  const basePngs = loadBasePngs(baseRef);
  const baseHealthy = healthyIds(baseEligible, basePngs, loadBaseThumbManifest(baseRef), baseIntegrity);
  const currentHealthy = healthyIds(currentEligible, currentPngs, loadCurrentThumbManifest(), currentIntegrity);

  const basePct = (baseHealthy.size / baseCatalog.size) * 100;
  const currentPct = (currentHealthy.size / currentCatalog.size) * 100;
  const eligiblePct = currentEligible.size
    ? ((currentHealthy.size / currentEligible.size) * 100).toFixed(1)
    : '0.0';

  const newlyEligible = new Set([...currentEligible].filter(id => !baseEligible.has(id)));
  const missing = [...currentEligible].filter(id => !currentHealthy.has(id) && !deferrals.valid.has(id)).sort();

  if (integrityStale) {
    console.warn(
      'Integrity audit is stale for the current PNG files; flags were ignored. ' +
      'Run python3 scripts/audit_thumbnail_integrity.py',
    );
  }

  console.log(
    `Thumbnail PR baseline: ${baseHealthy.size}/${baseCatalog.size} (${basePct.toFixed(1)}%)`,
  );
  console.log(
    `Thumbnail PR head: ${currentHealthy.size}/${currentCatalog.size} (${currentPct.toFixed(1)}%)`,
  );
  console.log(
    `Healthy eligible: ${currentHealthy.size}/${currentEligible.size} (${eligiblePct}%)`,
  );
  console.log(`Unexpired deferrals: ${deferrals.valid.size}`);
  console.log(`Missing (no healthy, no deferral): ${missing.length}`);

  let exitCode = 0;

  const offendingIds = evaluateNewlyEligible(newlyEligible, currentHealthy, deferrals.valid);

  if (newlyEligible.size > 0) {
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

  const deletedPngs = new Set([...basePngs].filter(id => !currentPngs.has(id) && baseHealthy.has(id)));

  if (deletedPngs.size > 0) {
    console.error(
      `❌ Thumbnails deleted for healthy shaders (${deletedPngs.size}): ` +
      [...deletedPngs].join(', '),
    );
    exitCode = 1;
  }

  writeCoverageMarkdown({
    catalog: currentCatalog.size,
    skip: skipIds.size,
    eligible: currentEligible.size,
    healthy: currentHealthy.size,
    healthyPct: eligiblePct,
    deferred: deferrals.valid.size,
    missing: missing.length,
    newlyEligible: newlyEligible.size,
    offending: offendingIds,
    integrityStale,
  });
  console.log(`Wrote ${path.relative(ROOT, COVERAGE_MD_PATH)}`);

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
  evaluateNewlyEligible,
  deferralExpiry,
  isIntegrityCurrent,
};
