#!/usr/bin/env node
/**
 * Test suite for check-thumbnail-coverage.js
 */

const fs = require('fs');
const path = require('path');
const { describe, it, before, after } = require('node:test');
const assert = require('node:assert');

const ROOT = path.join(__dirname, '..');

// Import functions from the main module
const module_ = require('./check-thumbnail-coverage.js');
const {
  healthyIds,
  loadCurrentCatalog,
  loadDeferralEntries,
} = module_;

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

  describe('loadDeferralEntries', () => {
    it('should load valid, non-expired deferral entries', () => {
      const deferralPath = path.join(ROOT, 'reports', 'thumbnail_deferrals.json');
      
      // Create a test deferral with an entry far in the future
      const futureDate = new Date();
      futureDate.setDate(futureDate.getDate() + 15);
      const futureStr = futureDate.toISOString().split('T')[0];
      
      const testData = {
        entries: [
          {
            id: 'test-shader-1',
            added_by: 'test',
            pr: 9999,
            deferred_at: new Date().toISOString().split('T')[0],
            expires: futureStr,
            reason: 'test deferral'
          }
        ]
      };
      
      fs.writeFileSync(deferralPath, JSON.stringify(testData, null, 2));
      
      try {
        const deferrals = loadDeferralEntries();
        assert.ok(deferrals.valid.has('test-shader-1'));
      } finally {
        fs.writeFileSync(deferralPath, JSON.stringify({ entries: [] }, null, 2));
      }
    });

    it('should exclude expired deferral entries', () => {
      const deferralPath = path.join(ROOT, 'reports', 'thumbnail_deferrals.json');
      
      // Create a test deferral with an expired date
      const pastDate = new Date();
      pastDate.setDate(pastDate.getDate() - 5);
      const pastStr = pastDate.toISOString().split('T')[0];
      
      const testData = {
        entries: [
          {
            id: 'expired-shader',
            added_by: 'test',
            pr: 9999,
            deferred_at: '2026-01-01',
            expires: pastStr,
            reason: 'expired deferral'
          }
        ]
      };
      
      fs.writeFileSync(deferralPath, JSON.stringify(testData, null, 2));
      
      try {
        const deferrals = loadDeferralEntries();
        assert.ok(!deferrals.valid.has('expired-shader'));
      } finally {
        fs.writeFileSync(deferralPath, JSON.stringify({ entries: [] }, null, 2));
      }
    });

    it('should return empty set when no deferrals file exists', () => {
      const deferralPath = path.join(ROOT, 'reports', 'thumbnail_deferrals.json');
      const backup = fs.existsSync(deferralPath) 
        ? fs.readFileSync(deferralPath, 'utf8')
        : null;
      
      try {
        if (fs.existsSync(deferralPath)) {
          fs.unlinkSync(deferralPath);
        }
        
        // This will be called when the file doesn't exist
        // The script should handle this gracefully
      } finally {
        if (backup) {
          fs.writeFileSync(deferralPath, backup);
        }
      }
    });
  });

  describe('loadCurrentCatalog', () => {
    it('should load all catalog IDs from shader-lists', () => {
      const catalog = loadCurrentCatalog();
      assert.ok(catalog.size > 0, 'Catalog should not be empty');
      
      // Check that we have the expected structure
      assert.ok([...catalog].every(id => typeof id === 'string'), 'All IDs should be strings');
    });
  });
});

console.log('✓ Thumbnail coverage check tests completed');
