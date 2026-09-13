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
import canvasConfigureContract from '../../contracts/canvas_configure.json';

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
  /** Probe result: swapchain accepts COPY_SRC (enables canvas → VideoFrame capture). */
  canvasCopySrc: boolean;
  canvasColorOptIns: Pick<CanvasConfigureOptIns, 'displayP3' | 'extendedToneMapping'>;
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
    canvasCopySrc: handoff.canvasCopySrc,
    canvasColorOptIns: handoff.canvasColorOptIns,
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

/** Opt-ins layered on top of the default canvas configure contract. */
export interface CanvasConfigureOptIns {
  /** Add COPY_SRC to the swapchain usage (only when probe flag canvasCopySrc is true). */
  copySrc?: boolean;
  /** Request colorSpace 'display-p3' (?display_p3=1). */
  displayP3?: boolean;
  /** Request toneMapping { mode: 'extended' } (display-p3 opt-in + HDR display only). */
  extendedToneMapping?: boolean;
}

// WebGPU spec GPUTextureUsage bit values, for non-browser (Jest / SSR) evaluation.
const TEXTURE_USAGE_FALLBACK: Record<string, number> = {
  COPY_SRC: 0x01,
  RENDER_ATTACHMENT: 0x10,
};

function textureUsageBits(names: readonly string[]): GPUTextureUsageFlags {
  const table = (typeof GPUTextureUsage !== 'undefined'
    ? GPUTextureUsage
    : TEXTURE_USAGE_FALLBACK) as unknown as Record<string, number>;
  return names.reduce((bits, name) => bits | table[name], 0);
}

/**
 * Canvas context configure options (parity with WASM JS_CreateSurfaceFromCanvas).
 * Values come from src/contracts/canvas_configure.json. The default path writes
 * only alphaMode + usage; colorSpace/toneMapping stay browser defaults (srgb /
 * standard) unless explicitly opted in.
 */
export function buildCanvasConfigureOptions(
  device: GPUDevice,
  format: GPUTextureFormat,
  optIns: CanvasConfigureOptIns = {},
): GPUCanvasConfiguration {
  const usageNames = optIns.copySrc
    ? canvasConfigureContract.optIn.copySrc.usage
    : canvasConfigureContract.usage;
  const config: GPUCanvasConfiguration = {
    device,
    format,
    alphaMode: canvasConfigureContract.alphaMode as GPUCanvasAlphaMode,
    usage: textureUsageBits(usageNames),
  };
  if (optIns.displayP3) {
    config.colorSpace = canvasConfigureContract.optIn.displayP3.colorSpace as PredefinedColorSpace;
    if (optIns.extendedToneMapping) {
      config.toneMapping = {
        mode: canvasConfigureContract.optIn.extendedToneMapping.toneMappingMode as GPUCanvasToneMappingMode,
      };
    }
  }
  return config;
}

/**
 * Parse the display-p3 opt-in from a URL search string. Extended tone mapping
 * additionally requires an HDR display (`(dynamic-range: high)`).
 */
export function resolveCanvasColorOptIns(
  search: string = typeof window !== 'undefined' ? window.location.search : '',
  isHdrDisplay: () => boolean = () =>
    typeof window !== 'undefined' &&
    typeof window.matchMedia === 'function' &&
    window.matchMedia(canvasConfigureContract.optIn.extendedToneMapping.requiresMediaQuery).matches,
): Pick<CanvasConfigureOptIns, 'displayP3' | 'extendedToneMapping'> {
  const params = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  const displayP3 = params.get(canvasConfigureContract.optIn.displayP3.urlParam) === '1';
  return {
    displayP3,
    extendedToneMapping: displayP3 && isHdrDisplay(),
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
