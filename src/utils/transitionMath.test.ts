import { lerpParam, snapToStep } from './transitionMath';

describe('transitionMath', () => {
  test('clamps interpolated values to valid range', () => {
    expect(lerpParam(0, 10, 0.5, 0, 1)).toBeLessThanOrEqual(1);
    expect(lerpParam(0, -10, 0.5, 0, 1)).toBeGreaterThanOrEqual(0);
  });

  test('snaps target to step boundaries', () => {
    expect(snapToStep(0.87, 0, 1, 0.1)).toBeCloseTo(0.9, 8);
    expect(snapToStep(1.2, 0, 1, 0.1)).toBe(1);
  });
});

