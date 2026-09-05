/** WebGPU base limit. device.limits may be higher; never assume it is. */
export const DEFAULT_MAX_WORKGROUPS_PER_DIMENSION = 65535;

export function maxWorkgroupsPerDimension(device?: GPUDevice | null): number {
  const n = device?.limits?.maxComputeWorkgroupsPerDimension;
  return typeof n === 'number' && n > 0 ? n : DEFAULT_MAX_WORKGROUPS_PER_DIMENSION;
}

export function clampWorkgroupCount(
  count: number,
  maxPerDim = DEFAULT_MAX_WORKGROUPS_PER_DIMENSION,
): number {
  if (!Number.isFinite(count) || count < 1) return 1;
  return Math.min(Math.floor(count), maxPerDim);
}

/** Safety net for a flattened 1D dispatch. Caps X; does not invent a Y. */
export function workgroups1d(
  elementCount: number,
  workgroupSize = 64,
  maxPerDim = DEFAULT_MAX_WORKGROUPS_PER_DIMENSION,
): number {
  return clampWorkgroupCount(Math.ceil(elementCount / workgroupSize), maxPerDim);
}

/** Coverage-preserving path for @workgroup_size(8, 8) image kernels. */
export function workgroups2d(
  width: number,
  height: number,
  workgroupX = 8,
  workgroupY = 8,
  maxPerDim = DEFAULT_MAX_WORKGROUPS_PER_DIMENSION,
): { x: number; y: number } {
  return {
    x: clampWorkgroupCount(Math.ceil(width / workgroupX), maxPerDim),
    y: clampWorkgroupCount(Math.ceil(height / workgroupY), maxPerDim),
  };
}
