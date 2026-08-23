/**
 * Internal color storage format tiers — see docs/FORMAT_TIERS.md.
 * Keep numeric / enum mapping in sync with wasm_renderer/performance_policy.h.
 */

import type { RenderQualityMode } from './performancePolicy';

export type InternalColorFormat = 'rgba32float' | 'rgba16float';

export type AdapterGpuType = 'discrete' | 'integrated' | 'cpu' | 'unknown';

export interface DeviceFormatCapabilities {
  adapterGpuType: AdapterGpuType;
  isMobile: boolean;
  /** Measured 1×1 STORAGE_BINDING create of rgba32float (never assumed). */
  supportsRgba32FloatStorage: boolean;
  /** Measured 1×1 STORAGE_BINDING create of rgba16float. */
  supportsRgba16FloatStorage: boolean;
  /** Platform Float16Array — used for CPU uploads; missing ⇒ fail-soft FP32. */
  supportsFloat16Array: boolean;
  hasFloat32Filterable: boolean;
  hasFloat32Blendable: boolean;
}

export const ULTRA_COLOR_FORMAT: InternalColorFormat = 'rgba32float';
export const BALANCED_COLOR_FORMAT: InternalColorFormat = 'rgba16float';
export const BATTERY_COLOR_FORMAT: InternalColorFormat = 'rgba16float';

/** rgba targets at sim resolution (read, write, dataA/B/C, history) + full-res source. */
export const RGBA_INTERNAL_TARGET_COUNT = 7;

export function hasFloat16Array(): boolean {
  return typeof (globalThis as unknown as { Float16Array?: unknown }).Float16Array === 'function';
}

/** IEEE-754 binary16 bits from an f32 (no Float16Array required). */
export function floatToHalfBits(value: number): number {
  const f32 = new Float32Array(1);
  const u32 = new Uint32Array(f32.buffer);
  f32[0] = value;
  const x = u32[0];
  const sign = (x >>> 16) & 0x8000;
  const exp = (x >>> 23) & 0xff;
  const mant = x & 0x7fffff;

  if (exp === 255) {
    if (mant === 0) return sign | 0x7c00;
    return sign | 0x7c00 | (mant >>> 13) | 0x0200;
  }
  if (exp === 0) {
    return sign;
  }

  const newExp = exp - 127 + 15;
  if (newExp >= 31) return sign | 0x7c00;
  if (newExp <= 0) {
    if (newExp < -10) return sign;
    const den = (mant | 0x800000) >>> (1 - newExp);
    return sign | (den >>> 13);
  }
  return sign | (newExp << 10) | (mant >>> 13);
}

export function bytesPerPixel(format: InternalColorFormat): number {
  return format === 'rgba32float' ? 16 : 8;
}

/** CPU upload payload for queue.writeTexture on rgba sim textures. */
export function packRgbaUploadData(
  floats: Float32Array,
  width: number,
  height: number,
  format: InternalColorFormat,
): { data: ArrayBufferView; bytesPerRow: number; rowsPerImage: number } {
  const bytesPerRow = width * bytesPerPixel(format);
  if (format === 'rgba32float') {
    return { data: floats, bytesPerRow, rowsPerImage: height };
  }
  const Float16Ctor = (globalThis as unknown as { Float16Array?: new (n: number) => ArrayBufferView }).Float16Array;
  if (Float16Ctor) {
    const f16 = new Float16Ctor(floats.length);
    const f16View = f16 as unknown as { length: number; [i: number]: number };
    for (let i = 0; i < floats.length; i++) {
      f16View[i] = floats[i];
    }
    return { data: f16, bytesPerRow, rowsPerImage: height };
  }
  const packed = new Uint16Array(floats.length);
  for (let i = 0; i < floats.length; i++) {
    packed[i] = floatToHalfBits(floats[i]);
  }
  return { data: packed, bytesPerRow, rowsPerImage: height };
}

export function formatLabel(format: InternalColorFormat): string {
  return format === 'rgba32float' ? 'FP32' : 'FP16';
}

export function estimateInternalTextureMiB(
  width: number,
  height: number,
  format: InternalColorFormat,
  targetCount = RGBA_INTERNAL_TARGET_COUNT,
): number {
  const bytes = width * height * bytesPerPixel(format) * targetCount;
  return Math.round((bytes / (1024 * 1024)) * 10) / 10;
}

export function parseAdapterGpuType(
  adapterType: string | undefined,
): AdapterGpuType {
  switch (adapterType) {
    case 'discrete':
    case 'DiscreteGPU':
      return 'discrete';
    case 'integrated':
    case 'IntegratedGPU':
      return 'integrated';
    case 'cpu':
    case 'CPU':
      return 'cpu';
    default:
      return 'unknown';
  }
}

export interface FormatProbeOptions {
  isMobile?: boolean;
  /** Boot-probe GPUDevice — same requestDevice; never a second device. */
  device?: GPUDevice | null;
}

function probeStorageTexture(
  device: GPUDevice | null | undefined,
  format: GPUTextureFormat,
): boolean {
  if (!device || typeof device.createTexture !== 'function') return false;
  const usage: GPUTextureUsageFlags = typeof GPUTextureUsage !== 'undefined'
    ? GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.COPY_DST | GPUTextureUsage.TEXTURE_BINDING
    : 0x0e;
  try {
    const tex = device.createTexture({
      label: `format-probe-${format}`,
      size: [1, 1],
      format,
      usage,
    });
    tex.destroy();
    return true;
  } catch {
    return false;
  }
}

export function probeFormatCapabilities(
  adapter: GPUAdapter,
  isMobileOrOptions: boolean | FormatProbeOptions = false,
): DeviceFormatCapabilities {
  const options: FormatProbeOptions = typeof isMobileOrOptions === 'boolean'
    ? { isMobile: isMobileOrOptions }
    : isMobileOrOptions;
  const isMobile = options.isMobile ?? false;
  const features = adapter?.features;
  const hasFloat32Filterable = !!features?.has('float32-filterable');
  const hasFloat32Blendable = !!features?.has('float32-blendable' as GPUFeatureName);
  const float16 = hasFloat16Array();
  const supportsRgba16FloatStorage = probeStorageTexture(options.device, 'rgba16float');
  const supportsRgba32FloatStorage = probeStorageTexture(options.device, 'rgba32float');

  if (!float16) {
    console.warn(
      '[formatPolicy] Float16Array is unavailable — fail-soft staying on rgba32float for CPU uploads. '
      + 'Balanced/battery will not demote storage.',
    );
  }

  return {
    adapterGpuType: parseAdapterGpuType(
      (adapter.info as GPUAdapterInfo & { adapterType?: string })?.adapterType,
    ),
    isMobile,
    supportsRgba32FloatStorage,
    supportsRgba16FloatStorage,
    supportsFloat16Array: float16,
    hasFloat32Filterable,
    hasFloat32Blendable,
  };
}

function canUseRgba16Float(caps: DeviceFormatCapabilities): boolean {
  return caps.supportsRgba16FloatStorage && caps.supportsFloat16Array;
}

/** Default capabilities before adapter init (unmeasured FP32 storage; FP16 assumed for unit tests). */
export const DEFAULT_FORMAT_CAPABILITIES: DeviceFormatCapabilities = {
  adapterGpuType: 'unknown',
  isMobile: false,
  supportsRgba32FloatStorage: false,
  supportsRgba16FloatStorage: true,
  supportsFloat16Array: true,
  hasFloat32Filterable: false,
  hasFloat32Blendable: false,
};

export function resolveColorFormat(
  mode: RenderQualityMode,
  caps: DeviceFormatCapabilities = DEFAULT_FORMAT_CAPABILITIES,
): InternalColorFormat {
  if (mode === 'ultra') {
    return ULTRA_COLOR_FORMAT;
  }
  if (mode === 'balanced' || mode === 'battery') {
    if (canUseRgba16Float(caps)) return BALANCED_COLOR_FORMAT;
    return ULTRA_COLOR_FORMAT;
  }

  // auto — discrete desktop starts FP32 only when storage was measured legal
  if (
    caps.adapterGpuType === 'discrete'
    && !caps.isMobile
    && caps.supportsRgba32FloatStorage
  ) {
    return ULTRA_COLOR_FORMAT;
  }
  if (canUseRgba16Float(caps)) return BALANCED_COLOR_FORMAT;
  return ULTRA_COLOR_FORMAT;
}

export function toGpuTextureFormat(format: InternalColorFormat): GPUTextureFormat {
  return format;
}

export function internalColorFormatFromWasm(value: number): InternalColorFormat {
  return value === 0 ? ULTRA_COLOR_FORMAT : BALANCED_COLOR_FORMAT;
}

export function internalColorFormatToWasm(format: InternalColorFormat): number {
  return format === 'rgba32float' ? 0 : 1;
}

/**
 * True Jacobi / RD / fluid *state* graphs that must stay on FP32 even if the
 * generated catalog dropped `requiresRgba32Float`. Visual shaders that merely
 * tag `physics` / `fluid` are not in this set — see docs/FORMAT_TIERS.md.
 */
export const FP32_REQUIRED_SHADER_IDS = new Set([
  'ripple-tank',
  'fabric-of-reality',
  'chromatographic-fluid',
  'gray-scott-tank',
  'wave-tank',
  'optical-flow-dream',
  'photonic-caustics-graph',
  'sim-fluid-feedback-coupled',
]);

export interface Fp32PinDecision {
  /** Format that must actually be used, after honouring FP32-required shaders. */
  colorFormat: InternalColorFormat;
  /** True when the tier asked for FP16 but an active shader forced FP32. */
  pinned: boolean;
  /** Shader ids that forced the pin (sorted, for logging). */
  pinnedBy: string[];
}

/**
 * Guard against the silent FP16 path: a tier switch (or auto probe) must never demote
 * storage below rgba32float while an FP32-required shader is loaded in a slot.
 * See docs/FORMAT_TIERS.md — "Do not silently run physics sims at FP16."
 */
export function resolveFp32Pin(
  requestedFormat: InternalColorFormat,
  fp32ShaderIds: Iterable<string>,
): Fp32PinDecision {
  const pinnedBy = Array.from(fp32ShaderIds).sort();
  if (requestedFormat === ULTRA_COLOR_FORMAT || pinnedBy.length === 0) {
    return { colorFormat: requestedFormat, pinned: false, pinnedBy: [] };
  }
  return { colorFormat: ULTRA_COLOR_FORMAT, pinned: true, pinnedBy };
}

/** Infer FP32 requirement from the explicit JSON flag or the state-shader allowlist. */
export function inferRequiresRgba32Float(shader: {
  id?: string;
  requiresRgba32Float?: boolean;
  category?: string;
  tags?: string[];
}): boolean {
  if (shader.requiresRgba32Float === true) return true;
  if (shader.id && FP32_REQUIRED_SHADER_IDS.has(shader.id)) return true;
  return false;
}
