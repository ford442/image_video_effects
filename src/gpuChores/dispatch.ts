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

function assertPositiveWorkgroupSize(size: number, axis: string): number {
  if (!Number.isFinite(size) || size <= 0) {
    throw new Error(`${axis} workgroup size must be > 0`);
  }
  return size;
}

/** Safety net for a flattened 1D dispatch. Caps X; does not invent a Y. */
export function workgroups1d(
  elementCount: number,
  workgroupSize = 64,
  maxPerDim = DEFAULT_MAX_WORKGROUPS_PER_DIMENSION,
): number {
  const size = assertPositiveWorkgroupSize(workgroupSize, '1D');
  return clampWorkgroupCount(Math.ceil(elementCount / size), maxPerDim);
}

/** Coverage-preserving path for @workgroup_size(8, 8) image kernels. */
export function workgroups2d(
  width: number,
  height: number,
  workgroupX = 8,
  workgroupY = 8,
  maxPerDim = DEFAULT_MAX_WORKGROUPS_PER_DIMENSION,
): { x: number; y: number } {
  const xSize = assertPositiveWorkgroupSize(workgroupX, 'X');
  const ySize = assertPositiveWorkgroupSize(workgroupY, 'Y');
  return {
    x: clampWorkgroupCount(Math.ceil(width / xSize), maxPerDim),
    y: clampWorkgroupCount(Math.ceil(height / ySize), maxPerDim),
  };
}
