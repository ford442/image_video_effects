/**
 * Request a WebGPU device with the feature set expected by Pixelocity shaders.
 * Mirrors WebGPURenderer initialization so compile-time checks match runtime.
 *
 * Cross-reference: src/renderer/webgpuDevicePolicy.ts and wasm_renderer/device.cpp.
 */
import {
  assertAdapterMeetsContract,
  buildRequiredLimits,
} from '../renderer/webgpuDevicePolicy';

export interface PixelocityDeviceResult {
  device: GPUDevice;
  supportsSubgroups: boolean;
}

/** Conservative canvas dimension for scanner compile checks (no live canvas). */
const SCANNER_MAX_CANVAS_DIM = 8192;

export async function requestPixelocityDevice(
  adapter: GPUAdapter,
  maxCanvasDim: number = SCANNER_MAX_CANVAS_DIM,
): Promise<PixelocityDeviceResult | null> {
  const contract = assertAdapterMeetsContract(adapter, { maxCanvasDim });
  if (!contract.ok) {
    console.warn('[WebGPU] Scanner: adapter limits insufficient:', contract.failures);
    return null;
  }

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
      requiredLimits: buildRequiredLimits(maxCanvasDim),
    });
    const supportsSubgroups = !!(
      subgroupFeatureName && device.features.has(subgroupFeatureName)
    );
    return { device, supportsSubgroups };
  } catch {
    return null;
  }
}
