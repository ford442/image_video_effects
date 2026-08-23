/**
 * Gate gpu-chores on a successful WebGPU boot probe.
 */

export function isWebGpuProbeOk(): boolean {
  if (typeof window === 'undefined') return true;
  const probe = window.webgpuProbe;
  if (probe == null) return true;
  return probe.ok === true;
}

export function webGpuProbeFailureReason(): string {
  if (typeof window === 'undefined') return 'WebGPU boot probe failed';
  const probe = window.webgpuProbe;
  return probe?.lastError ?? 'WebGPU boot probe failed';
}
