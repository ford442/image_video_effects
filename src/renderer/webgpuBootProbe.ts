/**
 * WebGPU boot probe — fatal adapter ladder, swapchain + pipeline smoke test.
 * Breadcrumb: window.webgpuProbe (serializable slice without GPU handles).
 */

import { loadDisplayP3 } from '../services/displayP3';
import { reportError, getBrowserWarning } from './ErrorHandling';
import {
  ADAPTER_ATTEMPT_LADDER,
  assertAdapterMeetsContract,
  buildRequiredLimits,
  meetsDeepWorkgroupLimits,
  formatAdapterLimitsSummary,
  logAdapterFeatures,
  type AdapterAttempt,
} from './webgpuDevicePolicy';
import {
  appendAdapterSummaryFields,
  buildCanvasConfigureOptions,
  collectOptionalDeviceFeatures,
  resolveCanvasColorOptIns,
  resolveSubgroupFeatureName,
  type CanvasConfigureOptIns,
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
  canvasFormat: GPUTextureFormat;
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
  canvasColorOptIns: Pick<CanvasConfigureOptIns, 'displayP3' | 'extendedToneMapping'>;
  /** Why the requested color opt-in was narrowed at boot (absent when honored). */
  canvasColorFallback?: CanvasColorFallbackReason;
  /**
   * Removes the probe's log-only `uncapturederror` listener. The renderer calls it when it
   * adopts the device and installs its own routed listener.
   */
  detachUncapturedLog?: () => void;
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

export type CanvasColorOptIns = Pick<CanvasConfigureOptIns, 'displayP3' | 'extendedToneMapping'>;

/** Why the applied canvas color differs from (or is narrower than) what was asked for. */
export type CanvasColorFallbackReason =
  | 'unsupported-p3'
  | 'unsupported-extended-tone-mapping'
  | 'not-hdr-display'
  /** Extended tone mapping only does anything on an rgba16float canvas (#1512). */
  | 'sdr-canvas-format';

export interface CanvasColorNegotiation {
  requested: CanvasColorOptIns;
  applied: CanvasColorOptIns;
  colorSpace: PredefinedColorSpace;
  toneMapping: 'standard' | 'extended';
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
    case 'sdr-canvas-format':
      return 'extended tone mapping needs an rgba16float canvas';
  }
}

/**
 * Negotiate display-p3 (and extended tone mapping on HDR displays) fail-soft and
 * report what was actually accepted. Leaves the context configured with the
 * accepted options (default sRGB configure when everything is rejected).
 */
export async function negotiateCanvasColor(
  device: GPUDevice,
  context: GPUCanvasContext,
  format: GPUTextureFormat,
  requested: CanvasColorOptIns,
  copySrc = false,
): Promise<CanvasColorNegotiation> {
  const result = (applied: CanvasColorOptIns, reason?: CanvasColorFallbackReason): CanvasColorNegotiation => ({
    requested,
    applied,
    colorSpace: applied.displayP3 ? 'display-p3' : 'srgb',
    toneMapping: applied.extendedToneMapping ? 'extended' : 'standard',
    ...(reason ? { reason } : {}),
  });
  const none = { displayP3: false, extendedToneMapping: false };
  if (!requested.displayP3) {
    // Switching back to default: reconfigure only if a previous call left p3 on.
    context.configure(buildCanvasConfigureOptions(device, format, { copySrc }));
    return result(none);
  }

  // An 8-bit swapchain (getPreferredCanvasFormat) clamps to [0,1], so 'extended'
  // would be accepted by configure() yet change nothing — never report it there.
  const formatCanExtend = format === 'rgba16float';
  const tryExtended = !!requested.extendedToneMapping && formatCanExtend;
  const ladder = tryExtended
    ? [{ displayP3: true, extendedToneMapping: true }, { displayP3: true, extendedToneMapping: false }]
    : [{ displayP3: true, extendedToneMapping: false }];

  for (const optIns of ladder) {
    if (!(await tryConfigure(device, context, buildCanvasConfigureOptions(device, format, { ...optIns, copySrc })))) {
      continue;
    }
    const readback = readCanvasConfiguration(context);
    if (readback) {
      if (readback.colorSpace !== 'display-p3') continue;
      if (optIns.extendedToneMapping && readback.toneMapping?.mode !== 'extended') continue;
    }
    console.log(
      `[WebGPU Probe] canvas colorSpace=display-p3 toneMapping=${optIns.extendedToneMapping ? 'extended' : 'standard'}`,
    );
    const reason: CanvasColorFallbackReason | undefined = !requested.extendedToneMapping
      ? 'not-hdr-display'
      : !formatCanExtend
        ? 'sdr-canvas-format'
        : !optIns.extendedToneMapping ? 'unsupported-extended-tone-mapping' : undefined;
    return result(optIns, reason);
  }

  console.warn('[WebGPU Probe] display-p3 opt-in rejected; keeping srgb canvas');
  context.configure(buildCanvasConfigureOptions(device, format, { copySrc }));
  return result(none, 'unsupported-p3');
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
  colorOptIns: Pick<CanvasConfigureOptIns, 'displayP3' | 'extendedToneMapping'> = {},
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
  colorOptIns?: Pick<CanvasConfigureOptIns, 'displayP3' | 'extendedToneMapping'>;
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

  for (const attempt of ADAPTER_ATTEMPT_LADDER) {
    const record: WebGpuProbeAttempt = {
      label: attempt.label,
      powerPreference: attempt.powerPreference,
      forceFallbackAdapter: attempt.forceFallbackAdapter,
      adapterPresent: false,
    };

    const options: GPURequestAdapterOptions = {
      forceFallbackAdapter: attempt.forceFallbackAdapter,
    };
    if (attempt.powerPreference !== undefined) {
      options.powerPreference = attempt.powerPreference;
    }

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
        requiredLimits: buildRequiredLimits(maxCanvasDim, adapter.limits),
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

    const canvasFormat = navigator.gpu.getPreferredCanvasFormat();
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
    let canvasColorOptIns: Pick<CanvasConfigureOptIns, 'displayP3' | 'extendedToneMapping'>;
    let canvasColorFallback: CanvasColorFallbackReason | undefined;
    let canvasCopySrc: boolean;
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
    } catch (e) {
      record.error = e instanceof Error ? e.message : String(e);
      record.failedStage = 'configure';
      device.destroy();
      logAttempt(attempt, record);
      attempts.push(record);
      continue;
    }
    console.log(`[WebGPU Probe] canvasCopySrc=${canvasCopySrc}`);

    try {
      await runProbePipeline(device);
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

    // Inside a try: a rejection here must not leak the device (it is not handed off).
    let formatCapabilities: DeviceFormatCapabilities;
    try {
      formatCapabilities = await probeFormatCapabilities(adapter, {
        isMobile: isMobileDevice(),
        device,
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
    // Granted device limits, not the adapter's: those are what shaders run under.
    const supportsDeepWorkgroup = meetsDeepWorkgroupLimits(device.limits);
    const adapterIdentity = readAdapterIdentity(adapter);
    const adapterGpuType = inferAdapterGpuType(adapterIdentity);

    // Identity first: allowsFullWorkingSize matches the Pascal blocklist against this string.
    let adapterSummary =
      `Adapter attempt=${attempt.label} | adapter: ${formatAdapterIdentity(adapterIdentity)}`
      + ` type=${adapterGpuType} | limits: ${formatAdapterLimitsSummary(adapter)} (sufficient)`;
    adapterSummary = appendAdapterSummaryFields(adapterSummary, device, canvasFormat);
    adapterSummary +=
      ` | storage: rgba16float=${formatCapabilities.supportsRgba16FloatStorage ? 'yes' : 'no'}`
      + ` rgba32float=${formatCapabilities.supportsRgba32FloatStorage ? 'yes' : 'no'}`
      + ` float16Array=${formatCapabilities.supportsFloat16Array ? 'yes' : 'no'}`
      + ` f32filter=${formatCapabilities.hasFloat32Filterable ? 'yes' : 'no'}`
      + ` f32blend=${formatCapabilities.hasFloat32Blendable ? 'yes' : 'no'}`
      + ` | canvas: copySrc=${canvasCopySrc ? 'yes' : 'no'}`
      + ` colorSpace=${canvasColorOptIns.displayP3 ? 'display-p3' : 'srgb'}`
      + ` toneMapping=${canvasColorOptIns.extendedToneMapping ? 'extended' : 'standard'}`;

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
      formatCapabilities,
    });
    serializable.ok = true;

    return {
      ...serializable,
      handoff: {
        device,
        context,
        canvasFormat,
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
      },
    };
  }

  const last = attempts[attempts.length - 1];
  const lastStage = last?.failedStage ?? 'requestAdapter';
  const lastError =
    last?.error && lastStage !== 'requestAdapter'
      ? last.error
      : 'Failed to obtain a WebGPU adapter after all fallback attempts ' +
        '(HighPerformance/Undefined/LowPower/forceFallbackAdapter).';
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
export function updateWebGpuProbeColor(result: CanvasColorNegotiation): void {
  if (typeof window === 'undefined' || !window.webgpuProbe) return;
  const { canvasColorFallback: _drop, ...rest } = window.webgpuProbe;
  window.webgpuProbe = {
    ...rest,
    canvasColorSpace: result.colorSpace,
    canvasToneMapping: result.toneMapping,
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
