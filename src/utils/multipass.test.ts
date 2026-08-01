import { getMultipassInfo, isMultipass } from '../utils/multipass';

describe('getMultipassInfo', () => {
  // ── Graph-runner (Tier C) entries ──────────────────────────────────────────
  it('returns 4-pass for ripple-tank (4 graph nodes)', () => {
    const info = getMultipassInfo('ripple-tank');
    expect(info).not.toBeNull();
    expect(info!.passCount).toBe(4);
  });

  it('returns 4-pass for fabric-of-reality (4 graph nodes)', () => {
    const info = getMultipassInfo('fabric-of-reality');
    expect(info).not.toBeNull();
    expect(info!.passCount).toBe(4);
  });

  it('returns 3-pass for photonic-caustics-graph (3 graph nodes)', () => {
    const info = getMultipassInfo('photonic-caustics-graph');
    expect(info).not.toBeNull();
    expect(info!.passCount).toBe(3);
  });

  it('returns 3-pass for wave-tank (3 graph nodes)', () => {
    const info = getMultipassInfo('wave-tank');
    expect(info).not.toBeNull();
    expect(info!.passCount).toBe(3);
  });

  // ── Linear Tier B chains ──────────────────────────────────────────────────
  it('returns 3-pass for rd-on-video-pass1 (linear 3-pass chain)', () => {
    const info = getMultipassInfo('rd-on-video-pass1');
    expect(info).not.toBeNull();
    expect(info!.passCount).toBe(3);
  });

  it('returns 2-pass for vortex-pass1 (linear 2-pass chain)', () => {
    const info = getMultipassInfo('vortex-pass1');
    expect(info).not.toBeNull();
    expect(info!.passCount).toBe(2);
  });

  it('returns null for a mid-chain pass (not pass 1)', () => {
    // rd-on-video-pass2 is pass 2 — should not show as entry point
    expect(getMultipassInfo('rd-on-video-pass2')).toBeNull();
  });

  // ── Single-pass entries ───────────────────────────────────────────────────
  it('returns null for a single-pass shader', () => {
    expect(getMultipassInfo('wave-equation')).toBeNull();
  });

  it('returns null for an unknown id', () => {
    expect(getMultipassInfo('not-a-real-shader')).toBeNull();
  });
});

describe('isMultipass', () => {
  it('returns true for ripple-tank', () => {
    expect(isMultipass('ripple-tank')).toBe(true);
  });

  it('returns true for a linear chain start (vortex-pass1)', () => {
    expect(isMultipass('vortex-pass1')).toBe(true);
  });

  it('returns false for single-pass shader', () => {
    expect(isMultipass('wave-equation')).toBe(false);
  });

  it('returns false for unknown shader id', () => {
    expect(isMultipass('unknown-shader-id')).toBe(false);
  });

  it('returns false for mid-chain pass (rd-on-video-pass2)', () => {
    expect(isMultipass('rd-on-video-pass2')).toBe(false);
  });
});
