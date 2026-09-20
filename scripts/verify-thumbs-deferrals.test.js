#!/usr/bin/env node
/**
 * Test suite for verify-thumbs-deferrals.js (pure functions + CLI against a real file).
 */
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');
const { describe, it } = require('node:test');
const assert = require('node:assert');

const V = require('./verify-thumbs-deferrals.js');

const contract = V.loadContract();
const TODAY = '2026-09-19';

function pending(overrides = {}) {
  return {
    id: 'shader-a', reason: 'gpu-capture-pending', added_by: 'test',
    deferred_at: '2026-09-19', expires: '2026-10-19', renewals: 1, ...overrides,
  };
}
const check = (entries, extra = {}) => V.validateDeferrals({ entries }, { contract, today: TODAY, ...extra });
const problemsFor = (entry, extra) => check([entry], extra).problems;

describe('contract', () => {
  it('has the required enum, window, renewal allowance and ratchet', () => {
    assert.deepStrictEqual(contract.reasons,
      ['gpu-capture-pending', 'audio-only', 'interactive-no-still', 'known-magenta', 'other']);
    assert.strictEqual(contract.gpuCapturePending.maxWindowDays, 30);
    assert.strictEqual(contract.gpuCapturePending.maxRenewalsWithoutEvidence, 1);
    assert.ok(Number.isInteger(contract.pendingRatchet));
  });
});

describe('validateEntry', () => {
  it('accepts a well-formed pending entry', () => {
    assert.deepStrictEqual(problemsFor(pending()), []);
  });
  it('rejects the legacy spaced reason and suggests the enum value', () => {
    const p = problemsFor(pending({ reason: 'gpu-capture pending' }));
    assert.strictEqual(p.length, 1);
    assert.match(p[0], /use "gpu-capture-pending"/);
  });
  it('normalizeReason maps legacy spelling onto the enum', () => {
    assert.strictEqual(V.normalizeReason('gpu-capture pending', contract), 'gpu-capture-pending');
    assert.strictEqual(V.normalizeReason('other', contract), 'other');
  });
  it('rejects unknown reasons, unknown fields and missing fields', () => {
    assert.ok(problemsFor(pending({ reason: 'lazy' })).some(p => /unknown reason/.test(p)));
    assert.ok(problemsFor(pending({ extra: 1 })).some(p => /unknown field/.test(p)));
    const { expires, ...noExpires } = pending();
    assert.ok(problemsFor(noExpires).some(p => /missing required field "expires"/.test(p)));
  });
  it('rejects invalid dates, including impossible calendar days', () => {
    assert.ok(problemsFor(pending({ expires: '2026-02-30' })).some(p => /not a valid/.test(p)));
    assert.ok(problemsFor(pending({ deferred_at: 'yesterday' })).some(p => /not a valid/.test(p)));
  });
  it('rejects a window longer than 30 days but accepts exactly 30', () => {
    assert.ok(problemsFor(pending({ expires: '2026-10-20' })).some(p => /31 days/.test(p)));
    assert.deepStrictEqual(problemsFor(pending({ expires: '2026-10-19' })), []);
  });
  it('rejects expires <= deferred_at and future deferred_at', () => {
    assert.ok(problemsFor(pending({ expires: '2026-09-19' })).some(p => /after deferred_at/.test(p)));
    assert.ok(problemsFor(pending({ deferred_at: '2026-09-25', expires: '2026-10-05' })).some(p => /in the future/.test(p)));
  });
  it('rejects an expired pending entry, and accepts one expiring today', () => {
    const old = pending({ deferred_at: '2026-08-01', expires: '2026-08-31' });
    assert.ok(problemsFor(old).some(p => /expired on 2026-08-31/.test(p)));
    assert.deepStrictEqual(problemsFor(pending({ deferred_at: '2026-08-20', expires: '2026-09-19' })), []);
  });
  it('allows one renewal without evidence but not a second', () => {
    assert.deepStrictEqual(problemsFor(pending({ renewals: 1 })), []);
    assert.ok(problemsFor(pending({ renewals: 2 })).some(p => /capture_failure/.test(p)));
  });
  it('accepts a second renewal only with a capture_failure that cites a real attempt', () => {
    const url = 'run https://github.com/o/r/actions/runs/123 failed: no gpu adapter';
    assert.deepStrictEqual(problemsFor(pending({ renewals: 2, capture_failure: url })), []);
    assert.deepStrictEqual(problemsFor(pending({ renewals: 3, capture_failure: '2026-09-10 capture crashed at compile' })), []);
    assert.ok(problemsFor(pending({ renewals: 2, capture_failure: 'it did not work at all really' })).some(p => /run URL or an ISO date/.test(p)));
    assert.ok(problemsFor(pending({ renewals: 2, capture_failure: 'short' })).some(p => /at least 20/.test(p)));
  });
  it('requires a note for non-pending reasons', () => {
    assert.ok(problemsFor(pending({ reason: 'audio-only' })).some(p => /requires a non-empty note/.test(p)));
    assert.deepStrictEqual(problemsFor(pending({ reason: 'audio-only', note: 'silent without mic' })), []);
  });
});

describe('validateDeferrals', () => {
  it('rejects duplicates and skip-allowlisted ids', () => {
    assert.ok(check([pending(), pending()]).problems.some(p => /duplicate/.test(p)));
    assert.ok(check([pending()], { skipIds: new Set(['shader-a']) }).problems.some(p => /skip allowlist/.test(p)));
  });
  it('fails when pending count exceeds the ratchet', () => {
    const tight = { ...contract, pendingRatchet: 1 };
    const r = V.validateDeferrals({ entries: [pending(), pending({ id: 'shader-b' })] }, { contract: tight, today: TODAY });
    assert.ok(r.problems.some(p => /exceeds pendingRatchet 1/.test(p)));
  });
  it('does not count non-pending reasons against the ratchet', () => {
    const tight = { ...contract, pendingRatchet: 1 };
    const r = V.validateDeferrals(
      { entries: [pending(), pending({ id: 'shader-b', reason: 'other', note: 'x' })] },
      { contract: tight, today: TODAY },
    );
    assert.deepStrictEqual(r.problems, []);
    assert.strictEqual(r.pending, 1);
  });
  it('fails when the ratchet was raised above the base value', () => {
    const r = V.validateDeferrals({ entries: [] }, { contract: { ...contract, pendingRatchet: 10 }, today: TODAY, baseRatchet: 5 });
    assert.ok(r.problems.some(p => /may only decrease/.test(p)));
    const ok = V.validateDeferrals({ entries: [] }, { contract: { ...contract, pendingRatchet: 5 }, today: TODAY, baseRatchet: 10 });
    assert.deepStrictEqual(ok.problems, []);
  });
  it('rejects a malformed document', () => {
    assert.ok(V.validateDeferrals({}, { contract, today: TODAY }).problems[0].match(/"entries" array/));
  });
});

describe('orderEntry / date helpers', () => {
  it('orders keys per the contract', () => {
    const o = V.orderEntry({ expires: 'e', id: 'i', zzz: 1, reason: 'r', renewals: 1 }, contract);
    assert.deepStrictEqual(Object.keys(o), ['id', 'reason', 'expires', 'renewals', 'zzz']);
  });
  it('addDays/daysBetween agree', () => {
    assert.strictEqual(V.addDays('2026-09-19', 30), '2026-10-19');
    assert.strictEqual(V.daysBetween('2026-08-30', '2026-09-29'), 30);
  });
});

describe('CLI', () => {
  // Uses temp files only: check-thumbnail-coverage.test.js rewrites the real file concurrently.
  const script = path.join(__dirname, 'verify-thumbs-deferrals.js');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'deferrals-'));
  const file = path.join(dir, 'deferrals.json');
  const run = (entries, ...extra) => {
    fs.writeFileSync(file, JSON.stringify({ entries }));
    return spawnSync('node', [script, '--file', file, '--today', TODAY, ...extra], { encoding: 'utf8' });
  };

  it('exits 0 on a valid file', () => {
    const r = run([pending()]);
    assert.strictEqual(r.status, 0, r.stdout + r.stderr);
    assert.match(r.stdout, /Thumbnail deferrals valid/);
  });
  it('exits non-zero on a deliberately malformed entry', () => {
    const r = run([pending(), { id: 'zz-malformed-fixture', reason: 'because', deferred_at: '2026-09-19', expires: '2027-12-31', added_by: 'test' }]);
    assert.strictEqual(r.status, 1);
    assert.match(r.stderr, /zz-malformed-fixture: unknown reason/);
  });
  it('exits non-zero on an expired entry', () => {
    const r = run([pending({ deferred_at: '2026-08-01', expires: '2026-08-31' })]);
    assert.strictEqual(r.status, 1);
    assert.match(r.stderr, /expired on/);
  });
  it('exits non-zero when the pending count exceeds the ratchet', () => {
    const entries = Array.from({ length: contract.pendingRatchet + 1 }, (_, i) => pending({ id: `s-${i}` }));
    const r = run(entries);
    assert.strictEqual(r.status, 1);
    assert.match(r.stderr, /exceeds pendingRatchet/);
  });
});
