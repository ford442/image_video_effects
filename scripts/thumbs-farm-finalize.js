#!/usr/bin/env node
/**
 * After a GPU capture wave: fail if any newly captured PNG is integrity-flagged,
 * then drop deferrals for now-healthy ids and lower the gpu-capture-pending ratchet.
 * Usage: node scripts/thumbs-farm-finalize.js --new=id1,id2,... [--dry-run]
 */
const fs = require('fs');
const path = require('path');
const { DEFERRALS_PATH, RATCHET_PATH } = require('./lib/thumbnailDeferrals');

const ROOT = path.join(__dirname, '..');
const arg = name => (process.argv.find(a => a.startsWith(`--${name}=`)) || '').split('=')[1];
const dry = process.argv.includes('--dry-run');

const newIds = new Set((arg('new') || '').split(',').map(s => s.trim()).filter(Boolean));
if (newIds.size === 0) {
  console.error('No new thumbnail ids given (--new=a,b,c); nothing captured.');
  process.exit(1);
}

const integrity = JSON.parse(fs.readFileSync(path.join(ROOT, 'reports', 'thumbnail_integrity_audit.json'), 'utf8'));
const badNew = (integrity.entries || []).filter(e => newIds.has(e.id));
if (badNew.length > 0) {
  console.error(`❌ ${badNew.length} captured thumbnail(s) failed integrity (near-black / magenta / unreadable) — not committing placeholders:`);
  for (const e of badNew) console.error(`  - ${e.id}: ${e.reason}`);
  process.exit(1);
}

const data = JSON.parse(fs.readFileSync(DEFERRALS_PATH, 'utf8'));
const before = data.entries.length;
data.entries = data.entries.filter(e => !newIds.has(e.id));
const pending = data.entries.filter(e => e.reason === 'gpu-capture-pending').length;
console.log(`Deferrals ${before} → ${data.entries.length}; gpu-capture-pending now ${pending}`);

if (!dry) {
  fs.writeFileSync(DEFERRALS_PATH, JSON.stringify(data, null, 2) + '\n');
  const ratchet = JSON.parse(fs.readFileSync(RATCHET_PATH, 'utf8'));
  ratchet.maxGpuCapturePending = Math.min(ratchet.maxGpuCapturePending, pending);
  fs.writeFileSync(RATCHET_PATH, JSON.stringify(ratchet, null, 2) + '\n');
}
console.log(`✓ ${newIds.size} captured thumbnail(s) integrity-clean`);
