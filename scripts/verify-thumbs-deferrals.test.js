#!/usr/bin/env node
/**
 * Tests for the push / --expiry split of the thumbnail deferral gate
 * (scripts/lib/thumbnailDeferrals.js checkDeferrals + scripts/verify-thumbs-deferrals.js).
 * Never touches the real reports/ files.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');
const { describe, it, before, after } = require('node:test');
const assert = require('node:assert');

const { checkDeferrals, loadBaseDeferrals } = require('./lib/thumbnailDeferrals');
const { parseArgs } = require('./verify-thumbs-deferrals');

const ratchet = { maxGpuCapturePending: 10, target: 200 };
const entry = (id, over = {}) => ({
  id, added_by: 'test', deferred_at: '2026-10-01', expires: '2026-10-26', reason: 'gpu-capture-pending', ...over,
});
const check = (entries, opts) => checkDeferrals(entries, { ratchet, ...opts });
const SCHEDULED = /expired — the scheduled expiry job owns this/;

describe('push mode (default)', () => {
  it('ignores a past date: no error, one "scheduled job owns this" warning', () => {
    const { errors, warnings, nextExpiry } = check([entry('a')], { now: '2026-10-27' });
    assert.deepStrictEqual(errors, []);
    assert.strictEqual(warnings.length, 1);
    assert.match(warnings[0], /^1 deferral\(s\) expired/);
    assert.match(warnings[0], SCHEDULED);
    assert.strictEqual(nextExpiry, null);
  });

  it('never emits the 7-day warning', () => {
    assert.deepStrictEqual(check([entry('a')], { now: '2026-10-24' }).warnings, []);
  });

  it('still fails schema, span, renewal, ratchet and duplicate checks', () => {
    const now = '2026-10-20';
    const one = (rows, re) => {
      const { errors } = check(rows, { now });
      assert.strictEqual(errors.filter(e => re.test(e)).length, 1, `${re} in ${JSON.stringify(errors)}`);
    };
    one([entry('a', { reason: 'audio-only' })], /permanent/);
    one([entry('a', { expires: '2026-11-01' })], /more than 30 days/);
    one([entry('a', { renewals: 2 })], /without a failure_note/);
    one(Array.from({ length: 11 }, (_, i) => entry(`x${i}`)), /count 11 exceeds ratchet 10/);
    one([entry('a'), entry('a')], /duplicate deferral/);
  });

  it('rejects an unknown mode', () => {
    assert.throws(() => check([entry('a')], { now: '2026-10-20', expiryMode: 'calendar' }), /expiryMode/);
  });
});

describe('enforce mode (--expiry)', () => {
  const enforce = (entries, now) => check(entries, { now, expiryMode: 'enforce' });

  it('fails the day after expiry', () => {
    const { errors } = enforce([entry('a')], '2026-10-27');
    assert.strictEqual(errors.length, 1);
    assert.match(errors[0], /expired 2026-10-26/);
  });

  it('allows the expiry day itself, with the 7-day warning', () => {
    const { errors, warnings } = enforce([entry('a')], '2026-10-26');
    assert.deepStrictEqual(errors, []);
    assert.strictEqual(warnings.length, 1);
    assert.match(warnings[0], /expire within 7 days/);
  });

  const later = [
    entry('p', { deferred_at: '2026-10-11', expires: '2026-11-10' }),
    entry('q', { deferred_at: '2026-10-16', expires: '2026-11-15' }),
  ];

  it('warns inside 7 days and names the earliest date', () => {
    const { errors, warnings, nextExpiry } = enforce(later, '2026-11-03');
    assert.deepStrictEqual(errors, []);
    assert.strictEqual(warnings.length, 1);
    assert.match(warnings[0], /2026-11-10/);
    assert.strictEqual(nextExpiry, '2026-11-10');
  });

  it('reports the next date outside the 7-day window without warning', () => {
    const { errors, warnings, nextExpiry } = enforce(later, '2026-10-27');
    assert.deepStrictEqual(errors, []);
    assert.deepStrictEqual(warnings, []);
    assert.strictEqual(nextExpiry, '2026-11-10');
  });

  it('nextExpiry skips expired rows and is null when nothing is valid', () => {
    assert.strictEqual(enforce([entry('a'), ...later], '2026-10-27').nextExpiry, '2026-11-10');
    assert.strictEqual(enforce([entry('a')], '2026-10-27').nextExpiry, null);
  });

  it('ignores baseEntries (the calendar decides)', () => {
    const { errors } = check([entry('a')], { now: '2026-10-27', expiryMode: 'enforce', baseEntries: [entry('a')] });
    assert.strictEqual(errors.length, 1);
  });
});

describe('introduced-expired rule (push mode with baseEntries)', () => {
  const now = '2026-10-27';

  it('fails a past date absent from the base', () => {
    const { errors } = check([entry('a', { deferred_at: '2026-09-15', expires: '2026-10-01' })], { now, baseEntries: [] });
    assert.strictEqual(errors.length, 1);
    assert.match(errors[0], /^a: expires 2026-10-01 is already past .* is new vs the base/);
  });

  it('grandfathers the same id with the same past date', () => {
    const { errors, warnings } = check([entry('a')], { now, baseEntries: [entry('a')] });
    assert.deepStrictEqual(errors, []);
    assert.match(warnings[0], SCHEDULED);
  });

  it('fails a row edited into the past', () => {
    const { errors } = check(
      [entry('a', { deferred_at: '2026-09-15', expires: '2026-10-01' })],
      { now, baseEntries: [entry('a', { deferred_at: '2026-10-11', expires: '2026-11-10' })] },
    );
    assert.strictEqual(errors.length, 1);
    assert.match(errors[0], /changed from 2026-11-10/);
  });

  it('passes a new future row', () => {
    assert.deepStrictEqual(check([entry('a', { deferred_at: '2026-10-11', expires: '2026-11-10' })], { now, baseEntries: [] }).errors, []);
  });

  it('skips the check when no base list is given', () => {
    assert.deepStrictEqual(check([entry('a', { expires: '2026-10-01', deferred_at: '2026-09-15' })], { now }).errors, []);
  });
});

describe('until is an alias of expires', () => {
  const row = entry('a', { expires: undefined, until: '2026-10-26' });
  const base = entry('a', { expires: undefined, until: '2026-10-26' });

  it('behaves like expires in both modes', () => {
    assert.deepStrictEqual(check([row], { now: '2026-10-27' }).errors, []);
    assert.deepStrictEqual(check([row], { now: '2026-10-27', baseEntries: [base] }).errors, []);
    assert.strictEqual(check([row], { now: '2026-10-27', baseEntries: [] }).errors.length, 1);
    assert.match(check([row], { now: '2026-10-27', expiryMode: 'enforce' }).errors[0], /expired 2026-10-26/);
    assert.deepStrictEqual(check([row], { now: '2026-10-26', expiryMode: 'enforce' }).errors, []);
  });

  it('matches a base row that used expires for the same date', () => {
    assert.deepStrictEqual(check([row], { now: '2026-10-27', baseEntries: [entry('a')] }).errors, []);
  });
});

describe('ratchet target', () => {
  it('is inert', () => {
    const rows = [entry('a', { deferred_at: '2026-10-11', expires: '2026-11-10' })];
    for (const expiryMode of ['push', 'enforce']) {
      const opts = { now: '2026-10-27', expiryMode };
      assert.deepStrictEqual(
        checkDeferrals(rows, { ...opts, ratchet: { maxGpuCapturePending: 10, target: 0 } }),
        checkDeferrals(rows, { ...opts, ratchet: { maxGpuCapturePending: 10, target: 200 } }),
      );
    }
  });
});

describe('loadBaseDeferrals', () => {
  let repo;
  let noFile;
  let withFile;
  const git = (...args) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...args], { cwd: repo, encoding: 'utf8' }).trim();

  before(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), 'deferral-base-'));
    git('init', '-q');
    fs.writeFileSync(path.join(repo, 'README'), 'x');
    git('add', '.');
    git('commit', '-q', '-m', 'no deferrals');
    noFile = git('rev-parse', 'HEAD');
    fs.mkdirSync(path.join(repo, 'reports'));
    fs.writeFileSync(path.join(repo, 'reports', 'thumbnail_deferrals.json'), JSON.stringify({ entries: [entry('a')] }));
    git('add', '.');
    git('commit', '-q', '-m', 'deferrals');
    withFile = git('rev-parse', 'HEAD');
  });
  after(() => fs.rmSync(repo, { recursive: true, force: true }));

  it('reads entries from the ref', () => {
    assert.deepStrictEqual(loadBaseDeferrals(withFile, repo).map(e => e.id), ['a']);
  });
  it('returns [] for a resolvable ref without the file', () => {
    assert.deepStrictEqual(loadBaseDeferrals(noFile, repo), []);
  });
  it('throws for an unresolvable ref', () => {
    assert.throws(() => loadBaseDeferrals('no-such-ref-xyz', repo), /does not resolve/);
  });
});

describe('verify-thumbs-deferrals CLI', () => {
  const script = path.join(__dirname, 'verify-thumbs-deferrals.js');
  const cli = (args, env = {}) => spawnSync(process.execPath, [script, ...args], {
    encoding: 'utf8',
    env: { ...process.env, THUMBS_DEFERRALS_NOW: '', THUMBS_DEFERRALS_BASE_REF: '', ...env },
  });

  it('parses --expiry and both --base-ref spellings; the flag beats the env var', () => {
    assert.deepStrictEqual(parseArgs([], {}), { expiry: false, baseRef: null });
    assert.deepStrictEqual(parseArgs(['--expiry', '--base-ref=origin/main'], {}), { expiry: true, baseRef: 'origin/main' });
    assert.deepStrictEqual(parseArgs(['--base-ref', 'abc123'], {}), { expiry: false, baseRef: 'abc123' });
    assert.strictEqual(parseArgs([], { THUMBS_DEFERRALS_BASE_REF: 'env-ref' }).baseRef, 'env-ref');
    assert.strictEqual(parseArgs(['--base-ref=flag-ref'], { THUMBS_DEFERRALS_BASE_REF: 'env-ref' }).baseRef, 'flag-ref');
    assert.throws(() => parseArgs(['--expiry=yes'], {}), /unknown argument/);
    assert.throws(() => parseArgs(['--base-ref='], {}), /needs a git ref/);
  });

  it('exits 1 on an unknown flag', () => {
    const r = cli(['--bogus']);
    assert.strictEqual(r.status, 1);
    assert.match(r.stderr, /unknown argument "--bogus"/);
  });

  it('exits 1 on a malformed THUMBS_DEFERRALS_NOW', () => {
    const r = cli([], { THUMBS_DEFERRALS_NOW: 'tomorrow' });
    assert.strictEqual(r.status, 1);
    assert.match(r.stderr, /YYYY-MM-DD/);
  });

  it('exits 1 on an unresolvable base ref (flag or env)', () => {
    assert.strictEqual(cli(['--base-ref=no-such-ref-xyz']).status, 1);
    const r = cli([], { THUMBS_DEFERRALS_BASE_REF: 'no-such-ref-xyz' });
    assert.strictEqual(r.status, 1);
    assert.match(r.stderr, /does not resolve/);
  });

  it('prints the next expiry line in --expiry mode', () => {
    const r = cli(['--expiry']);
    assert.match(r.stdout, /enforce mode/);
    assert.match(r.stdout, /next expiry/);
  });
});
