#!/usr/bin/env node
/** Fails on expired/invalid thumbnail deferrals or a gpu-capture-pending count above the ratchet. */
const { loadDeferralFile, loadRatchet, validateDeferrals } = require('./lib/thumbnailDeferrals');

const entries = loadDeferralFile();
const ratchet = loadRatchet();
const errors = validateDeferrals(entries, { ratchet });
const pending = entries.filter(e => e.reason === 'gpu-capture-pending').length;

console.log(`Thumbnail deferrals: ${entries.length} (gpu-capture-pending ${pending}, ratchet ${ratchet.maxGpuCapturePending}, target ${ratchet.target ?? 'n/a'})`);
if (errors.length) {
  const shown = errors.slice(0, 20);
  console.error(`❌ ${errors.length} deferral violation(s):\n  ` + shown.join('\n  ') + (errors.length > shown.length ? `\n  … +${errors.length - shown.length} more` : ''));
  process.exit(1);
}
console.log('✓ Thumbnail deferrals honest');
