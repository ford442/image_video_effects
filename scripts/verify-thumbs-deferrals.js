#!/usr/bin/env node
/**
 * Gate for reports/thumbnail_deferrals.json. Schema and policy live in
 * src/contracts/thumbnail_deferrals.json. Exits non-zero on any violation.
 *
 *   node scripts/verify-thumbs-deferrals.js [--base-ref origin/main] [--today YYYY-MM-DD] [--file path]
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const CONTRACT_REL = 'src/contracts/thumbnail_deferrals.json';
const CONTRACT_PATH = path.join(ROOT, CONTRACT_REL);
const DEFERRALS_PATH = path.join(ROOT, 'reports', 'thumbnail_deferrals.json');
const SKIP_PATH = path.join(ROOT, 'reports', 'thumbnail_skip_allowlist.json');

const PENDING = 'gpu-capture-pending';
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function loadContract() {
  return readJson(CONTRACT_PATH);
}

function todayUtc() {
  return new Date().toISOString().slice(0, 10);
}

function parseDate(value) {
  if (typeof value !== 'string' || !DATE_RE.test(value)) return null;
  const ms = Date.parse(`${value}T00:00:00Z`);
  if (Number.isNaN(ms)) return null;
  return new Date(ms).toISOString().slice(0, 10) === value ? ms : null;
}

function daysBetween(from, to) {
  return Math.round((parseDate(to) - parseDate(from)) / 86400000);
}

function addDays(date, days) {
  return new Date(parseDate(date) + days * 86400000).toISOString().slice(0, 10);
}

/** Map the legacy "gpu-capture pending" spelling (or any alias) onto the enum. */
function normalizeReason(reason, contract) {
  return (contract.legacyReasonAliases || {})[reason] || reason;
}

/** Copy an entry with keys in contract order; unknown keys are kept last, sorted. */
function orderEntry(entry, contract) {
  const order = contract.entryFields.keyOrder;
  const out = {};
  for (const key of order) if (entry[key] !== undefined) out[key] = entry[key];
  for (const key of Object.keys(entry).filter(k => !order.includes(k)).sort()) out[key] = entry[key];
  return out;
}

function captureFailureProblem(text, contract) {
  const min = contract.gpuCapturePending.captureFailureMinLength;
  if (typeof text !== 'string' || text.trim().length < min) {
    return `capture_failure must be a string of at least ${min} characters`;
  }
  if (!/https?:\/\/\S+/.test(text) && !/\d{4}-\d{2}-\d{2}/.test(text)) {
    return 'capture_failure must reference a real attempt (a run URL or an ISO date)';
  }
  return null;
}

/** Returns a list of human-readable problems for one entry. */
function validateEntry(entry, contract, today) {
  const problems = [];
  const fields = contract.entryFields;
  const label = entry && typeof entry.id === 'string' ? entry.id : '<no id>';
  const bad = msg => problems.push(`${label}: ${msg}`);

  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) return [`${label}: entry is not an object`];

  for (const key of fields.required) {
    if (entry[key] === undefined || entry[key] === null || entry[key] === '') bad(`missing required field "${key}"`);
  }
  const known = new Set([...fields.required, ...fields.optional]);
  for (const key of Object.keys(entry)) if (!known.has(key)) bad(`unknown field "${key}"`);

  if (entry.id !== undefined && (typeof entry.id !== 'string' || !entry.id.trim())) bad('id must be a non-empty string');

  const reason = entry.reason;
  if (reason !== undefined && !contract.reasons.includes(reason)) {
    const alias = normalizeReason(reason, contract);
    bad(`unknown reason ${JSON.stringify(reason)}` + (alias !== reason ? ` (use "${alias}")` : ''));
  }

  const deferredMs = parseDate(entry.deferred_at);
  const expiresMs = parseDate(entry.expires);
  if (entry.deferred_at !== undefined && deferredMs === null) bad(`deferred_at ${JSON.stringify(entry.deferred_at)} is not a valid ${fields.dateFormat} date`);
  if (entry.expires !== undefined && expiresMs === null) bad(`expires ${JSON.stringify(entry.expires)} is not a valid ${fields.dateFormat} date`);
  if (entry.first_deferred_at !== undefined && parseDate(entry.first_deferred_at) === null) bad('first_deferred_at is not a valid date');

  const datesOk = deferredMs !== null && expiresMs !== null;
  if (datesOk) {
    if (entry.deferred_at > today) bad(`deferred_at ${entry.deferred_at} is in the future (today ${today})`);
    if (expiresMs <= deferredMs) bad('expires must be after deferred_at');
    if (entry.expires < today) bad(`expired on ${entry.expires} (today ${today})`);
  }

  if (entry.renewals !== undefined && !(Number.isInteger(entry.renewals) && entry.renewals >= 0)) {
    bad('renewals must be a non-negative integer');
  }

  if (reason === PENDING) {
    const cfg = contract.gpuCapturePending;
    if (datesOk && expiresMs > deferredMs) {
      const window = daysBetween(entry.deferred_at, entry.expires);
      if (window > cfg.maxWindowDays) bad(`window is ${window} days; ${PENDING} allows at most ${cfg.maxWindowDays}`);
    }
    const renewals = Number.isInteger(entry.renewals) ? entry.renewals : 0;
    if (renewals > cfg.maxRenewalsWithoutEvidence) {
      const problem = captureFailureProblem(entry.capture_failure, contract);
      if (problem) bad(`renewals=${renewals} exceeds the evidence-free allowance of ${cfg.maxRenewalsWithoutEvidence}; ${problem}`);
    }
  } else if (contract.entryFields.noteRequiredFor.includes(reason) && !(typeof entry.note === 'string' && entry.note.trim())) {
    bad(`reason "${reason}" requires a non-empty note`);
  }

  return problems;
}

/**
 * Validate a whole deferrals document.
 * opts: { contract, today, skipIds:Set, baseRatchet:number|null }
 * Returns { problems, pending, ratchet }.
 */
function validateDeferrals(data, opts) {
  const { contract, today = todayUtc(), skipIds = new Set(), baseRatchet = null } = opts;
  const problems = [];
  const entries = data && Array.isArray(data.entries) ? data.entries : null;
  if (!entries) return { problems: ['deferrals file must be an object with an "entries" array'], pending: 0, ratchet: contract.pendingRatchet };

  const seen = new Set();
  let pending = 0;
  for (const entry of entries) {
    problems.push(...validateEntry(entry, contract, today));
    if (entry && typeof entry.id === 'string') {
      if (seen.has(entry.id)) problems.push(`${entry.id}: duplicate entry`);
      seen.add(entry.id);
      if (skipIds.has(entry.id)) problems.push(`${entry.id}: is in the skip allowlist; permanent skips are not deferrals`);
    }
    if (entry && entry.reason === PENDING) pending++;
  }

  const ratchet = contract.pendingRatchet;
  if (!Number.isInteger(ratchet) || ratchet < 0) {
    problems.push('contract pendingRatchet must be a non-negative integer');
  } else {
    if (pending > ratchet) problems.push(`${PENDING} count ${pending} exceeds pendingRatchet ${ratchet}`);
    if (baseRatchet !== null && ratchet > baseRatchet) {
      problems.push(`pendingRatchet ${ratchet} was raised above the base branch value ${baseRatchet}; it may only decrease`);
    }
  }
  return { problems, pending, ratchet };
}

function loadSkipIds() {
  return fs.existsSync(SKIP_PATH) ? new Set((readJson(SKIP_PATH).ids || []).filter(Boolean)) : new Set();
}

function loadBaseRatchet(ref) {
  try {
    const text = execFileSync('git', ['show', `${ref}:${CONTRACT_REL}`], {
      cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    });
    const value = JSON.parse(text).pendingRatchet;
    return Number.isInteger(value) ? value : null;
  } catch {
    return null; // base has no contract yet (first PR) — nothing to compare against
  }
}

function argValue(argv, flag) {
  const i = argv.indexOf(flag);
  return i >= 0 ? argv[i + 1] : null;
}

function main() {
  const argv = process.argv.slice(2);
  const today = argValue(argv, '--today') || todayUtc();
  const baseRef = argValue(argv, '--base-ref');
  const contract = loadContract();
  const file = argValue(argv, '--file') || DEFERRALS_PATH;
  const data = fs.existsSync(file) ? readJson(file) : { entries: [] };
  const baseRatchet = baseRef ? loadBaseRatchet(baseRef) : null;

  const { problems, pending, ratchet } = validateDeferrals(data, { contract, today, skipIds: loadSkipIds(), baseRatchet });
  const total = (data.entries || []).length;
  console.log(`Thumbnail deferrals: ${total} entries, ${PENDING} pending=${pending}, ratchet=${ratchet}`);

  if (problems.length > 0) {
    const shown = problems.slice(0, 25);
    console.error(`❌ ${problems.length} deferral problem(s):`);
    for (const p of shown) console.error(`  - ${p}`);
    if (problems.length > shown.length) console.error(`  ... and ${problems.length - shown.length} more`);
    process.exitCode = 1;
    return;
  }
  if (pending < ratchet) {
    console.log(`Note: pending (${pending}) is below the ratchet (${ratchet}); lower it with defer-thumbnail.js --lower-ratchet.`);
  }
  console.log('✓ Thumbnail deferrals valid');
}

if (require.main === module) main();

module.exports = {
  PENDING,
  loadContract,
  parseDate,
  daysBetween,
  addDays,
  todayUtc,
  normalizeReason,
  orderEntry,
  captureFailureProblem,
  validateEntry,
  validateDeferrals,
  loadSkipIds,
  loadBaseRatchet,
  CONTRACT_PATH,
  DEFERRALS_PATH,
};
