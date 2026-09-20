#!/usr/bin/env node
/**
 * The only supported way to add, renew, or remove a thumbnail deferral.
 * Writes schema-valid entries with computed dates and refuses to write anything
 * scripts/verify-thumbs-deferrals.js would reject.
 *
 *   node scripts/defer-thumbnail.js --id my-shader [--id other] [--ids-file list.txt]
 *        [--reason gpu-capture-pending] [--note "..."] [--capture-failure "run URL / date + what failed"]
 *   node scripts/defer-thumbnail.js --remove my-shader
 *   node scripts/defer-thumbnail.js --lower-ratchet
 * Flags: --dry-run, --today YYYY-MM-DD, --allow-unknown-id, --file/--contract-file (override paths, for tests)
 *
 * An id that already has an entry is renewed (renewals+1, fresh window from today).
 */

const fs = require('fs');
const path = require('path');
const V = require('./verify-thumbs-deferrals.js');

const ROOT = path.join(__dirname, '..');
const ADDED_BY = 'defer-thumbnail';

function sortEntries(entries, contract) {
  return entries.map(e => V.orderEntry(e, contract)).sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}

/**
 * Pure: compute the next entries list. Throws on refusals that are independent of the
 * final gate (unknown id, skip-listed id). The caller still runs validateDeferrals.
 */
function applyChanges({ entries, ids = [], remove = [], reason = V.PENDING, note, captureFailure, today, contract, catalog = null, skipIds = new Set(), addedBy = ADDED_BY }) {
  const normalized = V.normalizeReason(reason, contract);
  if (!contract.reasons.includes(normalized)) throw new Error(`unknown reason ${JSON.stringify(reason)}; expected one of ${contract.reasons.join(', ')}`);

  const byId = new Map(entries.map(e => [e.id, { ...e, reason: V.normalizeReason(e.reason, contract) }]));
  const actions = [];

  for (const id of remove) {
    if (!byId.delete(id)) throw new Error(`cannot remove ${id}: no such deferral`);
    actions.push({ id, action: 'removed' });
  }

  for (const id of ids) {
    if (skipIds.has(id)) throw new Error(`${id} is in the skip allowlist; permanent skips are not deferrals`);
    const prev = byId.get(id);
    if (!prev && catalog && !catalog.has(id)) throw new Error(`${id} is not in the shader catalog (pass --allow-unknown-id to override)`);
    const next = { id, reason: normalized, added_by: prev ? prev.added_by : addedBy, deferred_at: today };
    next.expires = V.addDays(today, contract.gpuCapturePending.maxWindowDays);
    if (note) next.note = note;
    if (prev) {
      next.first_deferred_at = prev.first_deferred_at || prev.deferred_at;
      next.renewals = (Number.isInteger(prev.renewals) ? prev.renewals : 0) + 1;
      if (prev.note && !note) next.note = prev.note;
      const evidence = captureFailure || prev.capture_failure;
      if (evidence) next.capture_failure = evidence;
      actions.push({ id, action: 'renewed', renewals: next.renewals });
    } else {
      next.renewals = 0;
      if (captureFailure) next.capture_failure = captureFailure;
      actions.push({ id, action: 'added' });
    }
    byId.set(id, next);
  }
  return { entries: sortEntries([...byId.values()], contract), actions };
}

function formatDocument(entries, contract) {
  return JSON.stringify({ contract: 'src/contracts/thumbnail_deferrals.json', entries: sortEntries(entries, contract) }, null, 2) + '\n';
}

function parseArgs(argv) {
  const out = { ids: [], remove: [], flags: new Set() };
  const takesValue = new Set(['--file', '--contract-file', '--reason', '--note', '--capture-failure', '--today', '--ids-file', '--id', '--remove']);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) throw new Error(`unexpected argument ${a}`);
    if (takesValue.has(a)) {
      const v = argv[++i];
      if (v === undefined) throw new Error(`${a} needs a value`);
      if (a === '--id') out.ids.push(...v.split(',').map(s => s.trim()).filter(Boolean));
      else if (a === '--remove') out.remove.push(...v.split(',').map(s => s.trim()).filter(Boolean));
      else if (a === '--ids-file') {
        out.ids.push(...fs.readFileSync(v, 'utf8').split('\n').map(s => s.trim()).filter(s => s && !s.startsWith('#')));
      } else out[a.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = v;
    } else out.flags.add(a);
  }
  return out;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const contractPath = args.contractFile || V.CONTRACT_PATH;
  const deferralsPath = args.file || V.DEFERRALS_PATH;
  const contract = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
  const today = args.today || V.todayUtc();
  const existing = fs.existsSync(deferralsPath) ? JSON.parse(fs.readFileSync(deferralsPath, 'utf8')).entries || [] : [];
  const skipIds = V.loadSkipIds();

  if (args.ids.length === 0 && args.remove.length === 0 && !args.flags.has('--lower-ratchet')) {
    throw new Error('nothing to do: pass --id/--ids-file, --remove, or --lower-ratchet');
  }
  const catalog = args.flags.has('--allow-unknown-id') ? null : require('./check-thumbnail-coverage.js').loadCurrentCatalog();

  const { entries, actions } = applyChanges({
    entries: existing, ids: args.ids, remove: args.remove, reason: args.reason || V.PENDING,
    note: args.note, captureFailure: args.captureFailure, today, contract, catalog, skipIds,
  });

  const nextContract = { ...contract };
  const pending = entries.filter(e => e.reason === V.PENDING).length;
  const lowerRatchet = args.flags.has('--lower-ratchet');
  if (lowerRatchet && pending < contract.pendingRatchet) nextContract.pendingRatchet = pending;

  const { problems } = V.validateDeferrals({ entries }, { contract: nextContract, today, skipIds });
  if (problems.length > 0) {
    console.error(`❌ Refusing to write: verify-thumbs-deferrals would reject the result (${problems.length} problem(s)):`);
    for (const p of problems.slice(0, 25)) console.error(`  - ${p}`);
    process.exitCode = 1;
    return;
  }

  const counts = actions.reduce((m, a) => ({ ...m, [a.action]: (m[a.action] || 0) + 1 }), {});
  console.log(`Deferrals: ${JSON.stringify(counts)}; pending=${pending}, ratchet=${nextContract.pendingRatchet}`);
  if (args.flags.has('--dry-run')) {
    console.log('(dry run — nothing written)');
    return;
  }
  fs.writeFileSync(deferralsPath, formatDocument(entries, contract));
  if (nextContract.pendingRatchet !== contract.pendingRatchet) {
    fs.writeFileSync(contractPath, JSON.stringify(nextContract, null, 2) + '\n');
    console.log(`Lowered pendingRatchet ${contract.pendingRatchet} -> ${nextContract.pendingRatchet}`);
  }
  console.log(`Wrote ${path.relative(ROOT, deferralsPath)}`);
}

if (require.main === module) {
  try {
    main();
  } catch (err) {
    console.error(`❌ ${err.message}`);
    process.exitCode = 1;
  }
}

module.exports = { applyChanges, formatDocument, sortEntries, parseArgs };
