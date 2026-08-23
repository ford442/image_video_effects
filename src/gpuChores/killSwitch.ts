/**
 * `?no_gpu_compute` forces the TS analysis backend.
 * Chrome/Edge WebGPU mismatch must degrade with a reason string — never a
 * second requestDevice() or dual-hot WebGL+WebGPU on the same working set.
 */

export const NO_GPU_COMPUTE_PARAM = 'no_gpu_compute';

export function isGpuComputeKillSwitchEnabled(
  search: string | null | undefined = typeof window !== 'undefined'
    ? window.location.search
    : '',
): boolean {
  if (!search) return false;
  try {
    const params = new URLSearchParams(search.startsWith('?') ? search : `?${search}`);
    if (!params.has(NO_GPU_COMPUTE_PARAM)) return false;
    const value = params.get(NO_GPU_COMPUTE_PARAM);
    if (value === null || value === '' || value === '1' || value === 'true') return true;
    if (value === '0' || value === 'false') return false;
    return true;
  } catch {
    return false;
  }
}

export function gpuComputeKillReason(): string {
  return 'kill switch ?no_gpu_compute';
}
