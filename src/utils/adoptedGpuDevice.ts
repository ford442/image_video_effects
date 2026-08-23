/**
 * Single adopted renderer GPUDevice registry.
 * Populated from the boot-probe handoff — consumers must never requestAdapter/requestDevice.
 */

let adoptedDevice: GPUDevice | null = null;
let adoptedSupportsSubgroups = false;

export function registerAdoptedRendererDevice(
  device: GPUDevice | null,
  supportsSubgroups = false,
): void {
  adoptedDevice = device;
  adoptedSupportsSubgroups = supportsSubgroups;
}

export function clearAdoptedRendererDevice(): void {
  adoptedDevice = null;
  adoptedSupportsSubgroups = false;
}

export function getAdoptedRendererDevice(): GPUDevice | null {
  return adoptedDevice;
}

export function getAdoptedSupportsSubgroups(): boolean {
  return adoptedSupportsSubgroups;
}

export function releaseAdoptedDeviceIfLeavingWebGpu(
  previousType: string | null,
  targetType: string,
): void {
  if (previousType === 'webgpu' && targetType !== 'webgpu') clearAdoptedRendererDevice();
}

export function adoptHandoffDeviceIfWebGpu(
  targetType: string,
  handoff?: { device: GPUDevice; supportsSubgroups: boolean } | null,
): void {
  if (targetType === 'webgpu' && handoff?.device) {
    registerAdoptedRendererDevice(handoff.device, handoff.supportsSubgroups);
  }
}
