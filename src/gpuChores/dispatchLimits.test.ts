import {
  assertDispatchWithinLimits,
  clampDispatchToLimits,
} from './dispatchLimits';
import { DEFAULT_MAX_WORKGROUPS_PER_DIMENSION, workgroups2d } from './dispatch';

describe('assertDispatchWithinLimits', () => {
  const limits = { maxComputeWorkgroupsPerDimension: DEFAULT_MAX_WORKGROUPS_PER_DIMENSION };

  it('accepts a legal 2D 2048² chores grid', () => {
    const wg = workgroups2d(2048, 2048);
    expect(assertDispatchWithinLimits(wg.x, wg.y, 1, limits)).toEqual({ x: 256, y: 256, z: 1 });
  });

  it('throws on 65536 in X (the flattened 2048² / 64 bug)', () => {
    expect(() => assertDispatchWithinLimits(65536, 1, 1, limits)).toThrow(
      /maxComputeWorkgroupsPerDimension/,
    );
  });

  it('throws when any axis exceeds a tight device cap', () => {
    expect(() =>
      assertDispatchWithinLimits(11, 1, 1, { maxComputeWorkgroupsPerDimension: 10 }),
    ).toThrow(/exceeds/);
  });
});

describe('clampDispatchToLimits', () => {
  it('caps an oversized axis at the device max', () => {
    expect(
      clampDispatchToLimits(65536, 70000, 1, { maxComputeWorkgroupsPerDimension: 65535 }),
    ).toEqual({ x: 65535, y: 65535, z: 1 });
  });
});
