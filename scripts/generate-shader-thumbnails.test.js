/**
 * Unit tests for thumbnail generator CLI helpers (node --test).
 */
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  parseArgs,
  hasExistingThumbnail,
  classifyFailure,
  extractDefaultParams,
} = require('./generate-shader-thumbnails');

describe('generate-shader-thumbnails', () => {
  it('parseArgs defaults to app engine and all-catalog', () => {
    const args = parseArgs([]);
    assert.equal(args.engine, 'app');
    assert.equal(args.category, 'all-catalog');
    assert.equal(args.frames, 60);
    assert.equal(args.size, 256);
    assert.equal(args.quality, 'battery');
  });

  it('parseArgs --missing sets skipExisting', () => {
    const args = parseArgs(['--missing']);
    assert.equal(args.missing, true);
    assert.equal(args.skipExisting, true);
  });

  it('parseArgs --force is distinct from missing', () => {
    const args = parseArgs(['--force', '--missing']);
    assert.equal(args.force, true);
    assert.equal(args.skipExisting, true);
  });

  it('parseArgs shard and engine', () => {
    const args = parseArgs(['--shard=1/4', '--engine=minimal', '--limit=10']);
    assert.equal(args.shardIndex, 1);
    assert.equal(args.shardCount, 4);
    assert.equal(args.engine, 'minimal');
    assert.equal(args.limit, 10);
  });

  it('hasExistingThumbnail requires manifest and png', () => {
    const fs = require('fs');
    const path = require('path');
    const pngPath = path.join(__dirname, '..', 'public', 'thumbnails');
    const existing = fs.readdirSync(pngPath).find(f => f.endsWith('.png'));
    if (existing) {
      const id = existing.replace('.png', '');
      assert.equal(hasExistingThumbnail(id, { [id]: {} }), true);
    }
    assert.equal(hasExistingThumbnail('nonexistent-shader-id-xyz', { foo: {} }), false);
  });

  it('classifyFailure maps compile and black_frame', () => {
    assert.equal(classifyFailure('compile: line 1 error'), 'compile');
    assert.equal(classifyFailure('black_frame'), 'black_frame');
    assert.equal(classifyFailure('no GPU adapter'), 'gpu_unavailable');
  });

  it('extractDefaultParams reads zoom_params mappings', () => {
    const params = extractDefaultParams({
      params: [
        { mapping: 'zoom_params.x', default: 0.3 },
        { mapping: 'zoom_params.y', default: 0.7 },
      ],
    });
    assert.equal(params[0], 0.3);
    assert.equal(params[1], 0.7);
  });
});
