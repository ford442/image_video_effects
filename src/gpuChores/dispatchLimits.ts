import {
  DEFAULT_MAX_WORKGROUPS_PER_DIMENSION,
  clampWorkgroupCount,
} from './dispatch';

export interface DispatchLimits {
  maxComputeWorkgroupsPerDimension?: number;
}

export interface DispatchCounts {
  x: number;
  y: number;
  z: number;
}

function maxPerDimension(limits?: DispatchLimits | null): number {
  const n = limits?.maxComputeWorkgroupsPerDimension;
  return typeof n === 'number' && n > 0 ? n : DEFAULT_MAX_WORKGROUPS_PER_DIMENSION;
}

/**
 * Last-line check before GPUComputePassEncoder.dispatchWorkgroups.
 * Throws if any axis exceeds maxComputeWorkgroupsPerDimension (WebGPU base 65535).
 * Callers must 2D-tile first (workgroups2d); this does not flatten w*h/64.
 */
export function assertDispatchWithinLimits(
  x: number,
  y = 1,
  z = 1,
  limits?: DispatchLimits | null,
): DispatchCounts {
  const max = maxPerDimension(limits);
  const nx = Math.floor(x);
  const ny = Math.floor(y);
  const nz = Math.floor(z);
  if (
    ![nx, ny, nz].every((n) => Number.isFinite(n) && n >= 1 && n <= max)
  ) {
    throw new Error(
      `Dispatch workgroup count exceeds maxComputeWorkgroupsPerDimension (${max}): (${x}, ${y}, ${z})`,
    );
  }
  return { x: nx, y: ny, z: nz };
}

/** Clamp each axis into [1, max] — safety net after workgroups2d. */
export function clampDispatchToLimits(
  x: number,
  y = 1,
  z = 1,
  limits?: DispatchLimits | null,
): DispatchCounts {
  const max = maxPerDimension(limits);
  return {
    x: clampWorkgroupCount(x, max),
    y: clampWorkgroupCount(y, max),
    z: clampWorkgroupCount(z, max),
  };
}
