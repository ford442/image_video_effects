import {
  captureByte,
  captureRgb,
  deltaE76,
  imageDeltaE,
  maxChannelDelta,
  srgb8ToLab,
} from './goldenTolerance';
import { referenceComposite } from './compositorReference';

describe('golden-frame tolerance helper (#1512)', () => {
  it('maps linear values to the readback bytes', () => {
    expect(captureByte(0)).toBe(0);
    expect(captureByte(1)).toBe(255);
    expect(captureByte(4)).toBe(255); // HDR values clamp
    expect(captureByte(0.5)).toBe(Math.round(0.5 ** (1 / 2.2) * 255));
    expect(captureRgb([0.25, 0.5, 1, 1])).toEqual([captureByte(0.25), captureByte(0.5), 255]);
  });

  it('measures channel deltas', () => {
    expect(maxChannelDelta([10, 20, 30], [12, 17, 30])).toBe(3);
    expect(maxChannelDelta([10, 20, 30, 0], [10, 20, 30, 255])).toBe(0); // alpha ignored
  });

  it('computes CIE76 ΔE from sRGB bytes', () => {
    const white = srgb8ToLab([255, 255, 255]);
    expect(white[0]).toBeCloseTo(100, 1);
    expect(Math.abs(white[1])).toBeLessThan(0.05);
    expect(Math.abs(white[2])).toBeLessThan(0.05);
    expect(srgb8ToLab([0, 0, 0])[0]).toBeCloseTo(0, 5);
    expect(deltaE76([128, 64, 200], [128, 64, 200])).toBe(0);
    // One step of a mid grey is under a just-noticeable difference; black vs white is ~100.
    expect(deltaE76([128, 128, 128], [129, 129, 129])).toBeLessThan(1);
    expect(deltaE76([0, 0, 0], [255, 255, 255])).toBeCloseTo(100, 0);
  });

  it('summarises ΔE across an image', () => {
    const a = new Uint8Array([10, 10, 10, 255, 200, 100, 50, 255]);
    const same = imageDeltaE(a, a);
    expect(same).toEqual({ mean: 0, p95: 0, max: 0 });
    const b = new Uint8Array([10, 10, 10, 255, 0, 0, 0, 255]);
    const diff = imageDeltaE(a, b);
    expect(diff.max).toBeGreaterThan(20);
    expect(diff.mean).toBeCloseTo(diff.max / 2, 5);
  });

  it('gives the screen-at-50% golden its expected bytes', () => {
    const out = referenceComposite([0, 0, 0, 1], [
      { output: 'replace', blend: 'normal', opacity: 1, color: [0.6, 0.25, 0.4, 1] },
      { output: 'blend', blend: 'screen', opacity: 0.5, color: [0.3, 0.7, 0.2, 1] },
    ]);
    // screen(a, b) = a + b − ab, then halfway from a.
    expect(out[0]).toBeCloseTo(0.6 + 0.5 * (0.3 - 0.6 * 0.3), 6);
    expect(captureRgb(out)).toEqual(out.slice(0, 3).map(captureByte));
  });
});
