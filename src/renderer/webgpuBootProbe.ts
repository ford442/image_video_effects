/**
 * WebGPU boot probe — fatal adapter ladder, swapchain + pipeline smoke test.
 * Breadcrumb: window.webgpuProbe (serializable slice without GPU handles).
 */

import { reportError, getBrowserWarning } from './ErrorHandling';
import {
  ADAPTER_ATTEMPT_LADDER,
  assertAdapterMeetsContract,
  buildRequiredLimits,
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
  parseAdapterGpuType,
  probeFormatCapabilities,
} from '../config/formatPolicy';
import { isMobileDevice } from '../config/performancePolicy';

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
  formatCapabilities: DeviceFormatCapabilities;
  adapterSummary: string;
  adapterAttemptLabel: string | null;
  /** Swapchain accepted RENDER_ATTACHMENT | COPY_SRC (configured render-only regardless). */
  canvasCopySrc: boolean;
  /** Color opt-ins actually applied to the live configure; rebuild configs with these. */
  canvasColorOptIns: Pick<CanvasConfigureOptIns, 'displayP3' | 'extendedToneMapping'>;
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
  /** Canvas swapchain accepted COPY_SRC (GPU capture without a Canvas2D roundtrip). */
  canvasCopySrc?: boolean;
  /** Applied canvas colorSpace ('srgb' unless ?display_p3=1 was accepted). */
  canvasColorSpace?: PredefinedColorSpace;
  /** Applied canvas tone mapping mode ('standard' unless extended was accepted). */
  canvasToneMapping?: 'standard' | 'extended';
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

async function readAdapterInfo(adapter: GPUAdapter): Promise<WebGpuProbeAdapterInfo | undefined> {
  try {
    const withReq = adapter as unknown as { requestAdapterInfo?: () => Promise<GPUAdapterInfo> };
    if (typeof withReq.requestAdapterInfo === 'function') {
      const info = await withReq.requestAdapterInfo();
      return {
        vendor: info.vendor,
        architecture: info.architecture,
        device: info.device,
        description: info.description,
      };
    }
    const legacy = (adapter as unknown as { info?: GPUAdapterInfo }).info;
    if (legacy) {
      return {
        vendor: legacy.vendor,
        architecture: legacy.architecture,
        device: legacy.device,
        description: legacy.description,
      };
    }
  } catch {
    /* optional */
  }
  return undefined;
}

function formatDeviceLimitsSummary(device: GPUDevice): string {
  const dl = device.limits;
  return (
    `maxTex2D=${dl.maxTextureDimension2D} storageTex=${dl.maxStorageTexturesPerShaderStage} ` +
    `computeInvocations=${dl.maxComputeInvocationsPerWorkgroup}`
  );
}

function runProbePipeline(device: GPUDevice): void {
  const module = device.createShaderModule({
    label: 'WebGpuBootProbe',
    code: PROBE_PIPELINE_WGSL,
  });
  device.createComputePipeline({
    label: 'WebGpuBootProbePipeline',
    layout: 'auto',
    compute: { module, entryPoint: 'main' },
  });
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
  const scoped =
    typeof device.pushErrorScope === 'function' && typeof device.popErrorScope === 'function';
  if (scoped) device.pushErrorScope('validation');
  let threw = false;
  try {
    context.configure(config);
  } catch {
    threw = true;
  }
  const scopeError = scoped ? await device.popErrorScope().catch(() => null) : null;
  return !threw && !scopeError;
}

/**
 * Apply ?display_p3=1 (and extended tone mapping on HDR displays) fail-soft.
 * Leaves the context configured with whatever was accepted.
 */
export async function applyCanvasColorOptIns(
  device: GPUDevice,
  context: GPUCanvasContext,
  format: GPUTextureFormat,
  requested: Pick<CanvasConfigureOptIns, 'displayP3' | 'extendedToneMapping'>,
): Promise<Pick<CanvasConfigureOptIns, 'displayP3' | 'extendedToneMapping'>> {
  const none = { displayP3: false, extendedToneMapping: false };
  if (!requested.displayP3) return none;

  const ladder = requested.extendedToneMapping
    ? [{ displayP3: true, extendedToneMapping: true }, { displayP3: true, extendedToneMapping: false }]
    : [{ displayP3: true, extendedToneMapping: false }];

  for (const optIns of ladder) {
    if (!(await tryConfigure(device, context, buildCanvasConfigureOptions(device, format, optIns)))) {
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
    return optIns;
  }

  console.warn('[WebGPU Probe] display-p3 opt-in rejected; keeping srgb canvas');
  context.configure(buildCanvasConfigureOptions(device, format));
  return none;
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
export async function runWebGpuBootProbe(
  canvas: HTMLCanvasElement,
  configWidth: number,
  configHeight: number,
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
    record.adapterInfo = await readAdapterInfo(adapter);

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
        requiredLimits: buildRequiredLimits(maxCanvasDim),
      });
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
    let canvasCopySrc: boolean;
    try {
      canvasColorOptIns = await applyCanvasColorOptIns(
        device,
        context,
        canvasFormat,
        resolveCanvasColorOptIns(),
      );
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
      runProbePipeline(device);
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
    const maxInvocations = adapter.limits?.maxComputeInvocationsPerWorkgroup ?? 256;
    const supportsDeepWorkgroup = maxInvocations >= 1024;
    const adapterGpuType = parseAdapterGpuType(
      (adapter.info as GPUAdapterInfo & { adapterType?: string })?.adapterType,
    );
    const formatCapabilities = probeFormatCapabilities(adapter, {
      isMobile: isMobileDevice(),
      device,
    });

    let adapterSummary =
      `Adapter attempt=${attempt.label} | limits: ${formatAdapterLimitsSummary(adapter)} (sufficient)`;
    adapterSummary = appendAdapterSummaryFields(adapterSummary, device, canvasFormat);
    adapterSummary +=
      ` | storage: rgba16float=${formatCapabilities.supportsRgba16FloatStorage ? 'yes' : 'no'}`
      + ` rgba32float=${formatCapabilities.supportsRgba32FloatStorage ? 'yes' : 'no'}`
      + ` float16Array=${formatCapabilities.supportsFloat16Array ? 'yes' : 'no'}`
      + ` f32filter=${formatCapabilities.hasFloat32Filterable ? 'yes' : 'no'}`
      + ` f32blend=${formatCapabilities.hasFloat32Blendable ? 'yes' : 'no'}`
      + ` | canvas: copySrc=${canvasCopySrc ? 'yes' : 'no'}`
      + ` colorSpace=${canvasColorOptIns.displayP3 ? 'display-p3' : 'srgb'}`;

    device.addEventListener('uncapturederror', (ev) => {
      console.error('[WebGPU] Uncaptured error:', (ev as GPUUncapturedErrorEvent).error);
    });

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
        formatCapabilities,
        adapterSummary,
        adapterAttemptLabel: attempt.label,
        canvasCopySrc,
        canvasColorOptIns,
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
  if (typeof window === 'undefined') return;
  window.webgpuProbe = toWebGpuProbeBreadcrumb(result);
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
