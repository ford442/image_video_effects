#!/usr/bin/env node
/**
 * Tests for scripts/defer-thumbnail.js and the deferral gate's date handling.
 * Everything runs against temp files, never the real reports/ files.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert');

const { run, UsageError } = require('./defer-thumbnail');
const { checkDeferrals, validateDeferrals, today } = require('./lib/thumbnailDeferrals');

const NOW = '2026-09-26';
const entry = (id, over = {}) => ({
  id, added_by: 'test', deferred_at: '2026-09-01', expires: '2026-09-30', reason: 'gpu-capture-pending', ...over,
});

describe('deferral gate dates', () => {
  const ratchet = { maxGpuCapturePending: 10 };

  it('passes when now == expires', () => {
    assert.deepStrictEqual(checkDeferrals([entry('a')], { now: '2026-09-30', ratchet }).errors, []);
  });

  it('fails when now == expires + 1', () => {
    const { errors } = checkDeferrals([entry('a')], { now: '2026-10-01', ratchet });
    assert.strictEqual(errors.length, 1);
    assert.match(errors[0], /expired 2026-09-30/);
  });

  it('warns (no error) when an entry expires within 7 days, naming count and earliest date', () => {
    const entries = [entry('a', { expires: '2026-10-03', deferred_at: '2026-09-10' }), entry('b', { expires: '2026-10-02', deferred_at: '2026-09-10' }), entry('c', { expires: '2026-10-30', deferred_at: '2026-10-01' })];
    const { errors, warnings } = checkDeferrals(entries, { now: '2026-09-26', ratchet });
    assert.deepStrictEqual(errors, []);
    assert.strictEqual(warnings.length, 1);
    assert.match(warnings[0], /^2 deferral\(s\) expire within 7 days \(earliest 2026-10-02/);
  });

  it('does not warn at 8 days out, and an expired entry is an error, not a warning', () => {
    assert.deepStrictEqual(checkDeferrals([entry('a', { expires: '2026-10-04', deferred_at: '2026-09-10' })], { now: '2026-09-26', ratchet }).warnings, []);
    const expired = checkDeferrals([entry('a')], { now: '2026-10-05', ratchet });
    assert.strictEqual(expired.errors.length, 1);
    assert.deepStrictEqual(expired.warnings, []);
  });

  it('validateDeferrals stays an errors-only array', () => {
    assert.deepStrictEqual(validateDeferrals([entry('a')], { now: '2026-09-30', ratchet }), []);
  });

  it('THUMBS_DEFERRALS_NOW overrides today and rejects malformed dates', () => {
    assert.strictEqual(today({ THUMBS_DEFERRALS_NOW: '2026-09-30' }), '2026-09-30');
    assert.match(today({}), /^\d{4}-\d{2}-\d{2}$/);
    assert.throws(() => today({ THUMBS_DEFERRALS_NOW: 'tomorrow' }), /YYYY-MM-DD/);
  });
});

describe('defer-thumbnail writer', () => {
  let dir;
  let paths;
  const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
  const ids = () => read(paths.deferrals).entries.map(e => e.id);
  const exec = (argv, extra = {}) => run(argv, { paths, now: NOW, log: () => {}, ...extra });

  const seed = (entries, ratchet = 10) => {
    fs.writeFileSync(paths.deferrals, JSON.stringify({ entries }, null, 2) + '\n');
    fs.writeFileSync(paths.ratchet, JSON.stringify({ description: 'r', maxGpuCapturePending: ratchet, target: 2 }, null, 2) + '\n');
  };

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), 'defer-thumb-'));
    paths = {
      deferrals: path.join(dir, 'deferrals.json'),
      ratchet: path.join(dir, 'ratchet.json'),
      allowlist: path.join(dir, 'allowlist.json'),
      listsDir: path.join(dir, 'lists'),
    };
    fs.mkdirSync(paths.listsDir);
    fs.writeFileSync(path.join(paths.listsDir, 'alpha.json'), JSON.stringify([{ id: 'a1' }, { id: 'a2' }, { id: 'a3' }]));
    fs.writeFileSync(path.join(paths.listsDir, 'beta.json'), JSON.stringify([{ id: 'b1' }, { id: 'b2' }]));
    fs.writeFileSync(paths.allowlist, JSON.stringify({ description: 'skips', ids: ['old'], reasons: { old: 'because' } }, null, 2) + '\n');
  });
  afterEach(() => fs.rmSync(dir, { recursive: true, force: true }));

  it('renew sets renewals/renewed_at/deferred_at/expires=today+30 and writes sorted, 2-space JSON with trailing newline', () => {
    seed([entry('b1'), entry('a1'), entry('a2')]);
    exec(['renew', '--category=alpha', '--note=no runner']);
    const text = fs.readFileSync(paths.deferrals, 'utf8');
    assert.ok(text.endsWith('}\n'));
    assert.ok(text.includes('\n    {\n      "id"'));
    const entries = read(paths.deferrals).entries;
    assert.deepStrictEqual(entries.map(e => e.id), ['a1', 'a2', 'b1']);
    assert.deepStrictEqual(
      { ...entries[0] },
      entry('a1', { deferred_at: NOW, expires: '2026-10-26', renewals: 1, renewed_at: NOW, failure_note: 'no runner' }),
    );
    assert.strictEqual(entries[2].renewals, undefined, 'ids outside the category are untouched');
    assert.deepStrictEqual(validateDeferrals(entries, { now: NOW, ratchet: { maxGpuCapturePending: 10 } }), []);
  });

  it('renew accepts ids and --ids-file, and refuses ids that are not deferred', () => {
    seed([entry('a1'), entry('a2'), entry('b1')]);
    const file = path.join(dir, 'ids.txt');
    fs.writeFileSync(file, '# comment\na2\n\n');
    exec(['renew', 'a1', `--ids-file=${file}`]);
    assert.deepStrictEqual(read(paths.deferrals).entries.filter(e => e.renewals).map(e => e.id), ['a1', 'a2']);
    assert.throws(() => exec(['renew', 'ghost']), UsageError);
  });

  it('renew without --note is refused once renewals would exceed 1, and nothing is written', () => {
    seed([entry('a1', { renewals: 1, renewed_at: '2026-09-10', failure_note: 'first' }), entry('a2')]);
    const before = fs.readFileSync(paths.deferrals, 'utf8');
    assert.throws(() => exec(['renew', 'a1', 'a2']), /without --note/);
    assert.strictEqual(fs.readFileSync(paths.deferrals, 'utf8'), before);
    exec(['renew', 'a1', 'a2', '--note=magenta on run 3']);
    const a1 = read(paths.deferrals).entries.find(e => e.id === 'a1');
    assert.strictEqual(a1.renewals, 2);
    assert.strictEqual(a1.failure_note, 'magenta on run 3');
  });

  it('the first renewal does not need a note', () => {
    seed([entry('a1')]);
    exec(['renew', 'a1']);
    assert.strictEqual(read(paths.deferrals).entries[0].renewals, 1);
  });

  it('reclassify moves the id to the skip allowlist (ids + reasons) and drops the deferral', () => {
    seed([entry('a1'), entry('a2')]);
    exec(['reclassify', 'a1', '--reason=audio-only', '--why=reads only plasmaBuffer, black without audio']);
    assert.deepStrictEqual(ids(), ['a2']);
    const allow = read(paths.allowlist);
    assert.deepStrictEqual(allow.ids, ['a1', 'old']);
    assert.strictEqual(allow.reasons.a1, 'audio-only: reads only plasmaBuffer, black without audio');
    assert.strictEqual(allow.reasons.old, 'because');
    assert.strictEqual(allow.description, 'skips');
  });

  it('reclassify requires a permanent reason, evidence, and an existing deferral', () => {
    seed([entry('a1')]);
    assert.throws(() => exec(['reclassify', 'a1', '--reason=other', '--why=x']), UsageError);
    assert.throws(() => exec(['reclassify', 'a1', '--reason=audio-only']), /--why/);
    assert.throws(() => exec(['reclassify', 'zzz', '--reason=audio-only', '--why=x']), /not currently deferred/);
    assert.deepStrictEqual(ids(), ['a1']);
  });

  it('remove --expired drops only entries past their expiry', () => {
    seed([entry('a1', { expires: '2026-09-25' }), entry('a2', { expires: '2026-09-26' }), entry('a3', { expires: '2026-09-27' })]);
    exec(['remove', '--expired']);
    assert.deepStrictEqual(ids(), ['a2', 'a3']);
  });

  it('remove --category and remove <id> work', () => {
    seed([entry('a1'), entry('a2'), entry('b1'), entry('b2')]);
    exec(['remove', '--category=alpha']);
    exec(['remove', 'b2']);
    assert.deepStrictEqual(ids(), ['b1']);
  });

  it('the ratchet cannot be raised by the writer', () => {
    seed([entry('a1'), entry('a2')], 5);
    assert.throws(() => exec(['ratchet', '--to=6']), /raise/);
    assert.strictEqual(read(paths.ratchet).maxGpuCapturePending, 5);
    exec(['ratchet']);
    assert.strictEqual(read(paths.ratchet).maxGpuCapturePending, 2);
    assert.strictEqual(read(paths.ratchet).target, 2, 'other ratchet fields are preserved');
    assert.throws(() => exec(['ratchet', '--to=1']), /below the current pending count/);
  });

  it('add cannot push gpu-capture-pending above the ratchet', () => {
    seed([entry('a1')], 1);
    assert.throws(() => exec(['add', 'a2', '--reason=gpu-capture-pending']), /above the ratchet/);
    assert.deepStrictEqual(ids(), ['a1']);
  });

  it('add validates reason, days, catalog membership and duplicates', () => {
    seed([entry('a1')]);
    exec(['add', 'a2', '--reason=other', '--days=7']);
    const added = read(paths.deferrals).entries.find(e => e.id === 'a2');
    assert.strictEqual(added.expires, '2026-10-03');
    assert.strictEqual(added.deferred_at, NOW);
    assert.throws(() => exec(['add', 'a3', '--reason=audio-only']), /reclassify/);
    assert.throws(() => exec(['add', 'a3', '--reason=other', '--days=31']), /--days/);
    assert.throws(() => exec(['add', 'nope', '--reason=other']), /not in public\/shader-lists/);
    assert.throws(() => exec(['add', 'a1', '--reason=other']), /already deferred/);
  });

  it('--dry-run writes nothing for every subcommand', () => {
    seed([entry('a1', { expires: '2026-09-01', deferred_at: '2026-08-01' }), entry('a2')]);
    const snapshot = () => [paths.deferrals, paths.ratchet, paths.allowlist].map(f => fs.readFileSync(f, 'utf8'));
    const before = snapshot();
    const lines = [];
    const argvs = [
      ['add', 'a3', '--reason=other'],
      ['renew', '--category=alpha', '--note=n'],
      ['remove', '--expired'],
      ['reclassify', 'a2', '--reason=interactive-no-still', '--why=needs mouse'],
      ['ratchet', '--to=2'],
    ];
    for (const argv of argvs) exec([...argv, '--dry-run'], { log: l => lines.push(l) });
    assert.deepStrictEqual(snapshot(), before);
    assert.strictEqual(lines.length, argvs.length);
    assert.ok(lines.every(l => l.startsWith('[dry-run] would ')));
  });

  it('rejects unknown subcommands and flags', () => {
    seed([entry('a1')]);
    assert.throws(() => exec(['bulk-renew']), UsageError);
    assert.throws(() => exec(['renew', 'a1', '--bogus=1']), /unknown or malformed flag/);
  });
});
