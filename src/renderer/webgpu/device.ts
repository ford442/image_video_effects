/**
 * device.ts
 *
 * WebGPU adapter/device acquisition and canvas context setup.
 * Mirrors wasm_renderer/device.cpp.
 */

import { reportError } from '../ErrorHandling';
import type { CanvasColorFallbackReason, WebGpuProbeHandoff } from '../webgpuBootProbe';
import { publishWebGpuProbe, runWebGpuBootProbe } from '../webgpuBootProbe';
import { AdapterGpuType, DeviceFormatCapabilities } from '../../config/formatPolicy';
import type { AdapterIdentity } from '../../config/adapterIdentity';
import canvasConfigureContract from '../../contracts/canvas_configure.json';
import optionalFeaturesContract from '../../contracts/webgpu_optional_features.json';
import type { FeatureLevel, LimitsTier } from '../webgpuDevicePolicy';

export interface WebGPUDeviceInitResult {
  ok: true;
  device: GPUDevice;
  context: GPUCanvasContext;
  /** The applied swapchain format (rgba16float for the HDR canvas). */
  canvasFormat: GPUTextureFormat;
  /** The preferred format every SDR configure uses (#1512). */
  preferredCanvasFormat: GPUTextureFormat;
  /** The swapchain was accepted with STORAGE_BINDING for the compute present (#1512). */
  storagePresent: boolean;
  canvasW: number;
  canvasH: number;
  supportsSubgroups: boolean;
  supportsDeepWorkgroup: boolean;
  hasF32Filterable: boolean;
  adapterGpuType: AdapterGpuType;
  adapterIdentity: AdapterIdentity;
  formatCapabilities: DeviceFormatCapabilities;
  adapterSummary: string;
  adapterAttemptLabel: string | null;
  /** Probe result: swapchain accepts COPY_SRC (enables canvas → VideoFrame capture). */
  canvasCopySrc: boolean;
  canvasColorOptIns: CanvasColorOptInsState;
  canvasColorFallback?: CanvasColorFallbackReason;
  /** Removes the boot probe's log-only uncapturederror listener (see WebGpuProbeHandoff). */
  detachUncapturedLog?: () => void;
  /** Capability tier 2 (#1512): what the device was actually granted. */
  tier2: DeviceTier2;
}

/** Capability tier 2 (#1512): optional features, feature level and limits tiers of the live device. */
export interface DeviceTier2 {
  featureLevel: FeatureLevel;
  /** Created under compatibility validation (the compat rung). */
  compat: boolean;
  shaderF16: boolean;
  bgra8unormStorage: boolean;
  float32Blendable: boolean;
  dualSourceBlending: boolean;
  limitsTiers: LimitsTier[];
}

export const CORE_TIER2: DeviceTier2 = {
  featureLevel: 'core',
  compat: false,
  shaderF16: false,
  bgra8unormStorage: false,
  float32Blendable: false,
  dualSourceBlending: false,
  limitsTiers: [],
};

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
    preferredCanvasFormat: handoff.preferredCanvasFormat ?? handoff.canvasFormat,
    storagePresent: handoff.storagePresent ?? false,
    canvasW: handoff.canvasW,
    canvasH: handoff.canvasH,
    supportsSubgroups: handoff.supportsSubgroups,
    supportsDeepWorkgroup: handoff.supportsDeepWorkgroup,
    hasF32Filterable: handoff.hasF32Filterable,
    adapterGpuType: handoff.adapterGpuType,
    adapterIdentity: handoff.adapterIdentity,
    formatCapabilities: handoff.formatCapabilities,
    adapterSummary: handoff.adapterSummary,
    adapterAttemptLabel: handoff.adapterAttemptLabel,
    canvasCopySrc: handoff.canvasCopySrc,
    canvasColorOptIns: handoff.canvasColorOptIns,
    canvasColorFallback: handoff.canvasColorFallback,
    detachUncapturedLog: handoff.detachUncapturedLog,
    tier2: handoff.tier2 ?? CORE_TIER2,
  };
}

/**
 * Capability tier 2 (#1512), requested after the C++-mirrored three when the adapter offers
 * them. TS only (webgpu_optional_features.json tier2; the WASM backend stays frozen).
 */
export const TIER2_OPTIONAL_FEATURES = optionalFeaturesContract.tier2.requestOrder as readonly GPUFeatureName[];

/** Pixelocity optional features requested when the adapter offers them. */
const PIXELOCITY_OPTIONAL_FEATURES = [
  'float32-filterable',
  'timestamp-query',
  'subgroups',
  'chromium-experimental-subgroups',
  ...TIER2_OPTIONAL_FEATURES,
] as const;

/**
 * Collect optional device features to request (mirrors wasm_renderer/device.cpp order).
 * timestamp-query is always-on when available (#1007 / #1030). The tier-2 features follow.
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
  for (const feature of TIER2_OPTIONAL_FEATURES) {
    if (adapter.features.has(feature)) features.push(feature);
  }
  return features;
}

/** What the device was granted of tier 2 (granted, not offered: a device only has what it asked for). */
export function readDeviceTier2(
  device: GPUDevice,
  featureLevel: FeatureLevel,
  compat: boolean,
  limitsTiers: LimitsTier[],
): DeviceTier2 {
  const has = (name: string) => device.features.has(name as GPUFeatureName);
  return {
    featureLevel,
    compat,
    shaderF16: has('shader-f16'),
    bgra8unormStorage: has('bgra8unorm-storage'),
    float32Blendable: has('float32-blendable'),
    dualSourceBlending: has('dual-source-blending'),
    limitsTiers,
  };
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
  /**
   * Swap the canvas format for rgba16float (#1512, optIn.hdrCanvas). Honored only together
   * with displayP3 + extendedToneMapping: extended tone mapping is inert on an 8-bit canvas.
   */
  hdrCanvas?: boolean;
  /** Add STORAGE_BINDING so the present can write a bgra8unorm swapchain from compute (#1512). */
  storagePresent?: boolean;
}

/** The colour opt-ins a renderer remembers and re-applies on every configure. */
export type CanvasColorOptInsState = Pick<CanvasConfigureOptIns, 'displayP3' | 'extendedToneMapping' | 'hdrCanvas'>;

/** True when these opt-ins put the swapchain in rgba16float (the HDR canvas). */
export function isHdrCanvas(optIns: CanvasConfigureOptIns): boolean {
  return !!(optIns.displayP3 && optIns.extendedToneMapping && optIns.hdrCanvas);
}

/** The swapchain format a configure with these opt-ins produces (preferred unless HDR). */
export function effectiveCanvasFormat(preferred: GPUTextureFormat, optIns: CanvasConfigureOptIns = {}): GPUTextureFormat {
  return isHdrCanvas(optIns) ? (canvasConfigureContract.optIn.hdrCanvas.format as GPUTextureFormat) : preferred;
}

/** `?canvas_format=bgra8unorm|rgba8unorm` overrides getPreferredCanvasFormat() (tests, storage present). */
export function resolveCanvasFormatOverride(search: string): GPUTextureFormat | null {
  const params = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  const v = params.get('canvas_format');
  return v === 'bgra8unorm' || v === 'rgba8unorm' ? v : null;
}

/** `?storage_present=0` keeps the render-pass present even where storage present is possible. */
export function storagePresentDisabledByUrl(search: string): boolean {
  const params = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  return params.get(canvasConfigureContract.optIn.storagePresent.urlParam) === '0';
}

/** One canvas capability per canvas_configure.json optIn entry (shared with C++ canvas_configure.h). */
export type CanvasCapability = keyof typeof canvasConfigureContract.optIn;

// Compile-time lockstep: CanvasConfigureOptIns has exactly the contract's capability keys.
type SameKeys<A, B> = [keyof A] extends [keyof B] ? ([keyof B] extends [keyof A] ? true : false) : false;
const optInKeysMatchContract: SameKeys<Required<CanvasConfigureOptIns>, typeof canvasConfigureContract.optIn> = true;
void optInKeysMatchContract;

// WebGPU spec GPUTextureUsage bit values (contract usageBits), for non-browser (Jest / SSR) evaluation.
const TEXTURE_USAGE_FALLBACK: Record<string, number> = canvasConfigureContract.usageBits;

function textureUsageBits(names: readonly string[]): GPUTextureUsageFlags {
  const table = (typeof GPUTextureUsage !== 'undefined'
    ? GPUTextureUsage
    : TEXTURE_USAGE_FALLBACK) as unknown as Record<string, number>;
  return names.reduce((bits, name) => bits | (table[name] ?? 0), 0);
}

/**
 * Canvas context configure options (parity with WASM JS_CreateSurfaceFromCanvas).
 * Values come from src/contracts/canvas_configure.json. The default path writes
 * only alphaMode + usage; colorSpace/toneMapping stay browser defaults (srgb /
 * standard) unless explicitly opted in. `format` is the preferred format; the
 * hdrCanvas opt-in swaps it for the contract's rgba16float (effectiveCanvasFormat).
 */
export function buildCanvasConfigureOptions(
  device: GPUDevice,
  format: GPUTextureFormat,
  optIns: CanvasConfigureOptIns = {},
): GPUCanvasConfiguration {
  const usageNames = [
    ...(optIns.copySrc ? canvasConfigureContract.optIn.copySrc.usage : canvasConfigureContract.usage),
    ...(optIns.storagePresent ? canvasConfigureContract.optIn.storagePresent.usage : []),
  ];
  const config: GPUCanvasConfiguration = {
    device,
    format: effectiveCanvasFormat(format, { ...optIns, hdrCanvas: !!optIns.hdrCanvas }),
    alphaMode: canvasConfigureContract.alphaMode as GPUCanvasAlphaMode,
    usage: textureUsageBits([...new Set(usageNames)]),
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
 * Resolve the display-p3 opt-in from the URL (`?display_p3=1`) or the persisted
 * user setting (`stored`); either enables it. Extended tone mapping additionally
 * requires an HDR display (`(dynamic-range: high)`).
 */
export function resolveCanvasColorOptIns(
  search: string = typeof window !== 'undefined' ? window.location.search : '',
  isHdrDisplay: () => boolean = () =>
    typeof window !== 'undefined' &&
    typeof window.matchMedia === 'function' &&
    window.matchMedia(canvasConfigureContract.optIn.extendedToneMapping.requiresMediaQuery).matches,
  stored = false,
): Pick<CanvasConfigureOptIns, 'displayP3' | 'extendedToneMapping'> {
  const params = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  const displayP3 =
    params.get(canvasConfigureContract.optIn.displayP3.urlParam) === '1' || stored;
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
  canvas: HTMLCanvasElement | OffscreenCanvas,
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

/** Report at most one error per distinct message per window, and a global cap per minute. */
export const UNCAPTURED_ERROR_RATE_LIMIT = { perMessageMs: 5000, maxPerMinute: 20 } as const;

export function createErrorRateLimiter(
  now: () => number = () => Date.now(),
  limits: { perMessageMs: number; maxPerMinute: number } = UNCAPTURED_ERROR_RATE_LIMIT,
): (message: string) => boolean {
  const lastByMessage = new Map<string, number>();
  let windowStart = -Infinity;
  let windowCount = 0;
  return (message: string) => {
    const t = now();
    const last = lastByMessage.get(message);
    if (last !== undefined && t - last < limits.perMessageMs) return false;
    if (t - windowStart >= 60_000) {
      windowStart = t;
      windowCount = 0;
    }
    if (windowCount >= limits.maxPerMinute) return false;
    windowCount++;
    lastByMessage.set(message, t);
    if (lastByMessage.size > 200) lastByMessage.clear();
    return true;
  };
}

function isOutOfMemoryError(err: GPUError): boolean {
  const name = (err as { name?: string }).name;
  return (
    (typeof GPUOutOfMemoryError !== 'undefined' && err instanceof GPUOutOfMemoryError) ||
    name === 'GPUOutOfMemoryError' ||
    /out of memory/i.test(err.message)
  );
}

/**
 * Single `uncapturederror` listener for an adopted device: OOM goes to `onOom`, validation and
 * internal errors go to reportError (rate limited). Returns a detach function for teardown.
 */
export function attachUncapturedErrorRouter(
  device: GPUDevice,
  handlers: { onOom: () => void },
  shouldReport: (message: string) => boolean = createErrorRateLimiter(),
): () => void {
  const listener = (ev: Event) => {
    const err = (ev as GPUUncapturedErrorEvent).error;
    if (!err) return;
    if (isOutOfMemoryError(err)) {
      handlers.onOom();
      return;
    }
    const name = (err as { name?: string }).name ?? 'GPUError';
    const message = `${name}: ${err.message}`;
    if (!shouldReport(message)) return;
    reportError({ type: 'gpu-validation', message, recoverable: true });
  };
  device.addEventListener('uncapturederror', listener);
  return () => device.removeEventListener('uncapturederror', listener);
}

/** Why a device stopped; `reason` is the GPUDeviceLostInfo reason (or 'simulated'). */
export interface DeviceLostDetails {
  reason: string;
  message: string;
}

export interface DeviceLostHandlerOptions {
  /** True when a test hook destroyed the device to stand in for a real loss. */
  isSimulated?: () => boolean;
}

/**
 * Routes `device.lost`: a `'destroyed'` loss is silent and never touches the context (only
 * the device owner destroys, and its teardown already unconfigured it; a late unconfigure
 * could hit a context a newer device has since configured). A real (or simulated) loss is
 * reported as recoverable, the context is unconfigured and `onLost` runs once.
 */
export function attachDeviceLostHandler(
  device: GPUDevice,
  context: GPUCanvasContext | null,
  onLost: (details: DeviceLostDetails) => void,
  options: DeviceLostHandlerOptions = {},
): void {
  void device.lost.then((info) => {
    const simulated = info.reason === 'destroyed' && options.isSimulated?.() === true;
    if (info.reason === 'destroyed' && !simulated) return;
    const details: DeviceLostDetails = simulated
      ? { reason: 'simulated', message: 'simulated device loss (test hook)' }
      : { reason: String(info.reason ?? 'unknown'), message: info.message ?? '' };
    reportError({
      type: 'device-lost',
      message: `GPU device lost (${details.reason}) — restoring renderer…`,
      recoverable: true,
    });
    console.error('[WebGPU] Device lost:', details.reason, details.message);
    try {
      context?.unconfigure();
    } catch {
      // Ignore errors during cleanup
    }
    onLost(details);
  });
}
