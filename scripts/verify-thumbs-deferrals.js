#!/usr/bin/env node
/**
 * Thumbnail deferral gate.
 *
 *   node scripts/verify-thumbs-deferrals.js [--expiry] [--base-ref=<gitref>]
 *
 * Push mode (default, every push/PR): schema, reasons, 30-day span, renewals and the
 * gpu-capture-pending ratchet. Rows that aged past `expires` only warn; with a base ref, a
 * past-dated row that is new or re-dated vs the base fails.
 * --expiry (scheduled job): also fails on any expired row, warns within 7 days, and prints
 * the next expiry date.
 *
 * THUMBS_DEFERRALS_NOW=YYYY-MM-DD overrides today. THUMBS_DEFERRALS_BASE_REF=<gitref> equals
 * --base-ref (the flag wins). Exit 0 = no errors, 1 = any error or bad usage.
 */
const { loadDeferralFile, loadRatchet, loadBaseDeferrals, checkDeferrals, today } = require('./lib/thumbnailDeferrals');

function parseArgs(argv, env = process.env) {
  const opts = { expiry: false, baseRef: env.THUMBS_DEFERRALS_BASE_REF || null };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--expiry') opts.expiry = true;
    else if (arg.startsWith('--base-ref=')) opts.baseRef = arg.slice('--base-ref='.length);
    else if (arg === '--base-ref' && argv[i + 1] && !argv[i + 1].startsWith('--')) opts.baseRef = argv[++i];
    else throw new Error(`unknown argument "${arg}" (usage: verify-thumbs-deferrals.js [--expiry] [--base-ref=<gitref>])`);
  }
  if (opts.baseRef === '') throw new Error('--base-ref needs a git ref');
  return opts;
}

function main() {
  let opts;
  let now;
  let baseEntries;
  try {
    opts = parseArgs(process.argv.slice(2));
    now = today();
    if (opts.baseRef) baseEntries = loadBaseDeferrals(opts.baseRef);
  } catch (err) {
    console.error(`❌ ${err.message}`);
    process.exit(1);
  }

  const entries = loadDeferralFile();
  const ratchet = loadRatchet();
  const expiryMode = opts.expiry ? 'enforce' : 'push';
  const { errors, warnings, nextExpiry } = checkDeferrals(entries, { now, ratchet, expiryMode, baseEntries });
  const pending = entries.filter(e => e.reason === 'gpu-capture-pending').length;

  const base = opts.baseRef ? `, base ${opts.baseRef}` : '';
  console.log(`Thumbnail deferrals: ${entries.length} (gpu-capture-pending ${pending}, ratchet ${ratchet.maxGpuCapturePending}, target ${ratchet.target ?? 'n/a'}; ${expiryMode} mode, today ${now}${base})`);
  for (const w of warnings) console.warn(`⚠ ${w}`);
  if (opts.expiry) console.log(nextExpiry ? `next expiry ${nextExpiry}` : 'next expiry: none (no unexpired deferrals)');
  if (errors.length) {
    const shown = errors.slice(0, 50);
    console.error(`❌ ${errors.length} deferral violation(s):\n  ` + shown.join('\n  ') + (errors.length > shown.length ? `\n  … +${errors.length - shown.length} more` : ''));
    process.exit(1);
  }
  console.log('✓ Thumbnail deferrals honest');
}

if (require.main === module) main();

module.exports = { parseArgs };
