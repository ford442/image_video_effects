'use strict';
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { diffLedger } = require('./record-shader-upgrades');
const { stableStringify, passChain, thumbnailFreshness, loadMultipassRegistry } = require('./lib/shaderSourceHash');

describe('upgrade ledger', () => {
  it('records changed and new shaders, leaves unchanged alone', () => {
    const ledger = { shaders: { a: { hash: '1', history: [] }, b: { hash: '2', history: [] } } };
    const { changed, added } = diffLedger(ledger, { a: '1', b: '9', c: '3' }, { event: 'upgraded', note: 'n', date: 'd', commit: 'c' });
    assert.deepEqual(changed, ['b']);
    assert.deepEqual(added, ['c']);
    assert.equal(ledger.shaders.b.hash, '9');
    assert.deepEqual(ledger.shaders.b.history[0], { event: 'upgraded', date: 'd', hash: '9', prev_hash: '2', commit: 'c', note: 'n' });
    assert.equal(ledger.shaders.a.history.length, 0);
  });
});

describe('shaderSourceHash helpers', () => {
  it('stableStringify ignores key order', () => {
    assert.equal(stableStringify({ b: 1, a: [1, { d: 2, c: 3 }] }), stableStringify({ a: [1, { c: 3, d: 2 }], b: 1 }));
  });
  it('passChain follows nextShader without looping', () => {
    const reg = { p1: { nextShader: 'p2' }, p2: { nextShader: 'p1' } };
    assert.deepEqual(passChain('p1', reg), ['p1', 'p2']);
  });
  it('parses the real multipassRegistry.ts (hashes would silently drop later passes otherwise)', () => {
    const reg = loadMultipassRegistry();
    const withNext = Object.values(reg).filter(e => e && e.nextShader);
    assert.ok(withNext.length > 0, 'MULTIPASS_REGISTRY parsed to no chained passes');
  });
  it('thumbnailFreshness', () => {
    assert.equal(thumbnailFreshness('x', 'h', {}), 'missing');
    assert.equal(thumbnailFreshness('x', 'h', { x: {} }), 'unknown');
    assert.equal(thumbnailFreshness('x', 'h', { x: { source_hash: 'g' } }), 'stale');
    assert.equal(thumbnailFreshness('x', 'h', { x: { source_hash: 'h' } }), 'fresh');
  });
});
