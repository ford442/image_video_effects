/**
 * Thumbnail deferral schema + gate. A deferral is a *temporary* skip; permanent
 * skips belong in reports/thumbnail_skip_allowlist.json.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..', '..');
const DEFERRALS_PATH = path.join(ROOT, 'reports', 'thumbnail_deferrals.json');
const RATCHET_PATH = path.join(ROOT, 'reports', 'thumbnail_deferral_ratchet.json');

const REASONS = ['gpu-capture-pending', 'audio-only', 'interactive-no-still', 'known-magenta', 'other'];
const PERMANENT_REASONS = new Set(['audio-only', 'interactive-no-still']);
const MAX_DEFERRAL_DAYS = 30;
const MAX_RENEWALS_WITHOUT_NOTE = 1;
const EXPIRY_WARNING_DAYS = 7;
const EXPIRY_MODES = ['push', 'enforce'];
const DAY_MS = 86400000;

const isoDate = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(value));
const daysBetween = (from, to) => Math.round((Date.parse(to) - Date.parse(from)) / DAY_MS);

/**
 * "Today" for the gate. THUMBS_DEFERRALS_NOW=YYYY-MM-DD overrides it for tests and
 * reproductions (e.g. previewing the expiry cliff); CI never sets it.
 */
function today(env = process.env) {
  const override = env.THUMBS_DEFERRALS_NOW;
  if (override === undefined || override === '') return new Date().toISOString().split('T')[0];
  if (!isoDate(override)) throw new Error(`THUMBS_DEFERRALS_NOW must be YYYY-MM-DD, got "${override}"`);
  return override;
}

function loadDeferralFile(file = DEFERRALS_PATH) {
  return fs.existsSync(file) ? (JSON.parse(fs.readFileSync(file, 'utf8')).entries || []) : [];
}

function loadRatchet(file = RATCHET_PATH) {
  return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : { maxGpuCapturePending: Infinity };
}

/** `git show <ref>:reports/thumbnail_deferrals.json` entries; [] when the ref has no file; throws on a bad ref. */
function loadBaseDeferrals(ref, cwd = ROOT) {
  const git = args => execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 * 1024 * 1024 });
  try {
    git(['rev-parse', '--verify', '--quiet', `${ref}^{commit}`]);
  } catch {
    throw new Error(`base ref "${ref}" does not resolve to a commit`);
  }
  const file = path.relative(ROOT, DEFERRALS_PATH).split(path.sep).join('/');
  try {
    git(['cat-file', '-e', `${ref}:${file}`]);
  } catch {
    return [];
  }
  return JSON.parse(git(['show', `${ref}:${file}`])).entries || [];
}

/**
 * Checks the deferral file. `errors` fail the gate; `warnings` never do. An entry is valid
 * through its `expires` day inclusive.
 *
 * expiryMode 'push' (default, every push/PR): no calendar error. Rows that merely aged past
 * `expires` produce one warning — the scheduled job (`--expiry`) owns them. With `baseEntries`,
 * a past-dated row that is new or whose date changed vs the base is an error, so nobody can
 * commit a pre-expired entry.
 * expiryMode 'enforce' (`--expiry`, scheduled): past `expires` is an error, rows expiring
 * within EXPIRY_WARNING_DAYS warn, and `nextExpiry` names the earliest still-valid date.
 */
function checkDeferrals(entries, { now = today(), ratchet = loadRatchet(), expiryMode = 'push', baseEntries } = {}) {
  if (!EXPIRY_MODES.includes(expiryMode)) throw new Error(`expiryMode must be one of [${EXPIRY_MODES.join(', ')}], got "${expiryMode}"`);
  const enforce = expiryMode === 'enforce';
  const baseExpiry = baseEntries ? new Map(baseEntries.map(e => [e.id, e.expires || e.until])) : null;
  const errors = [];
  const warnings = [];
  const expiringSoon = [];
  const stillValid = [];
  let expiredCount = 0;
  const seen = new Set();
  let pending = 0;

  for (const e of entries) {
    const id = e.id || '<missing id>';
    const expires = e.expires || e.until;
    if (!e.id) errors.push('entry without id');
    else if (seen.has(e.id)) errors.push(`${id}: duplicate deferral`);
    seen.add(e.id);

    if (!REASONS.includes(e.reason)) {
      errors.push(`${id}: reason "${e.reason}" not in [${REASONS.join(', ')}]`);
    } else if (PERMANENT_REASONS.has(e.reason)) {
      errors.push(`${id}: "${e.reason}" is permanent — move it to thumbnail_skip_allowlist.json`);
    }
    if (e.reason === 'gpu-capture-pending') pending++;

    if (!isoDate(e.deferred_at) || !isoDate(expires)) {
      errors.push(`${id}: deferred_at and expires must be YYYY-MM-DD`);
      continue;
    }
    if (expires < now) {
      expiredCount++;
      if (enforce) {
        errors.push(`${id}: expired ${expires} (today ${now}) — capture it or renew with a note`);
      } else if (baseExpiry && baseExpiry.get(e.id) !== expires) {
        const was = baseExpiry.has(e.id) ? `changed from ${baseExpiry.get(e.id)}` : 'new';
        errors.push(`${id}: expires ${expires} is already past (today ${now}) and is ${was} vs the base — do not commit a pre-expired deferral`);
      }
    } else {
      stillValid.push(expires);
      if (enforce && daysBetween(now, expires) <= EXPIRY_WARNING_DAYS) expiringSoon.push(expires);
    }
    if (daysBetween(e.deferred_at, expires) > MAX_DEFERRAL_DAYS) {
      errors.push(`${id}: expires ${expires} is more than ${MAX_DEFERRAL_DAYS} days after deferred_at ${e.deferred_at}`);
    }
    const renewals = Number(e.renewals || 0);
    if (renewals > MAX_RENEWALS_WITHOUT_NOTE && !String(e.failure_note || '').trim()) {
      errors.push(`${id}: renewed ${renewals}x without a failure_note describing the captured failure`);
    }
  }

  if (pending > ratchet.maxGpuCapturePending) {
    errors.push(`gpu-capture-pending count ${pending} exceeds ratchet ${ratchet.maxGpuCapturePending}`);
  }
  const earliest = dates => dates.reduce((a, b) => (a < b ? a : b));
  if (expiringSoon.length) {
    warnings.push(`${expiringSoon.length} deferral(s) expire within ${EXPIRY_WARNING_DAYS} days (earliest ${earliest(expiringSoon)}, today ${now})`);
  }
  if (!enforce && expiredCount) {
    warnings.push(`${expiredCount} deferral(s) expired — the scheduled expiry job owns this; run verify:thumbs-deferrals --expiry`);
  }
  return { errors, warnings, nextExpiry: enforce && stillValid.length ? earliest(stillValid) : null };
}

/** Errors only; empty array means the deferral file is honest. */
function validateDeferrals(entries, opts) {
  return checkDeferrals(entries, opts).errors;
}

module.exports = {
  REASONS, PERMANENT_REASONS, MAX_DEFERRAL_DAYS, MAX_RENEWALS_WITHOUT_NOTE, EXPIRY_WARNING_DAYS, EXPIRY_MODES,
  DEFERRALS_PATH, RATCHET_PATH,
  today, isoDate, daysBetween, loadDeferralFile, loadRatchet, loadBaseDeferrals, checkDeferrals, validateDeferrals,
};
