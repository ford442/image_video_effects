/**
 * device.ts
 *
 * WebGPU adapter/device acquisition and canvas context setup.
 * Mirrors wasm_renderer/device.cpp.
 */

import { reportError, getBrowserWarning } from '../ErrorHandling';
import {
  assertAdapterMeetsContract,
  buildRequiredLimits,
  formatAdapterLimitsSummary,
  logAdapterFeatures,
  requestAdapterWithFallback,
} from '../webgpuDevicePolicy';

export interface WebGPUDeviceInitResult {
  ok: true;
  device: GPUDevice;
  context: GPUCanvasContext;
  canvasFormat: GPUTextureFormat;
  canvasW: number;
  canvasH: number;
  supportsSubgroups: boolean;
  supportsDeepWorkgroup: boolean;
  hasF32Filterable: boolean;
  adapterSummary: string;
  adapterAttemptLabel: string | null;
}

export interface WebGPUDeviceInitFailure {
  ok: false;
  lastInitError: string;
  adapterSummary: string;
  adapterAttemptLabel: string | null;
}

export type WebGPUDeviceInitOutcome = WebGPUDeviceInitResult | WebGPUDeviceInitFailure;

export async function initializeWebGPUDevice(
  canvas: HTMLCanvasElement,
  configWidth: number,
  configHeight: number,
): Promise<WebGPUDeviceInitOutcome> {
  if (!navigator.gpu) {
    const warning = getBrowserWarning();
    reportError({
      type: 'webgpu-unavailable',
      message: warning || 'WebGPU is not available in this browser',
      recoverable: false,
    });
    console.warn('[WebGPU] navigator.gpu is unavailable in this browser');
    return { ok: false, lastInitError: warning || 'WebGPU unavailable', adapterSummary: '', adapterAttemptLabel: null };
  }

  const canvasW = canvas.width || configWidth;
  const canvasH = canvas.height || configHeight;
  const maxCanvasDim = Math.max(canvasW, canvasH, 1);
  const { adapter, attemptLabel } = await requestAdapterWithFallback(navigator.gpu);

  if (!adapter) {
    const message =
      'Failed to obtain a WebGPU adapter after all fallback attempts ' +
      '(HighPerformance/Undefined/LowPower/forceFallbackAdapter).';
    reportError({ type: 'webgpu-unavailable', message, recoverable: false });
    console.warn('[WebGPU]', message);
    return { ok: false, lastInitError: message, adapterSummary: '', adapterAttemptLabel: attemptLabel };
  }

  logAdapterFeatures(adapter);

  const contract = assertAdapterMeetsContract(adapter, { maxCanvasDim });
  if (!contract.ok) {
    const adapterSummary = `INSUFFICIENT adapter limits — ${contract.failures.join('; ')}`;
    reportError({
      type: 'webgpu-unavailable',
      message: `${contract.message} (${contract.failures.join('; ')})`,
      recoverable: false,
    });
    console.warn('[WebGPU] Adapter limits insufficient:', contract.failures);
    return { ok: false, lastInitError: contract.message, adapterSummary, adapterAttemptLabel: attemptLabel };
  }

  let adapterSummary = `Adapter attempt=${attemptLabel ?? 'unknown'} | limits: ${formatAdapterLimitsSummary(adapter)} (sufficient)`;

  const wantFeatures: GPUFeatureName[] = [];
  if (adapter.features.has('float32-filterable')) {
    wantFeatures.push('float32-filterable');
  }
  // Required for GPU timestamp readback (#1007 / #1030). Guarded — absent adapters skip it.
  if (adapter.features.has('timestamp-query')) {
    wantFeatures.push('timestamp-query');
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

  let device: GPUDevice;
  try {
    device = await adapter.requestDevice({
      label: 'PixelocityDevice',
      requiredFeatures: wantFeatures,
      requiredLimits: buildRequiredLimits(maxCanvasDim),
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    const lastInitError = `requestDevice failed: ${message}`;
    reportError({ type: 'webgpu-unavailable', message: lastInitError, recoverable: false });
    console.warn('[WebGPU] requestDevice failed:', e);
    return { ok: false, lastInitError, adapterSummary, adapterAttemptLabel: attemptLabel };
  }

  if (device.limits) {
    const dl = device.limits;
    adapterSummary += ` | device: maxTex2D=${dl.maxTextureDimension2D} computeInvocations=${dl.maxComputeInvocationsPerWorkgroup}`;
    console.log(
      '[WebGPU] Device limits:',
      `maxTex2D=${dl.maxTextureDimension2D} storageTex=${dl.maxStorageTexturesPerShaderStage} ` +
      `computeInvocations=${dl.maxComputeInvocationsPerWorkgroup}`,
    );
  }

  const supportsSubgroups = !!(subgroupFeatureName && device.features.has(subgroupFeatureName));
  if (supportsSubgroups) {
    console.log('[WebGPU] Subgroup operations enabled — fast -sg variants will be preferred');
  }

  const maxInvocations = adapter.limits?.maxComputeInvocationsPerWorkgroup ?? 256;
  const supportsDeepWorkgroup = maxInvocations >= 1024;
  if (supportsDeepWorkgroup) {
    console.log('[WebGPU] Deep-workgroup (16×16×4 = 1024 invocations) supported');
  } else {
    console.log(`[WebGPU] Deep-workgroup NOT supported (maxComputeInvocationsPerWorkgroup=${maxInvocations}); requiresDeepWorkgroup shaders will be filtered out`);
  }

  device.addEventListener('uncapturederror', (ev) => {
    console.error('[WebGPU] Uncaptured error:', (ev as GPUUncapturedErrorEvent).error);
  });

  const context = canvas.getContext('webgpu') as GPUCanvasContext | null;
  if (!context) {
    console.warn('[WebGPU] Failed to get webgpu canvas context');
    device.destroy();
    return { ok: false, lastInitError: 'Failed to get webgpu canvas context', adapterSummary, adapterAttemptLabel: attemptLabel };
  }

  const canvasFormat = navigator.gpu.getPreferredCanvasFormat();
  try {
    context.unconfigure();
  } catch {
    // Context might not have been configured yet
  }
  context.configure({ device, format: canvasFormat, alphaMode: 'opaque' });

  return {
    ok: true,
    device,
    context,
    canvasFormat,
    canvasW,
    canvasH,
    supportsSubgroups,
    supportsDeepWorkgroup,
    hasF32Filterable: device.features.has('float32-filterable'),
    adapterSummary,
    adapterAttemptLabel: attemptLabel,
  };
}

export function attachDeviceLostHandler(
  device: GPUDevice,
  context: GPUCanvasContext | null,
  onLost: () => void,
): void {
  device.lost.then((info) => {
    reportError({
      type: 'device-lost',
      message: `GPU device lost: ${info.reason}. Try reloading the page.`,
      recoverable: false,
    });
    console.error('[WebGPU] Device lost:', info.reason, info.message);
    try {
      context?.unconfigure();
    } catch {
      // Ignore errors during cleanup
    }
    onLost();
  });
}
