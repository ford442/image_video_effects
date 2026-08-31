/**
 * device.ts
 *
 * WebGPU adapter/device acquisition and canvas context setup.
 * Mirrors wasm_renderer/device.cpp.
 */

import { reportError } from '../ErrorHandling';
import type { WebGpuProbeHandoff } from '../webgpuBootProbe';
import { publishWebGpuProbe, runWebGpuBootProbe } from '../webgpuBootProbe';
import { AdapterGpuType, DeviceFormatCapabilities } from '../../config/formatPolicy';

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
  adapterGpuType: AdapterGpuType;
  formatCapabilities: DeviceFormatCapabilities;
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

function outcomeFromHandoff(handoff: WebGpuProbeHandoff): WebGPUDeviceInitResult {
  return {
    ok: true,
    device: handoff.device,
    context: handoff.context,
    canvasFormat: handoff.canvasFormat,
    canvasW: handoff.canvasW,
    canvasH: handoff.canvasH,
    supportsSubgroups: handoff.supportsSubgroups,
    supportsDeepWorkgroup: handoff.supportsDeepWorkgroup,
    hasF32Filterable: handoff.hasF32Filterable,
    adapterGpuType: handoff.adapterGpuType,
    formatCapabilities: handoff.formatCapabilities,
    adapterSummary: handoff.adapterSummary,
    adapterAttemptLabel: handoff.adapterAttemptLabel,
  };
}

/** Pixelocity optional features requested when the adapter offers them. */
const PIXELOCITY_OPTIONAL_FEATURES = [
  'float32-filterable',
  'timestamp-query',
  'subgroups',
  'chromium-experimental-subgroups',
] as const;

/**
 * Collect optional device features to request (mirrors wasm_renderer/device.cpp order).
 * timestamp-query is always-on when available (#1007 / #1030).
 */
export function collectOptionalDeviceFeatures(adapter: GPUAdapter): GPUFeatureName[] {
  const features: GPUFeatureName[] = [];
  if (adapter.features.has('float32-filterable')) {
    features.push('float32-filterable');
  }
  if (adapter.features.has('timestamp-query')) {
    features.push('timestamp-query');
  }
  const subgroupFeatureName = resolveSubgroupFeatureName(adapter);
  if (subgroupFeatureName) {
    features.push(subgroupFeatureName);
  }
  return features;
}

/** Compact diagnostics string for enabled Pixelocity-requested features. */
export function formatEnabledDeviceFeatures(device: GPUDevice): string {
  const enabled = PIXELOCITY_OPTIONAL_FEATURES.filter((f) =>
    device.features.has(f as GPUFeatureName),
  );
  return `features=[${enabled.join(',')}]`;
}

/** Canvas context configure options (parity with WASM JS_CreateSurfaceFromCanvas). */
export function buildCanvasConfigureOptions(
  device: GPUDevice,
  format: GPUTextureFormat,
): GPUCanvasConfiguration {
  return {
    device,
    format,
    alphaMode: 'opaque',
    usage: typeof GPUTextureUsage !== 'undefined' ? GPUTextureUsage.RENDER_ATTACHMENT : 0x10,
  };
}

/** Append post-device fields to adapterSummary in WASM-aligned order. */
export function appendAdapterSummaryFields(
  base: string,
  device: GPUDevice,
  canvasFormat: GPUTextureFormat,
): string {
  let summary = base;
  if (device.limits) {
    const dl = device.limits;
    summary += ` | device: maxTex2D=${dl.maxTextureDimension2D} computeInvocations=${dl.maxComputeInvocationsPerWorkgroup}`;
  }
  summary += ` | ${formatEnabledDeviceFeatures(device)}`;
  summary += ` | surfaceFormat=${canvasFormat}`;
  return summary;
}

export function resolveSubgroupFeatureName(adapter: GPUAdapter): GPUFeatureName | null {
  if (adapter.features.has('subgroups')) return 'subgroups';
  if (adapter.features.has('chromium-experimental-subgroups' as GPUFeatureName)) {
    return 'chromium-experimental-subgroups' as GPUFeatureName;
  }
  return null;
}

export async function initializeWebGPUDevice(
  canvas: HTMLCanvasElement,
  configWidth: number,
  configHeight: number,
  existingHandoff?: WebGpuProbeHandoff,
): Promise<WebGPUDeviceInitOutcome> {
  if (existingHandoff) {
    return outcomeFromHandoff(existingHandoff);
  }

  const probe = await runWebGpuBootProbe(canvas, configWidth, configHeight);
  publishWebGpuProbe(probe);
  if (!probe.ok || !probe.handoff) {
    return {
      ok: false,
      lastInitError: probe.lastError ?? 'WebGPU boot probe failed',
      adapterSummary: probe.adapterSummary ?? '',
      adapterAttemptLabel: probe.adapterAttemptLabel ?? null,
    };
  }

  return outcomeFromHandoff(probe.handoff);
}

export function attachDeviceLostHandler(
  device: GPUDevice,
  context: GPUCanvasContext | null,
  onLost: () => void,
): void {
  device.lost.then((info) => {
    if (info.reason === 'destroyed') {
      try {
        context?.unconfigure();
      } catch {
        // Ignore errors during cleanup
      }
      return;
    }
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
