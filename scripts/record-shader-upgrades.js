#!/usr/bin/env node
'use strict';
/**
 * record-shader-upgrades.js — the upgrade ledger.
 *
 * Compares every shader's current source hash with the last hash recorded in
 * reports/shader-upgrade-ledger.json and appends a history entry for each one
 * that changed. Run it at the end of every upgrade batch, before committing:
 *
 *   npm run upgrades:record -- --note="2026-10-03 weekly batch (opus): idea cards in upgrade_batches/…"
 *
 * Flags:
 *   --note="…"     Free-text note stored on each new entry (model, batch file, idea summary)
 *   --ids=a,b      Only consider these ids (default: whole catalog)
 *   --event=NAME   upgraded (default) | fixed | hygiene — hygiene/fixed entries do not
 *                  count as upgrades in the app, but still mark thumbnails stale
 *   --dry-run      Print what would be recorded; write nothing
 *   --json         Print changed ids as JSON (for piping into thumbs:generate --ids=…)
 *
 * The first run (no ledger yet) records a baseline with no history.
 */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { ROOT, HASH_ALGORITHM, createHashContext, computeSourceHash } = require('./lib/shaderSourceHash');

const LEDGER_PATH = path.join(ROOT, 'reports', 'shader-upgrade-ledger.json');

function parseArgs(argv) {
  const out = { note: null, ids: null, event: 'upgraded', dryRun: false, json: false };
  for (const arg of argv) {
    const eq = arg.indexOf('=');
    const key = eq >= 0 ? arg.slice(2, eq) : arg.replace(/^--/, '');
    const val = eq >= 0 ? arg.slice(eq + 1) : 'true';
    if (key === 'note') out.note = val;
    else if (key === 'ids') out.ids = val.split(',').map(s => s.trim()).filter(Boolean);
    else if (key === 'event') out.event = val;
    else if (key === 'dry-run') out.dryRun = val !== 'false';
    else if (key === 'json') out.json = val !== 'false';
  }
  if (!['upgraded', 'fixed', 'hygiene'].includes(out.event)) {
    throw new Error(`--event must be upgraded, fixed or hygiene (got "${out.event}")`);
  }
  return out;
}

function headCommit() {
  try {
    return execSync('git rev-parse --short HEAD', { cwd: ROOT, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
  } catch {
    return null;
  }
}

function loadLedger() {
  if (!fs.existsSync(LEDGER_PATH)) return null;
  return JSON.parse(fs.readFileSync(LEDGER_PATH, 'utf8'));
}

/** Pure diff step (exported for tests). */
function diffLedger(ledger, currentHashes, { event, note, date, commit }) {
  const changed = [];
  const added = [];
  for (const [id, hash] of Object.entries(currentHashes)) {
    const rec = ledger.shaders[id];
    if (!rec) {
      ledger.shaders[id] = { hash, history: [{ event: 'added', date, hash, commit, note }] };
      added.push(id);
    } else if (rec.hash !== hash) {
      rec.history.push({ event, date, hash, prev_hash: rec.hash, commit, note });
      rec.hash = hash;
      changed.push(id);
    }
  }
  return { changed, added };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const ctx = createHashContext();
  const ids = args.ids || [...ctx.definitions.keys()];
  const current = {};
  for (const id of ids) {
    const h = computeSourceHash(id, ctx);
    if (h) current[id] = h;
  }

  let ledger = loadLedger();
  if (!ledger) {
    ledger = { version: 1, algorithm: HASH_ALGORITHM, created_at: new Date().toISOString(), shaders: {} };
    for (const [id, hash] of Object.entries(current)) ledger.shaders[id] = { hash, history: [] };
    if (!args.dryRun) {
      fs.mkdirSync(path.dirname(LEDGER_PATH), { recursive: true });
      fs.writeFileSync(LEDGER_PATH, JSON.stringify(ledger, null, 2) + '\n');
    }
    console.log(`[upgrades] Baseline ledger created for ${Object.keys(current).length} shaders. ` +
      'Future runs record changes against this baseline.');
    return;
  }
  if (ledger.algorithm !== HASH_ALGORITHM) {
    throw new Error(`Ledger hash algorithm "${ledger.algorithm}" ≠ "${HASH_ALGORITHM}". Re-baseline deliberately.`);
  }

  const { changed, added } = diffLedger(ledger, current, {
    event: args.event,
    note: args.note,
    date: new Date().toISOString(),
    commit: headCommit(),
  });

  if (args.json) {
    console.log(JSON.stringify({ changed, added }));
  } else {
    console.log(`[upgrades] ${changed.length} changed (${args.event}), ${added.length} new.`);
    for (const id of changed) console.log(`  ~ ${id}`);
    for (const id of added) console.log(`  + ${id}`);
    if (changed.length + added.length > 0) {
      console.log('\nRefresh their thumbnails: Shader Scanner → "Stale thumbnails only", or');
      console.log(`  npm run thumbs:generate -- --stale`);
    }
  }
  if (!args.dryRun && changed.length + added.length > 0) {
    fs.writeFileSync(LEDGER_PATH, JSON.stringify(ledger, null, 2) + '\n');
  }
}

if (require.main === module) {
  try {
    main();
  } catch (e) {
    console.error('[upgrades]', e.message || e);
    process.exit(1);
  }
}
module.exports = { parseArgs, diffLedger, LEDGER_PATH };
