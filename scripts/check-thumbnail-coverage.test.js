#!/usr/bin/env node
/**
 * Test suite for check-thumbnail-coverage.js
 */

const fs = require('fs');
const path = require('path');
const { describe, it } = require('node:test');
const assert = require('node:assert');

const ROOT = path.join(__dirname, '..');
const DEFERRAL_PATH = path.join(ROOT, 'reports', 'thumbnail_deferrals.json');

const module_ = require('./check-thumbnail-coverage.js');
const {
  healthyIds,
  loadCurrentCatalog,
  loadDeferralEntries,
  evaluateNewlyEligible,
  deferralExpiry,
} = module_;

function withDeferrals(entries, fn) {
  const backup = fs.existsSync(DEFERRAL_PATH) ? fs.readFileSync(DEFERRAL_PATH, 'utf8') : null;
  fs.writeFileSync(DEFERRAL_PATH, JSON.stringify({ entries }, null, 2));
  try {
    return fn();
  } finally {
    if (backup !== null) fs.writeFileSync(DEFERRAL_PATH, backup);
    else fs.unlinkSync(DEFERRAL_PATH);
  }
}

describe('Thumbnail Coverage Check', () => {
  describe('healthyIds', () => {
    it('should return IDs that have PNG, manifest entry, and are not flagged', () => {
      const catalog = new Set(['id1', 'id2', 'id3']);
      const pngs = new Set(['id1', 'id2']);
      const manifest = { id1: { thumb: true }, id2: { thumb: true } };
      const flagged = new Set(['id2']);

      const result = healthyIds(catalog, pngs, manifest, flagged);

      assert.strictEqual(result.size, 1);
      assert.ok(result.has('id1'));
      assert.ok(!result.has('id2'));
      assert.ok(!result.has('id3'));
    });

    it('should exclude IDs without PNG files', () => {
      const catalog = new Set(['id1', 'id2']);
      const pngs = new Set(['id1']);
      const manifest = { id1: { thumb: true }, id2: { thumb: true } };
      const flagged = new Set();

      const result = healthyIds(catalog, pngs, manifest, flagged);

      assert.strictEqual(result.size, 1);
      assert.ok(result.has('id1'));
    });

    it('should exclude IDs without manifest entries', () => {
      const catalog = new Set(['id1', 'id2']);
      const pngs = new Set(['id1', 'id2']);
      const manifest = { id1: { thumb: true } };
      const flagged = new Set();

      const result = healthyIds(catalog, pngs, manifest, flagged);

      assert.strictEqual(result.size, 1);
      assert.ok(result.has('id1'));
    });

    it('should exclude flagged IDs', () => {
      const catalog = new Set(['id1', 'id2']);
      const pngs = new Set(['id1', 'id2']);
      const manifest = { id1: { thumb: true }, id2: { thumb: true } };
      const flagged = new Set(['id1']);

      const result = healthyIds(catalog, pngs, manifest, flagged);

      assert.strictEqual(result.size, 1);
      assert.ok(!result.has('id1'));
      assert.ok(result.has('id2'));
    });
  });

  describe('evaluateNewlyEligible', () => {
    it('passes when newly eligible has a healthy thumb', () => {
      const offending = evaluateNewlyEligible(
        new Set(['new-a']),
        new Set(['new-a']),
        new Set(),
      );
      assert.deepStrictEqual(offending, []);
    });

    it('passes when newly eligible has an unexpired deferral', () => {
      const offending = evaluateNewlyEligible(
        new Set(['new-a']),
        new Set(),
        new Set(['new-a']),
      );
      assert.deepStrictEqual(offending, []);
    });

    it('fails when newly eligible has neither thumb nor deferral', () => {
      const offending = evaluateNewlyEligible(
        new Set(['new-a', 'new-b']),
        new Set(['new-a']),
        new Set(),
      );
      assert.deepStrictEqual(offending, ['new-b']);
    });

    it('does not fail on global healthy-count drop', () => {
      const offending = evaluateNewlyEligible(new Set(), new Set(['a']), new Set());
      assert.deepStrictEqual(offending, []);
    });
  });

  describe('loadDeferralEntries', () => {
    it('should load valid, non-expired deferral entries', () => {
      const futureDate = new Date();
      futureDate.setDate(futureDate.getDate() + 15);
      const futureStr = futureDate.toISOString().split('T')[0];

      withDeferrals([{
        id: 'test-shader-1',
        added_by: 'test',
        pr: 9999,
        deferred_at: new Date().toISOString().split('T')[0],
        expires: futureStr,
        reason: 'test deferral',
      }], () => {
        const deferrals = loadDeferralEntries();
        assert.ok(deferrals.valid.has('test-shader-1'));
      });
    });

    it('honors until as an alias of expires', () => {
      const futureDate = new Date();
      futureDate.setDate(futureDate.getDate() + 10);
      const futureStr = futureDate.toISOString().split('T')[0];

      withDeferrals([{
        id: 'until-shader',
        until: futureStr,
        reason: 'gpu-capture pending',
      }], () => {
        assert.strictEqual(deferralExpiry({ until: futureStr }), futureStr);
        const deferrals = loadDeferralEntries();
        assert.ok(deferrals.valid.has('until-shader'));
      });
    });

    it('should exclude expired deferral entries', () => {
      const pastDate = new Date();
      pastDate.setDate(pastDate.getDate() - 5);
      const pastStr = pastDate.toISOString().split('T')[0];

      withDeferrals([{
        id: 'expired-shader',
        added_by: 'test',
        pr: 9999,
        deferred_at: '2026-01-01',
        expires: pastStr,
        reason: 'expired deferral',
      }], () => {
        const deferrals = loadDeferralEntries();
        assert.ok(!deferrals.valid.has('expired-shader'));
        const offending = evaluateNewlyEligible(
          new Set(['expired-shader']),
          new Set(),
          deferrals.valid,
        );
        assert.deepStrictEqual(offending, ['expired-shader']);
      });
    });
  });

  describe('loadCurrentCatalog', () => {
    it('should load all catalog IDs from shader-lists', () => {
      const catalog = loadCurrentCatalog();
      assert.ok(catalog.size > 0, 'Catalog should not be empty');
      assert.ok([...catalog].every(id => typeof id === 'string'), 'All IDs should be strings');
    });
  });
});
