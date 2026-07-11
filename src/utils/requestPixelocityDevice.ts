/**
 * Request a WebGPU device with the feature set expected by Pixelocity shaders.
 * Mirrors WebGPURenderer initialization so compile-time checks match runtime.
 */
export interface PixelocityDeviceResult {
  device: GPUDevice;
  supportsSubgroups: boolean;
}

export async function requestPixelocityDevice(
  adapter: GPUAdapter
): Promise<PixelocityDeviceResult | null> {
  const wantFeatures: GPUFeatureName[] = [];
  if (adapter.features.has('float32-filterable')) {
    wantFeatures.push('float32-filterable');
  }

  const subgroupFeatureName: GPUFeatureName | null =
    adapter.features.has('subgroups')
      ? 'subgroups'
      : adapter.features.has('chromium-experimental-subgroups' as GPUFeatureName)
        ? ('chromium-experimental-subgroups' as GPUFeatureName)
        : null;
  if (subgroupFeatureName) {
    wantFeatures.push(subgroupFeatureName);
  }

  try {
    const device = await adapter.requestDevice({
      label: 'PixelocityScannerDevice',
      requiredFeatures: wantFeatures,
    });
    const supportsSubgroups = !!(
      subgroupFeatureName && device.features.has(subgroupFeatureName)
    );
    return { device, supportsSubgroups };
  } catch {
    return null;
  }
}
