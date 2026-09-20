#!/usr/bin/env node
/**
 * Test suite for defer-thumbnail.js (pure applyChanges; CLI runs against temp files only).
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { describe, it } = require('node:test');
const assert = require('node:assert');

const V = require('./verify-thumbs-deferrals.js');
const D = require('./defer-thumbnail.js');

const contract = V.loadContract();
const TODAY = '2026-09-19';
const base = { contract, today: TODAY, catalog: new Set(['a', 'b', 'c']), skipIds: new Set(['skipped']) };

describe('applyChanges', () => {
  it('adds a new entry with computed 30-day window and renewals 0', () => {
    const { entries, actions } = D.applyChanges({ ...base, entries: [], ids: ['a'] });
    assert.deepStrictEqual(actions, [{ id: 'a', action: 'added' }]);
    assert.deepStrictEqual(entries[0], {
      id: 'a', reason: 'gpu-capture-pending', added_by: 'defer-thumbnail',
      deferred_at: '2026-09-19', expires: '2026-10-19', renewals: 0,
    });
    assert.deepStrictEqual(V.validateDeferrals({ entries }, { contract, today: TODAY }).problems, []);
  });
  it('renews a legacy entry: normalizes reason, keeps first date, renewals 0 -> 1', () => {
    const legacy = { id: 'a', added_by: 'thumbnail-campaign', deferred_at: '2026-08-30', expires: '2026-09-29', reason: 'gpu-capture pending' };
    const { entries } = D.applyChanges({ ...base, entries: [legacy], ids: ['a'] });
    assert.strictEqual(entries[0].reason, 'gpu-capture-pending');
    assert.strictEqual(entries[0].first_deferred_at, '2026-08-30');
    assert.strictEqual(entries[0].renewals, 1);
    assert.strictEqual(entries[0].added_by, 'thumbnail-campaign');
  });
  it('produces deterministic output regardless of input order', () => {
    const a = D.applyChanges({ ...base, entries: [], ids: ['c', 'a', 'b'] }).entries;
    const b = D.applyChanges({ ...base, entries: [], ids: ['b', 'c', 'a'] }).entries;
    assert.strictEqual(D.formatDocument(a, contract), D.formatDocument(b, contract));
    assert.deepStrictEqual(a.map(e => e.id), ['a', 'b', 'c']);
    assert.deepStrictEqual(Object.keys(a[0]), ['id', 'reason', 'added_by', 'deferred_at', 'expires', 'renewals']);
  });
  it('second renewal is written but the gate then demands capture_failure', () => {
    const once = D.applyChanges({ ...base, entries: [], ids: ['a'] }).entries;
    const renewed1 = D.applyChanges({ ...base, entries: once, ids: ['a'] }).entries;
    const renewed2 = D.applyChanges({ ...base, entries: renewed1, ids: ['a'] }).entries;
    assert.strictEqual(renewed2[0].renewals, 2);
    assert.ok(V.validateDeferrals({ entries: renewed2 }, { contract, today: TODAY }).problems.some(p => /capture_failure/.test(p)));
    const withEvidence = D.applyChanges({ ...base, entries: renewed1, ids: ['a'], captureFailure: 'run https://example.com/runs/9 failed: no adapter' }).entries;
    assert.deepStrictEqual(V.validateDeferrals({ entries: withEvidence }, { contract, today: TODAY }).problems, []);
  });
  it('refuses unknown catalog ids for additions, skip-listed ids, and unknown reasons', () => {
    assert.throws(() => D.applyChanges({ ...base, entries: [], ids: ['nope'] }), /not in the shader catalog/);
    assert.throws(() => D.applyChanges({ ...base, entries: [], ids: ['skipped'] }), /skip allowlist/);
    assert.throws(() => D.applyChanges({ ...base, entries: [], ids: ['a'], reason: 'meh' }), /unknown reason/);
  });
  it('renewal of an entry not in the catalog is allowed (legacy cleanup path)', () => {
    const e = { id: 'gone', reason: 'gpu-capture-pending', added_by: 'x', deferred_at: '2026-09-01', expires: '2026-10-01', renewals: 0 };
    assert.doesNotThrow(() => D.applyChanges({ ...base, entries: [e], ids: ['gone'] }));
  });
  it('removes entries and errors on missing ones', () => {
    const { entries } = D.applyChanges({ ...base, entries: [], ids: ['a', 'b'] });
    assert.deepStrictEqual(D.applyChanges({ ...base, entries, remove: ['a'] }).entries.map(e => e.id), ['b']);
    assert.throws(() => D.applyChanges({ ...base, entries, remove: ['zzz'] }), /no such deferral/);
  });
});

describe('CLI', () => {
  const script = path.join(__dirname, 'defer-thumbnail.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'defer-'));
  const file = path.join(dir, 'deferrals.json');
  const contractFile = path.join(dir, 'contract.json');
  const run = (contractOverrides, entries, ...args) => {
    fs.writeFileSync(file, JSON.stringify({ entries }));
    fs.writeFileSync(contractFile, JSON.stringify({ ...contract, ...contractOverrides }));
    return spawnSync('node', [script, '--file', file, '--contract-file', contractFile, '--today', TODAY, '--allow-unknown-id', ...args], { encoding: 'utf8' });
  };

  it('writes a new entry when under the ratchet', () => {
    const r = run({ pendingRatchet: 1 }, [], '--id', 'zz-new');
    assert.strictEqual(r.status, 0, r.stderr);
    const written = JSON.parse(fs.readFileSync(file, 'utf8')).entries;
    assert.strictEqual(written[0].id, 'zz-new');
    assert.strictEqual(written[0].expires, '2026-10-19');
  });
  it('refuses, and writes nothing, when the ratchet would be exceeded', () => {
    const r = run({ pendingRatchet: 0 }, [], '--id', 'zz-new');
    assert.strictEqual(r.status, 1);
    assert.match(r.stderr, /Refusing to write/);
    assert.deepStrictEqual(JSON.parse(fs.readFileSync(file, 'utf8')).entries, []);
  });
  it('--dry-run writes nothing', () => {
    const r = run({ pendingRatchet: 1 }, [], '--id', 'zz-new', '--dry-run');
    assert.strictEqual(r.status, 0, r.stderr);
    assert.deepStrictEqual(JSON.parse(fs.readFileSync(file, 'utf8')).entries, []);
  });
  it('--lower-ratchet lowers the contract to the current pending count', () => {
    const e = { id: 'a', reason: 'gpu-capture-pending', added_by: 'x', deferred_at: TODAY, expires: '2026-10-19', renewals: 0 };
    const r = run({ pendingRatchet: 5 }, [e], '--lower-ratchet');
    assert.strictEqual(r.status, 0, r.stderr);
    assert.strictEqual(JSON.parse(fs.readFileSync(contractFile, 'utf8')).pendingRatchet, 1);
  });
  it('errors when there is nothing to do', () => {
    const r = spawnSync('node', [script], { encoding: 'utf8' });
    assert.strictEqual(r.status, 1);
    assert.match(r.stderr, /nothing to do/);
  });
});
