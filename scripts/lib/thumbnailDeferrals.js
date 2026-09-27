/**
 * Thumbnail deferral schema + gate. A deferral is a *temporary* skip; permanent
 * skips belong in reports/thumbnail_skip_allowlist.json.
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const DEFERRALS_PATH = path.join(ROOT, 'reports', 'thumbnail_deferrals.json');
const RATCHET_PATH = path.join(ROOT, 'reports', 'thumbnail_deferral_ratchet.json');

const REASONS = ['gpu-capture-pending', 'audio-only', 'interactive-no-still', 'known-magenta', 'other'];
const PERMANENT_REASONS = new Set(['audio-only', 'interactive-no-still']);
const MAX_DEFERRAL_DAYS = 30;
const MAX_RENEWALS_WITHOUT_NOTE = 1;
const EXPIRY_WARNING_DAYS = 7;
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

/**
 * Checks the deferral file. `errors` fail the gate; `warnings` (entries expiring within
 * EXPIRY_WARNING_DAYS) never do. An entry is valid through its `expires` day inclusive.
 */
function checkDeferrals(entries, { now = today(), ratchet = loadRatchet() } = {}) {
  const errors = [];
  const warnings = [];
  const expiringSoon = [];
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
    if (expires < now) errors.push(`${id}: expired ${expires} (today ${now}) — capture it or renew with a note`);
    else if (daysBetween(now, expires) <= EXPIRY_WARNING_DAYS) expiringSoon.push(expires);
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
  if (expiringSoon.length) {
    const earliest = expiringSoon.reduce((a, b) => (a < b ? a : b));
    warnings.push(`${expiringSoon.length} deferral(s) expire within ${EXPIRY_WARNING_DAYS} days (earliest ${earliest}, today ${now})`);
  }
  return { errors, warnings };
}

/** Errors only; empty array means the deferral file is honest. */
function validateDeferrals(entries, opts) {
  return checkDeferrals(entries, opts).errors;
}

module.exports = {
  REASONS, PERMANENT_REASONS, MAX_DEFERRAL_DAYS, MAX_RENEWALS_WITHOUT_NOTE, EXPIRY_WARNING_DAYS,
  DEFERRALS_PATH, RATCHET_PATH,
  today, isoDate, daysBetween, loadDeferralFile, loadRatchet, checkDeferrals, validateDeferrals,
};
