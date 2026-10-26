/**
 * WebGPU boot probe — fatal adapter ladder, swapchain + pipeline smoke test.
 * Breadcrumb: window.webgpuProbe (serializable slice without GPU handles).
 */

import { loadDisplayP3 } from '../services/displayP3';
import { reportError, getBrowserWarning } from './ErrorHandling';
import {
  assertAdapterMeetsContract,
  buildRequiredLimits,
  isCompatibilityDevice,
  meetsDeepWorkgroupLimits,
  formatAdapterLimitsSummary,
  logAdapterFeatures,
  resolveAdapterLadder,
  resolveLimitsTiers,
  type AdapterAttempt,
  type FeatureLevel,
  type LimitsTier,
} from './webgpuDevicePolicy';
import {
  appendAdapterSummaryFields,
  buildCanvasConfigureOptions,
  collectOptionalDeviceFeatures,
  effectiveCanvasFormat,
  readDeviceTier2,
  resolveCanvasColorOptIns,
  resolveCanvasFormatOverride,
  resolveSubgroupFeatureName,
  storagePresentDisabledByUrl,
  type CanvasColorOptInsState,
  type CanvasConfigureOptIns,
  type DeviceTier2,
} from './webgpu/device';
import {
  AdapterGpuType,
  DeviceFormatCapabilities,
  probeFormatCapabilities,
} from '../config/formatPolicy';
import {
  formatAdapterIdentity,
  inferAdapterGpuType,
  readAdapterIdentity,
  type AdapterIdentity,
} from '../config/adapterIdentity';
import { isMobileDevice } from '../config/performancePolicy';
import { describeScopeFailure, scopeFailed, withValidationScope } from './webgpu/validationScope';

export type WebGpuProbeStage =
  | 'requestAdapter'
  | 'contract'
  | 'requestDevice'
  | 'getContext'
  | 'configure'
  | 'probePipeline';

export type WebGpuProbeAdapterInfo = {
  vendor?: string;
  architecture?: string;
  device?: string;
  description?: string;
};

export type WebGpuProbeAttempt = {
  label: string;
  powerPreference?: GPUPowerPreference;
  forceFallbackAdapter: boolean;
  /** Set on the compatibility rung (#1512). */
  featureLevel?: FeatureLevel;
  adapterPresent: boolean;
  adapterInfo?: WebGpuProbeAdapterInfo;
  limitsSummary?: string;
  deviceLimitsSummary?: string;
  error?: string;
  failedStage?: WebGpuProbeStage;
};

/** Live GPU handles — not stored on window.webgpuProbe. */
export type WebGpuProbeHandoff = {
  device: GPUDevice;
  context: GPUCanvasContext;
  /** The applied swapchain format: rgba16float for an HDR canvas, else the preferred one. */
  canvasFormat: GPUTextureFormat;
  /** getPreferredCanvasFormat() (or ?canvas_format=): every SDR configure uses it. */
  preferredCanvasFormat?: GPUTextureFormat;
  /** The swapchain was accepted with STORAGE_BINDING for the compute present (#1512). */
  storagePresent?: boolean;
  canvasW: number;
  canvasH: number;
  supportsSubgroups: boolean;
  supportsDeepWorkgroup: boolean;
  hasF32Filterable: boolean;
  adapterGpuType: AdapterGpuType;
  /** From `adapter.info`; drives the 2048 gate (fallback, Pascal blocklist). */
  adapterIdentity: AdapterIdentity;
  formatCapabilities: DeviceFormatCapabilities;
  adapterSummary: string;
  adapterAttemptLabel: string | null;
  /** Swapchain accepted RENDER_ATTACHMENT | COPY_SRC (configured render-only regardless). */
  canvasCopySrc: boolean;
  /** Color opt-ins actually applied to the live configure; rebuild configs with these. */
  canvasColorOptIns: CanvasColorOptInsState;
  /** Why the requested color opt-in was narrowed at boot (absent when honored). */
  canvasColorFallback?: CanvasColorFallbackReason;
  /**
   * Removes the probe's log-only `uncapturederror` listener. The renderer calls it when it
   * adopts the device and installs its own routed listener.
   */
  detachUncapturedLog?: () => void;
  /** Capability tier 2 (#1512); absent on handoffs built before it existed (treated as core). */
  tier2?: DeviceTier2;
};

export type WebGpuProbeSerializable = {
  ok: boolean;
  finishedAt: string;
  userAgent: string;
  userAgentBrands: Array<{ brand: string; version: string }>;
  attempts: WebGpuProbeAttempt[];
  failedStage?: WebGpuProbeStage;
  lastError?: string;
  adapterSummary?: string;
  adapterAttemptLabel?: string | null;
  backend?: 'webgpu' | 'wasm';
  /** Where the TS backend renders: the page ('main') or the render worker (#1314). */
  renderThread?: 'main' | 'worker';
  /** Canvas swapchain accepted COPY_SRC (GPU capture without a Canvas2D roundtrip). */
  canvasCopySrc?: boolean;
  /** Applied canvas colorSpace ('srgb' unless ?display_p3=1 was accepted). */
  canvasColorSpace?: PredefinedColorSpace;
  /** Applied canvas tone mapping mode ('standard' unless extended was accepted). */
  canvasToneMapping?: 'standard' | 'extended';
  /** Why the requested display-p3 / extended tone mapping was narrowed (absent when honored). */
  canvasColorFallback?: CanvasColorFallbackReason;
  /** Applied canvas format: getPreferredCanvasFormat(), or rgba16float for an HDR canvas (#1512). */
  canvasFormat?: GPUTextureFormat;
  /** The present writes the bgra8unorm swapchain from a compute pass (canvas_configure optIn.storagePresent). */
  storagePresent?: boolean;
  /** Capability tier 2 (#1512): the feature level the device runs at and its granted features. */
  featureLevel?: FeatureLevel;
  /** The device came from the compatibility rung and validates as compat. */
  compat?: boolean;
  shaderF16?: boolean;
  bgra8unormStorage?: boolean;
  float32Blendable?: boolean;
  dualSourceBlending?: boolean;
  /** Every limits tier the granted device limits reach (webgpu_limits.json limitsTiers). */
  limitsTiers?: LimitsTier[];
  /**
   * Colour tag of the most recent WebCodecs recording: 'display-p3' when its WebM
   * Colour element was rewritten to P3 primaries, 'encoder-default' when the file
   * keeps the encoder's own tag (Chromium: smpte170m). Absent before any take.
   */
  recordingColorTag?: 'display-p3' | 'encoder-default';
  formatCapabilities?: Pick<
    DeviceFormatCapabilities,
    | 'adapterGpuType'
    | 'isMobile'
    | 'supportsRgba32FloatStorage'
    | 'supportsRgba16FloatStorage'
    | 'supportsFloat16Array'
    | 'hasFloat32Filterable'
    | 'hasFloat32Blendable'
  >;
};

export type WebGpuProbeResult = WebGpuProbeSerializable & {
  handoff?: WebGpuProbeHandoff;
};

const PROBE_PIPELINE_WGSL = '@compute @workgroup_size(1) fn main() {}';

/**
 * Devices this thread's probe created whose `lost` has not settled yet. The probe is the
 * only requestDevice caller (deviceOwnership.test.ts), so this is every live GPUDevice on
 * the thread: after a loss + recovery it must be back to 1 (#1395).
 */
let liveDeviceCount = 0;

export function getLiveDeviceCount(): number {
  return liveDeviceCount;
}

function trackLiveDevice(device: GPUDevice): void {
  liveDeviceCount++;
  void device.lost?.then(
    () => { liveDeviceCount--; },
    () => { liveDeviceCount--; },
  );
}

export function collectUserAgentBrands(): Array<{ brand: string; version: string }> {
  try {
    const nav = navigator as Navigator & {
      userAgentData?: { brands?: Array<{ brand: string; version: string }> };
    };
    if (nav.userAgentData?.brands?.length) {
      return nav.userAgentData.brands.map((b) => ({ brand: b.brand, version: b.version }));
    }
  } catch {
    /* non-browser */
  }
  return [];
}

function readAdapterInfo(adapter: GPUAdapter): WebGpuProbeAdapterInfo | undefined {
  const id = readAdapterIdentity(adapter);
  if (!id.vendor && !id.architecture && !id.device && !id.description) return undefined;
  return {
    vendor: id.vendor,
    architecture: id.architecture,
    device: id.device,
    description: id.description,
  };
}

function formatDeviceLimitsSummary(device: GPUDevice): string {
  const dl = device.limits;
  return (
    `maxTex2D=${dl.maxTextureDimension2D} storageTex=${dl.maxStorageTexturesPerShaderStage} ` +
    `computeInvocations=${dl.maxComputeInvocationsPerWorkgroup}`
  );
}

/**
 * Compile a trivial compute pipeline. Validation errors arrive asynchronously, so
 * a try/catch alone never saw them (#1395): scope the module and use the async
 * create, which rejects with a GPUPipelineError instead of yielding an invalid pipeline.
 * Throws with the failure message so the caller records failedStage 'probePipeline'.
 */
async function runProbePipeline(device: GPUDevice): Promise<void> {
  const result = await withValidationScope(device, () => {
    const module = device.createShaderModule({
      label: 'WebGpuBootProbe',
      code: PROBE_PIPELINE_WGSL,
    });
    const descriptor: GPUComputePipelineDescriptor = {
      label: 'WebGpuBootProbePipeline',
      layout: 'auto',
      compute: { module, entryPoint: 'main' },
    };
    return typeof device.createComputePipelineAsync === 'function'
      ? device.createComputePipelineAsync(descriptor)
      : device.createComputePipeline(descriptor);
  });
  const failure = describeScopeFailure(result);
  if (failure) throw new Error(failure);
}

type CanvasConfigurationReadback = GPUCanvasConfiguration & {
  toneMapping?: { mode?: string };
};

function readCanvasConfiguration(context: GPUCanvasContext): CanvasConfigurationReadback | null {
  const withGet = context as GPUCanvasContext & {
    getConfiguration?: () => CanvasConfigurationReadback | null;
  };
  if (typeof withGet.getConfiguration !== 'function') return null;
  try {
    return withGet.getConfiguration();
  } catch {
    return null;
  }
}

/**
 * Configure inside a validation error scope. Usage/colorSpace rejections may be
 * thrown synchronously or surface as device validation errors; both count as
 * rejected. Devices without error scopes (mocks) rely on the throw only.
 */
async function tryConfigure(
  device: GPUDevice,
  context: GPUCanvasContext,
  config: GPUCanvasConfiguration,
): Promise<boolean> {
  return !scopeFailed(await withValidationScope(device, () => context.configure(config)));
}

export type CanvasColorOptIns = CanvasColorOptInsState;

/** Why the applied canvas color differs from (or is narrower than) what was asked for. */
export type CanvasColorFallbackReason =
  | 'unsupported-p3'
  | 'unsupported-extended-tone-mapping'
  | 'not-hdr-display';

export interface CanvasColorNegotiation {
  requested: CanvasColorOptIns;
  applied: CanvasColorOptIns;
  colorSpace: PredefinedColorSpace;
  toneMapping: 'standard' | 'extended';
  /** The swapchain format the applied configure uses (rgba16float when HDR, #1512). */
  format?: GPUTextureFormat;
  /** Set when the request was narrowed; absent when fully honored (or nothing requested). */
  reason?: CanvasColorFallbackReason;
}

/** Result of a live toggle; `deferred` means nothing changed (capture in progress). */
export interface DisplayP3Result extends CanvasColorNegotiation {
  deferred?: boolean;
}

/** Live canvas color state for diagnostics. */
export interface CanvasColorState {
  requestedDisplayP3: boolean;
  colorSpace: PredefinedColorSpace;
  toneMapping: 'standard' | 'extended';
  copySrc: boolean;
  /** The live swapchain format (#1512). */
  format?: GPUTextureFormat;
  /** The present is the bgra8unorm compute write (#1512). */
  storagePresent?: boolean;
  fallbackReason?: CanvasColorFallbackReason;
}

export function describeCanvasColorFallback(reason: CanvasColorFallbackReason): string {
  switch (reason) {
    case 'unsupported-p3':
      return 'this browser/display rejected Display P3';
    case 'unsupported-extended-tone-mapping':
      return 'extended tone mapping was rejected';
    case 'not-hdr-display':
      return 'not an HDR display, extended tone mapping skipped';
  }
}

/** Usage opt-ins kept across a colour renegotiation (they never change the colour). */
export type CanvasUsageOptIns = Pick<CanvasConfigureOptIns, 'copySrc' | 'storagePresent'>;

/**
 * Negotiate display-p3 (and extended tone mapping on HDR displays) fail-soft and
 * report what was actually accepted. Leaves the context configured with the
 * accepted options (default sRGB configure when everything is rejected).
 *
 * Extended tone mapping only changes anything on a float16 swapchain, so it is
 * negotiated together with the rgba16float HDR canvas (#1512 optIn.hdrCanvas) and
 * never reported as applied on the 8-bit preferred format. `format` is the
 * preferred format; the result's `format` is what the swapchain uses now.
 */
export async function negotiateCanvasColor(
  device: GPUDevice,
  context: GPUCanvasContext,
  format: GPUTextureFormat,
  requested: CanvasColorOptIns,
  usage: boolean | CanvasUsageOptIns = false,
): Promise<CanvasColorNegotiation> {
  const kept: CanvasUsageOptIns = typeof usage === 'boolean' ? { copySrc: usage } : usage;
  const result = (applied: CanvasColorOptIns, reason?: CanvasColorFallbackReason): CanvasColorNegotiation => ({
    requested,
    applied,
    colorSpace: applied.displayP3 ? 'display-p3' : 'srgb',
    toneMapping: applied.extendedToneMapping ? 'extended' : 'standard',
    format: effectiveCanvasFormat(format, applied),
    ...(reason ? { reason } : {}),
  });
  const none = { displayP3: false, extendedToneMapping: false };
  if (!requested.displayP3) {
    // Switching back to default: reconfigure only if a previous call left p3 on.
    context.configure(buildCanvasConfigureOptions(device, format, kept));
    return result(none);
  }

  const ladder: CanvasColorOptIns[] = requested.extendedToneMapping
    ? [{ displayP3: true, extendedToneMapping: true, hdrCanvas: true }, { displayP3: true, extendedToneMapping: false }]
    : [{ displayP3: true, extendedToneMapping: false }];

  for (const optIns of ladder) {
    // The compute present writes bgra8unorm only: an HDR canvas presents through the render pass.
    const usageOptIns = optIns.hdrCanvas ? { copySrc: kept.copySrc } : kept;
    if (!(await tryConfigure(device, context, buildCanvasConfigureOptions(device, format, { ...optIns, ...usageOptIns })))) {
      continue;
    }
    const readback = readCanvasConfiguration(context);
    if (readback) {
      if (readback.colorSpace !== 'display-p3') continue;
      if (optIns.extendedToneMapping && readback.toneMapping?.mode !== 'extended') continue;
      if (optIns.hdrCanvas && readback.format !== undefined && readback.format !== effectiveCanvasFormat(format, optIns)) continue;
    }
    console.log(
      `[WebGPU Probe] canvas colorSpace=display-p3 toneMapping=${optIns.extendedToneMapping ? 'extended' : 'standard'}`,
    );
    const reason = requested.extendedToneMapping && !optIns.extendedToneMapping
      ? 'unsupported-extended-tone-mapping'
      : !requested.extendedToneMapping ? 'not-hdr-display' : undefined;
    return result(optIns, reason);
  }

  console.warn('[WebGPU Probe] display-p3 opt-in rejected; keeping srgb canvas');
  context.configure(buildCanvasConfigureOptions(device, format, kept));
  return result(none, 'unsupported-p3');
}

/**
 * Probe whether the swapchain accepts STORAGE_BINDING for the compute present (#1512):
 * only with the bgra8unorm-storage feature, a bgra8unorm SDR canvas, and not turned off
 * by ?storage_present=0. Leaves it configured with the storage usage when accepted, and
 * with `colorOptIns` either way. Never throws.
 */
export async function probeStoragePresent(
  device: GPUDevice,
  context: GPUCanvasContext,
  format: GPUTextureFormat,
  colorOptIns: CanvasColorOptIns,
  search = '',
): Promise<boolean> {
  const eligible = device.features.has('bgra8unorm-storage' as GPUFeatureName)
    && effectiveCanvasFormat(format, colorOptIns) === 'bgra8unorm'
    && !storagePresentDisabledByUrl(search);
  if (!eligible) return false;
  try {
    if (await tryConfigure(device, context, buildCanvasConfigureOptions(device, format, { ...colorOptIns, storagePresent: true }))) {
      const readback = readCanvasConfiguration(context);
      const storageBit = typeof GPUTextureUsage !== 'undefined' ? GPUTextureUsage.STORAGE_BINDING : 0x08;
      if (!readback || typeof readback.usage !== 'number' || (readback.usage & storageBit)) return true;
    }
  } catch {
    /* fall through to the render-pass present */
  }
  context.configure(buildCanvasConfigureOptions(device, format, colorOptIns));
  return false;
}

/**
 * Apply ?display_p3=1 / the persisted setting fail-soft. Boot-time wrapper over
 * negotiateCanvasColor that returns only the accepted opt-ins.
 */
export async function applyCanvasColorOptIns(
  device: GPUDevice,
  context: GPUCanvasContext,
  format: GPUTextureFormat,
  requested: CanvasColorOptIns,
): Promise<CanvasColorOptIns> {
  if (!requested.displayP3) return { displayP3: false, extendedToneMapping: false };
  return (await negotiateCanvasColor(device, context, format, requested)).applied;
}

/**
 * Probe whether the swapchain accepts RENDER_ATTACHMENT | COPY_SRC, then restore
 * the render-only configure (keeping color opt-ins). Never throws.
 */
export async function probeCanvasCopySrc(
  device: GPUDevice,
  context: GPUCanvasContext,
  format: GPUTextureFormat,
  colorOptIns: CanvasColorOptIns = {},
): Promise<boolean> {
  let accepted = false;
  try {
    accepted = await tryConfigure(
      device,
      context,
      buildCanvasConfigureOptions(device, format, { ...colorOptIns, copySrc: true }),
    );
    if (accepted) {
      const readback = readCanvasConfiguration(context);
      const copySrcBit = typeof GPUTextureUsage !== 'undefined' ? GPUTextureUsage.COPY_SRC : 0x01;
      if (readback && typeof readback.usage === 'number' && !(readback.usage & copySrcBit)) {
        accepted = false;
      }
    }
  } catch {
    accepted = false;
  }
  context.configure(buildCanvasConfigureOptions(device, format, colorOptIns));
  return accepted;
}

function baseSerializable(
  attempts: WebGpuProbeAttempt[],
  extra: Partial<WebGpuProbeSerializable> = {},
): WebGpuProbeSerializable {
  return {
    ok: false,
    finishedAt: new Date().toISOString(),
    userAgent: typeof navigator !== 'undefined' ? navigator.userAgent : '',
    userAgentBrands: collectUserAgentBrands(),
    attempts,
    ...extra,
  };
}

function logAttempt(attempt: AdapterAttempt, record: WebGpuProbeAttempt): void {
  const pref = attempt.powerPreference ?? 'default';
  const summary = record.limitsSummary ?? 'no adapter';
  const err = record.error ? ` error=${record.error}` : '';
  console.log(
    `[WebGPU Probe] attempt=${record.label} powerPreference=${pref} ` +
      `forceFallback=${record.forceFallbackAdapter} adapter=${record.adapterPresent} ` +
      `${summary}${err}`,
  );
}

/**
 * Walk ADAPTER_ATTEMPT_LADDER with per-rung logging. Each rung may fail at
 * adapter acquisition, contract, device, surface, or pipeline compile.
 */
export interface WebGpuProbeOptions {
  /**
   * Display-P3 / extended tone-mapping opt-ins. Defaults to the page URL +
   * HDR media query; a worker cannot see either, so the render worker (#1314)
   * passes the main thread's answer.
   */
  colorOptIns?: CanvasColorOptIns;
  /**
   * The page's `location.search` for probe flags (#1512): `?feature_level=compatibility`
   * starts at the compat rung, `?canvas_format=bgra8unorm|rgba8unorm` overrides the
   * preferred canvas format, `?storage_present=0` keeps the render-pass present. Defaults
   * to this realm's location; the render worker passes the page's.
   */
  search?: string;
}

export async function runWebGpuBootProbe(
  canvas: HTMLCanvasElement | OffscreenCanvas,
  configWidth: number,
  configHeight: number,
  probeOptions: WebGpuProbeOptions = {},
): Promise<WebGpuProbeResult> {
  const attempts: WebGpuProbeAttempt[] = [];

  if (!navigator.gpu) {
    const warning = getBrowserWarning();
    const message = warning || 'WebGPU is not available in this browser';
    reportError({ type: 'webgpu-unavailable', message, recoverable: false });
    console.warn('[WebGPU Probe] navigator.gpu unavailable');
    return {
      ...baseSerializable(attempts, {
        failedStage: 'requestAdapter',
        lastError: message,
      }),
    };
  }

  const canvasW = canvas.width || configWidth;
  const canvasH = canvas.height || configHeight;
  const maxCanvasDim = Math.max(canvasW, canvasH, 1);

  const search = probeOptions.search ?? (typeof location !== 'undefined' ? location.search : '');
  const ladder: readonly AdapterAttempt[] = resolveAdapterLadder(search);
  for (const attempt of ladder) {
    const record: WebGpuProbeAttempt = {
      label: attempt.label,
      powerPreference: attempt.powerPreference,
      forceFallbackAdapter: attempt.forceFallbackAdapter,
      adapterPresent: false,
      ...(attempt.featureLevel ? { featureLevel: attempt.featureLevel } : {}),
    };

    const options: GPURequestAdapterOptions = {
      forceFallbackAdapter: attempt.forceFallbackAdapter,
    };
    if (attempt.powerPreference !== undefined) {
      options.powerPreference = attempt.powerPreference;
    }
    if (attempt.featureLevel) options.featureLevel = attempt.featureLevel;

    let adapter: GPUAdapter | null = null;
    try {
      adapter = await navigator.gpu.requestAdapter(options);
    } catch (e) {
      record.error = e instanceof Error ? e.message : String(e);
      record.failedStage = 'requestAdapter';
      logAttempt(attempt, record);
      attempts.push(record);
      continue;
    }

    if (!adapter) {
      record.error = 'requestAdapter returned null';
      record.failedStage = 'requestAdapter';
      logAttempt(attempt, record);
      attempts.push(record);
      continue;
    }

    record.adapterPresent = true;
    record.limitsSummary = formatAdapterLimitsSummary(adapter);
    record.adapterInfo = readAdapterInfo(adapter);

    const contract = assertAdapterMeetsContract(adapter, { maxCanvasDim });
    if (!contract.ok) {
      record.error = contract.failures.join('; ');
      record.failedStage = 'contract';
      logAttempt(attempt, record);
      attempts.push(record);
      continue;
    }

    logAdapterFeatures(adapter);

    const wantFeatures = collectOptionalDeviceFeatures(adapter);
    const subgroupFeatureName = resolveSubgroupFeatureName(adapter);

    let device: GPUDevice;
    try {
      device = await adapter.requestDevice({
        label: 'PixelocityDevice',
        requiredFeatures: wantFeatures,
        requiredLimits: buildRequiredLimits(maxCanvasDim, adapter.limits, attempt.featureLevel ?? 'core'),
      });
      trackLiveDevice(device);
    } catch (e) {
      record.error = e instanceof Error ? e.message : String(e);
      record.failedStage = 'requestDevice';
      logAttempt(attempt, record);
      attempts.push(record);
      continue;
    }

    record.deviceLimitsSummary = formatDeviceLimitsSummary(device);

    const context = canvas.getContext('webgpu') as GPUCanvasContext | null;
    if (!context) {
      record.error = 'Failed to get webgpu canvas context';
      record.failedStage = 'getContext';
      device.destroy();
      logAttempt(attempt, record);
      attempts.push(record);
      continue;
    }

    // ?canvas_format= forces bgra8unorm (storage present) where the preferred one is rgba8unorm.
    const canvasFormat = resolveCanvasFormatOverride(search) ?? navigator.gpu.getPreferredCanvasFormat();
    try {
      try {
        context.unconfigure();
      } catch {
        /* not configured yet */
      }
      context.configure(buildCanvasConfigureOptions(device, canvasFormat));
    } catch (e) {
      record.error = e instanceof Error ? e.message : String(e);
      record.failedStage = 'configure';
      device.destroy();
      logAttempt(attempt, record);
      attempts.push(record);
      continue;
    }

    // Opt-ins are fail-soft: a rejection restores the default configure and
    // never fails the rung. A throw from the restore itself is a configure failure.
    let canvasColorOptIns: CanvasColorOptIns;
    let canvasColorFallback: CanvasColorFallbackReason | undefined;
    let canvasCopySrc: boolean;
    let storagePresent = false;
    try {
      const requestedColor =
        probeOptions.colorOptIns ?? resolveCanvasColorOptIns(undefined, undefined, loadDisplayP3());
      if (requestedColor.displayP3) {
        const negotiated = await negotiateCanvasColor(device, context, canvasFormat, requestedColor);
        canvasColorOptIns = negotiated.applied;
        canvasColorFallback = negotiated.reason;
      } else {
        canvasColorOptIns = { displayP3: false, extendedToneMapping: false };
      }
      canvasCopySrc = await probeCanvasCopySrc(device, context, canvasFormat, canvasColorOptIns);
      storagePresent = await probeStoragePresent(device, context, canvasFormat, canvasColorOptIns, search);
    } catch (e) {
      record.error = e instanceof Error ? e.message : String(e);
      record.failedStage = 'configure';
      device.destroy();
      logAttempt(attempt, record);
      attempts.push(record);
      continue;
    }
    console.log(`[WebGPU Probe] canvasCopySrc=${canvasCopySrc} storagePresent=${storagePresent}`);
    const presentFormat = effectiveCanvasFormat(canvasFormat, canvasColorOptIns);

    let formatCapabilities: DeviceFormatCapabilities;
    try {
      await runProbePipeline(device);
      // Inside the try: a rejection here must destroy the device like any other failed rung.
      formatCapabilities = await probeFormatCapabilities(adapter, {
        isMobile: isMobileDevice(),
        device,
        compat: isCompatibilityDevice(device, attempt.featureLevel),
      });
    } catch (e) {
      record.error = e instanceof Error ? e.message : String(e);
      record.failedStage = 'probePipeline';
      try {
        context.unconfigure();
      } catch {
        /* ignore */
      }
      device.destroy();
      logAttempt(attempt, record);
      attempts.push(record);
      continue;
    }

    logAttempt(attempt, record);
    attempts.push(record);

    const supportsSubgroups = !!(subgroupFeatureName && device.features.has(subgroupFeatureName));
    const tier2 = readDeviceTier2(
      device,
      attempt.featureLevel ?? 'core',
      isCompatibilityDevice(device, attempt.featureLevel),
      resolveLimitsTiers(device.limits),
    );
    // Granted device limits, not the adapter's: those are what shaders run under.
    const supportsDeepWorkgroup = meetsDeepWorkgroupLimits(device.limits);
    const adapterIdentity = readAdapterIdentity(adapter);
    const adapterGpuType = inferAdapterGpuType(adapterIdentity);

    // Identity first: allowsFullWorkingSize matches the Pascal blocklist against this string.
    let adapterSummary =
      `Adapter attempt=${attempt.label} | adapter: ${formatAdapterIdentity(adapterIdentity)}`
      + ` type=${adapterGpuType} | limits: ${formatAdapterLimitsSummary(adapter)} (sufficient)`;
    adapterSummary = appendAdapterSummaryFields(adapterSummary, device, presentFormat);
    adapterSummary +=
      ` | storage: rgba16float=${formatCapabilities.supportsRgba16FloatStorage ? 'yes' : 'no'}`
      + ` rgba32float=${formatCapabilities.supportsRgba32FloatStorage ? 'yes' : 'no'}`
      + ` float16Array=${formatCapabilities.supportsFloat16Array ? 'yes' : 'no'}`
      + ` f32filter=${formatCapabilities.hasFloat32Filterable ? 'yes' : 'no'}`
      + ` f32blend=${formatCapabilities.hasFloat32Blendable ? 'yes' : 'no'}`
      + ` | tier2: level=${tier2.compat ? 'compatibility' : 'core'} f16=${tier2.shaderF16 ? 'yes' : 'no'}`
      + ` bgra8storage=${tier2.bgra8unormStorage ? 'yes' : 'no'} dualSource=${tier2.dualSourceBlending ? 'yes' : 'no'}`
      + ` limitsTiers=${tier2.limitsTiers.join(',') || 'none'}`
      + ` | canvas: copySrc=${canvasCopySrc ? 'yes' : 'no'}`
      + ` colorSpace=${canvasColorOptIns.displayP3 ? 'display-p3' : 'srgb'}`
      + ` toneMapping=${canvasColorOptIns.extendedToneMapping ? 'extended' : 'standard'}`
      + ` storagePresent=${storagePresent ? 'yes' : 'no'}`;

    const logUncaptured = (ev: Event) => {
      console.error('[WebGPU] Uncaptured error:', (ev as GPUUncapturedErrorEvent).error);
    };
    device.addEventListener('uncapturederror', logUncaptured);
    const detachUncapturedLog = () => device.removeEventListener('uncapturederror', logUncaptured);

    console.log('[WebGPU Probe] Boot probe succeeded:', adapterSummary);

    const serializable = baseSerializable(attempts, {
      ok: true,
      failedStage: undefined,
      lastError: undefined,
      adapterSummary,
      adapterAttemptLabel: attempt.label,
      backend: 'webgpu',
      canvasCopySrc,
      canvasColorSpace: canvasColorOptIns.displayP3 ? 'display-p3' : 'srgb',
      canvasToneMapping: canvasColorOptIns.extendedToneMapping ? 'extended' : 'standard',
      ...(canvasColorFallback ? { canvasColorFallback } : {}),
      canvasFormat: presentFormat,
      storagePresent,
      featureLevel: tier2.compat ? 'compatibility' : 'core',
      compat: tier2.compat,
      shaderF16: tier2.shaderF16,
      bgra8unormStorage: tier2.bgra8unormStorage,
      float32Blendable: tier2.float32Blendable,
      dualSourceBlending: tier2.dualSourceBlending,
      limitsTiers: tier2.limitsTiers,
      formatCapabilities,
    });
    serializable.ok = true;

    return {
      ...serializable,
      handoff: {
        device,
        context,
        canvasFormat: presentFormat,
        preferredCanvasFormat: canvasFormat,
        storagePresent,
        canvasW,
        canvasH,
        supportsSubgroups,
        supportsDeepWorkgroup,
        hasF32Filterable: device.features.has('float32-filterable'),
        adapterGpuType,
        adapterIdentity,
        formatCapabilities,
        adapterSummary,
        adapterAttemptLabel: attempt.label,
        canvasCopySrc,
        canvasColorOptIns,
        canvasColorFallback,
        detachUncapturedLog,
        tier2,
      },
    };
  }

  const last = attempts[attempts.length - 1];
  const lastStage = last?.failedStage ?? 'requestAdapter';
  const lastError =
    last?.error && lastStage !== 'requestAdapter'
      ? last.error
      : 'Failed to obtain a WebGPU adapter after all fallback attempts ' +
        `(${ladder.map((a) => a.label).join('/')}).`;
  reportError({ type: 'webgpu-unavailable', message: lastError, recoverable: false });
  console.warn('[WebGPU Probe]', lastError);

  return {
    ...baseSerializable(attempts, {
      failedStage: lastStage,
      lastError,
      backend: 'webgpu',
    }),
  };
}

/** Strip GPU handles for window.webgpuProbe breadcrumb. */
export function toWebGpuProbeBreadcrumb(result: WebGpuProbeResult): WebGpuProbeSerializable {
  const { handoff: _h, ...rest } = result;
  return rest;
}

export function publishWebGpuProbe(result: WebGpuProbeResult): void {
  publishWebGpuProbeBreadcrumb(toWebGpuProbeBreadcrumb(result));
}

/** Publish an already-serialized breadcrumb (e.g. one posted back by the render worker). */
export function publishWebGpuProbeBreadcrumb(breadcrumb: WebGpuProbeSerializable): void {
  if (typeof window === 'undefined') return;
  window.webgpuProbe = breadcrumb;
}

/** Reflect a live color renegotiation in window.webgpuProbe (no-op before the first publish). */
export function updateWebGpuProbeColor(result: CanvasColorNegotiation, storagePresent?: boolean): void {
  if (typeof window === 'undefined' || !window.webgpuProbe) return;
  const { canvasColorFallback: _drop, ...rest } = window.webgpuProbe;
  window.webgpuProbe = {
    ...rest,
    canvasColorSpace: result.colorSpace,
    canvasToneMapping: result.toneMapping,
    ...(result.format ? { canvasFormat: result.format } : {}),
    ...(storagePresent !== undefined ? { storagePresent } : {}),
    ...(result.reason ? { canvasColorFallback: result.reason } : {}),
  };
}

/**
 * WASM init success breadcrumb. ?renderer=wasm skips the TS boot probe, so this is
 * the only window.webgpuProbe on that path; canvasCopySrc is the C++ swapchain
 * probe (canvas_configure.json optIn.copySrc), omitted when the artifact predates it.
 */
export function publishWasmProbeSuccess(
  adapterSummary: string,
  canvasCopySrc: boolean | null,
): void {
  if (typeof window === 'undefined') return;
  window.webgpuProbe = {
    ...baseSerializable([], {
      ok: true,
      adapterSummary: adapterSummary || undefined,
      backend: 'wasm',
      ...(canvasCopySrc === null ? {} : { canvasCopySrc }),
    }),
  };
}

/** WASM init failure breadcrumb when ?renderer=wasm hard-fails. */
export function publishWasmProbeFailure(
  lastError: string,
  adapterSummary = '',
  attempts: WebGpuProbeAttempt[] = [],
): void {
  if (typeof window === 'undefined') return;
  window.webgpuProbe = {
    ...baseSerializable(attempts, {
      failedStage: 'requestDevice',
      lastError,
      adapterSummary: adapterSummary || undefined,
      backend: 'wasm',
    }),
  };
}
