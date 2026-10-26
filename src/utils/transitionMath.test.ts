import { crossfadeMix, easeInOutSine, lerpParam, snapToStep } from './transitionMath';

describe('transitionMath', () => {
  test('clamps interpolated values to valid range', () => {
    expect(lerpParam(0, 10, 0.5, 0, 1)).toBeLessThanOrEqual(1);
    expect(lerpParam(0, -10, 0.5, 0, 1)).toBeGreaterThanOrEqual(0);
  });

  test('snaps target to step boundaries', () => {
    expect(snapToStep(0.87, 0, 1, 0.1)).toBeCloseTo(0.9, 8);
    expect(snapToStep(1.2, 0, 1, 0.1)).toBe(1);
  });

  describe('crossfadeMix', () => {
    test('starts on the hold and ends on the live frame', () => {
      expect(crossfadeMix(0)).toBe(1);
      expect(crossfadeMix(1)).toBeCloseTo(0, 12);
      expect(crossfadeMix(0.5)).toBeCloseTo(0.5, 12);
    });

    test('is the eased progress run backwards, on the same curve as the sliders', () => {
      for (const p of [0, 0.1, 0.25, 0.4, 0.75, 0.9, 1]) {
        expect(crossfadeMix(p)).toBeCloseTo(1 - easeInOutSine(p), 12);
      }
      expect(crossfadeMix(0.25, (x) => x)).toBeCloseTo(0.75, 12);
    });

    test('never leaves 0..1, whatever progress or easing does', () => {
      expect(crossfadeMix(-3)).toBe(1);
      expect(crossfadeMix(7)).toBeCloseTo(0, 12);
      expect(crossfadeMix(0.5, () => 4)).toBe(0);
      expect(crossfadeMix(0.5, () => -4)).toBe(1);
    });

    test('falls to the live frame for a progress that is not a number', () => {
      expect(crossfadeMix(Number.NaN)).toBe(0);
      expect(crossfadeMix(Number.POSITIVE_INFINITY)).toBe(0);
    });

    test('is monotone from hold to live', () => {
      let previous = crossfadeMix(0);
      for (let i = 1; i <= 100; i++) {
        const mix = crossfadeMix(i / 100);
        expect(mix).toBeLessThanOrEqual(previous);
        previous = mix;
      }
    });
  });
});
