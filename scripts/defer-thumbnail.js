#!/usr/bin/env node
/**
 * The only sanctioned writer for reports/thumbnail_deferrals.json.
 *
 *   add <id> --reason=<enum> [--days=N<=30]
 *   renew <id...> | --category=<name> | --ids-file=<path>  --note="<failure_note>"
 *   remove <id...> | --expired | --category=<name>
 *   reclassify <id> --reason=audio-only|interactive-no-still --why="..."
 *   ratchet [--to=N]            lower maxGpuCapturePending (default: current pending count)
 *
 * Every subcommand takes --dry-run (print the diff summary, write nothing).
 * --category=<name> reads public/shader-lists/<name>.json; --category=attract reuses the
 * thumbnail generator's --priority=attract list (loadAttractPriorityIds).
 * Deferrals never count as coverage and are never bulk-renewed silently: a second renewal
 * needs --note, expiry is always today+30, and the ratchet can only go down.
 */
const fs = require('fs');
const path = require('path');
const {
  REASONS, PERMANENT_REASONS, MAX_DEFERRAL_DAYS, MAX_RENEWALS_WITHOUT_NOTE,
  DEFERRALS_PATH, RATCHET_PATH, today, loadDeferralFile, loadRatchet,
} = require('./lib/thumbnailDeferrals');
const { loadAttractPriorityIds } = require('./generate-shader-thumbnails');

const ROOT = path.join(__dirname, '..');
const DEFAULT_PATHS = {
  deferrals: DEFERRALS_PATH,
  ratchet: RATCHET_PATH,
  allowlist: path.join(ROOT, 'reports', 'thumbnail_skip_allowlist.json'),
  listsDir: path.join(ROOT, 'public', 'shader-lists'),
};
const ADDED_BY = 'defer-thumbnail';
const ENTRY_KEY_ORDER = ['id', 'added_by', 'deferred_at', 'expires', 'reason', 'renewals', 'renewed_at', 'failure_note'];
const SUBCOMMANDS = ['add', 'renew', 'remove', 'reclassify', 'ratchet'];
const VALUE_FLAGS = new Set(['reason', 'days', 'note', 'why', 'category', 'ids-file', 'to']);
const BOOL_FLAGS = new Set(['dry-run', 'expired']);

class UsageError extends Error {}
const fail = msg => { throw new UsageError(msg); };

const byId = (a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
const addDays = (date, n) => new Date(Date.parse(date) + n * 86400000).toISOString().split('T')[0];
const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const writeJson = (file, data) => fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
const pendingCount = entries => entries.filter(e => e.reason === 'gpu-capture-pending').length;

function parseArgs(argv) {
  const [command, ...rest] = argv;
  if (!SUBCOMMANDS.includes(command)) fail(`usage: defer-thumbnail.js <${SUBCOMMANDS.join('|')}> ... (got "${command ?? ''}")`);
  const args = { command, ids: [], flags: {} };
  for (const token of rest) {
    if (!token.startsWith('--')) { args.ids.push(token); continue; }
    const [key, ...v] = token.slice(2).split('=');
    if (BOOL_FLAGS.has(key) && !v.length) args.flags[key] = true;
    else if (VALUE_FLAGS.has(key) && v.length) args.flags[key] = v.join('=');
    else fail(`unknown or malformed flag: ${token}`);
  }
  return args;
}

function canonicalEntry(entry) {
  const out = {};
  for (const k of ENTRY_KEY_ORDER) if (entry[k] !== undefined) out[k] = entry[k];
  for (const k of Object.keys(entry)) if (!(k in out)) out[k] = entry[k];
  return out;
}

function categoryIds(name, paths) {
  if (name === 'attract') return loadAttractPriorityIds();
  const file = path.join(paths.listsDir, `${name}.json`);
  if (!fs.existsSync(file)) fail(`no shader list for category "${name}" (expected ${file})`);
  return readJson(file).map(s => s.id);
}

function catalogIds(paths) {
  const ids = new Set();
  for (const f of fs.readdirSync(paths.listsDir).filter(n => n.endsWith('.json'))) {
    let list;
    try { list = readJson(path.join(paths.listsDir, f)); } catch { continue; }
    if (Array.isArray(list)) for (const s of list) if (s && s.id) ids.add(s.id);
  }
  return ids;
}

/** ids named on the command line, via --ids-file, or via --category; deduped, order preserved. */
function selectIds(args, paths, { allowExpired = false } = {}) {
  const sources = [];
  if (args.ids.length) sources.push(args.ids);
  if (args.flags['ids-file']) {
    sources.push(fs.readFileSync(args.flags['ids-file'], 'utf8').split('\n').map(l => l.trim()).filter(l => l && !l.startsWith('#')));
  }
  if (args.flags.category) sources.push({ category: args.flags.category });
  if (allowExpired && args.flags.expired) sources.push({ expired: true });
  if (sources.length === 0) fail(`${args.command}: give ids, --ids-file, --category${allowExpired ? ' or --expired' : ''}`);
  return sources;
}

function resolveTargets(args, paths, entries, now, opts) {
  const byKey = new Map(entries.map(e => [e.id, e]));
  const targets = new Set();
  const missing = [];
  for (const src of selectIds(args, paths, opts)) {
    if (Array.isArray(src)) {
      for (const id of src) (byKey.has(id) ? targets.add(id) : missing.push(id));
    } else if (src.category) {
      // A category selects only ids that are actually deferred; the rest are not our business.
      for (const id of categoryIds(src.category, paths)) if (byKey.has(id)) targets.add(id);
    } else if (src.expired) {
      for (const e of entries) if ((e.expires || e.until) < now) targets.add(e.id);
    }
  }
  if (missing.length) fail(`not currently deferred: ${missing.join(', ')}`);
  return [...targets];
}

function summarize(log, heading, ids, { dryRun }) {
  const shown = ids.slice(0, 10).join(', ') + (ids.length > 10 ? `, … +${ids.length - 10} more` : '');
  log(`${dryRun ? '[dry-run] would ' : ''}${heading}: ${ids.length}${ids.length ? ` (${shown})` : ''}`);
}

function checkRatchet(entries, ratchetFile) {
  const max = loadRatchet(ratchetFile).maxGpuCapturePending;
  const pending = pendingCount(entries);
  if (pending > max) fail(`refused: gpu-capture-pending would be ${pending}, above the ratchet ${max} (the ratchet only goes down)`);
}

function run(argv, ctx = {}) {
  const paths = { ...DEFAULT_PATHS, ...(ctx.paths || {}) };
  const log = ctx.log || console.log;
  const now = ctx.now || today();
  const args = parseArgs(argv);
  const dryRun = Boolean(args.flags['dry-run']);
  const entries = loadDeferralFile(paths.deferrals).map(canonicalEntry);
  const commit = next => {
    if (dryRun) return;
    writeJson(paths.deferrals, { entries: next.map(canonicalEntry).sort(byId) });
  };
  const result = { command: args.command, dryRun, changed: [] };

  if (args.command === 'add') {
    if (args.ids.length !== 1) fail('add: exactly one <id>');
    const [id] = args.ids;
    const reason = args.flags.reason;
    if (!REASONS.includes(reason)) fail(`add: --reason must be one of ${REASONS.join(', ')}`);
    if (PERMANENT_REASONS.has(reason)) fail(`add: "${reason}" is permanent — use reclassify (skip allowlist), not a deferral`);
    const days = args.flags.days === undefined ? MAX_DEFERRAL_DAYS : Number(args.flags.days);
    if (!Number.isInteger(days) || days < 1 || days > MAX_DEFERRAL_DAYS) fail(`add: --days must be an integer 1..${MAX_DEFERRAL_DAYS}`);
    if (entries.some(e => e.id === id)) fail(`add: ${id} is already deferred (use renew)`);
    if (!catalogIds(paths).has(id)) fail(`add: ${id} is not in public/shader-lists`);
    const next = [...entries, { id, added_by: ADDED_BY, deferred_at: now, expires: addDays(now, days), reason }];
    checkRatchet(next, paths.ratchet);
    summarize(log, `add (${reason}, ${days}d)`, [id], { dryRun });
    commit(next);
    result.changed = [id];
  } else if (args.command === 'renew') {
    const note = String(args.flags.note || '').trim();
    const targets = resolveTargets(args, paths, entries, now);
    const unnoted = entries.filter(e => targets.includes(e.id) && Number(e.renewals || 0) + 1 > MAX_RENEWALS_WITHOUT_NOTE);
    if (unnoted.length && !note) {
      fail(`renew: refused — ${unnoted.length} id(s) would exceed ${MAX_RENEWALS_WITHOUT_NOTE} renewal without --note="<failure_note>": ` +
        unnoted.slice(0, 10).map(e => e.id).join(', '));
    }
    const set = new Set(targets);
    const next = entries.map(e => {
      if (!set.has(e.id)) return e;
      const renewed = {
        ...e,
        deferred_at: now,
        expires: addDays(now, MAX_DEFERRAL_DAYS),
        renewals: Number(e.renewals || 0) + 1,
        renewed_at: now,
      };
      if (note) renewed.failure_note = note;
      return renewed;
    });
    summarize(log, `renew (expires ${addDays(now, MAX_DEFERRAL_DAYS)})`, targets, { dryRun });
    commit(next);
    result.changed = targets;
  } else if (args.command === 'remove') {
    const targets = resolveTargets(args, paths, entries, now, { allowExpired: true });
    const set = new Set(targets);
    summarize(log, 'remove', targets, { dryRun });
    commit(entries.filter(e => !set.has(e.id)));
    result.changed = targets;
  } else if (args.command === 'reclassify') {
    if (args.ids.length !== 1) fail('reclassify: exactly one <id>');
    const [id] = args.ids;
    const reason = args.flags.reason;
    if (!PERMANENT_REASONS.has(reason)) fail(`reclassify: --reason must be one of ${[...PERMANENT_REASONS].join(', ')}`);
    const why = String(args.flags.why || '').trim();
    if (!why) fail('reclassify: --why="<evidence>" is required');
    if (!entries.some(e => e.id === id)) fail(`reclassify: ${id} is not currently deferred`);
    const allowlist = fs.existsSync(paths.allowlist) ? readJson(paths.allowlist) : { ids: [], reasons: {} };
    const ids = [...new Set([...(allowlist.ids || []), id])].sort();
    const nextAllowlist = { ...allowlist, ids, reasons: { ...(allowlist.reasons || {}), [id]: `${reason}: ${why}` } };
    summarize(log, `reclassify → skip allowlist (${reason})`, [id], { dryRun });
    if (!dryRun) writeJson(paths.allowlist, nextAllowlist);
    commit(entries.filter(e => e.id !== id));
    result.changed = [id];
  } else if (args.command === 'ratchet') {
    const current = loadRatchet(paths.ratchet);
    const pending = pendingCount(entries);
    const to = args.flags.to === undefined ? pending : Number(args.flags.to);
    if (!Number.isInteger(to) || to < 0) fail('ratchet: --to must be a non-negative integer');
    if (to > current.maxGpuCapturePending) fail(`ratchet: refused — ${to} would raise maxGpuCapturePending from ${current.maxGpuCapturePending}`);
    if (to < pending) fail(`ratchet: refused — ${to} is below the current pending count ${pending}`);
    log(`${dryRun ? '[dry-run] would ' : ''}ratchet maxGpuCapturePending ${current.maxGpuCapturePending} → ${to}`);
    if (!dryRun) writeJson(paths.ratchet, { ...current, maxGpuCapturePending: to });
    result.changed = [String(to)];
  }
  return result;
}

if (require.main === module) {
  try {
    run(process.argv.slice(2));
  } catch (err) {
    if (!(err instanceof UsageError)) throw err;
    console.error(`❌ ${err.message}`);
    process.exit(1);
  }
}

module.exports = { run, parseArgs, UsageError, DEFAULT_PATHS };
