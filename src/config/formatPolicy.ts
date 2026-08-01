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
  /** Adapters that passed Pixelocity init support rgba32float storage today. */
  supportsRgba32FloatStorage: boolean;
}

export const ULTRA_COLOR_FORMAT: InternalColorFormat = 'rgba32float';
export const BALANCED_COLOR_FORMAT: InternalColorFormat = 'rgba16float';
export const BATTERY_COLOR_FORMAT: InternalColorFormat = 'rgba16float';

/** rgba targets at sim resolution (read, write, dataA/B/C, history) + full-res source. */
export const RGBA_INTERNAL_TARGET_COUNT = 7;

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
  if (!Float16Ctor) {
    throw new Error('Float16Array is not available in this runtime');
  }
  const f16 = new Float16Ctor(floats.length);
  const f16View = f16 as unknown as { length: number; [i: number]: number };
  for (let i = 0; i < floats.length; i++) {
    f16View[i] = floats[i];
  }
  return { data: f16, bytesPerRow, rowsPerImage: height };
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

export function probeFormatCapabilities(
  adapter: GPUAdapter,
  isMobile = false,
): DeviceFormatCapabilities {
  return {
    adapterGpuType: parseAdapterGpuType(
      (adapter.info as GPUAdapterInfo & { adapterType?: string })?.adapterType,
    ),
    isMobile,
    supportsRgba32FloatStorage: true,
  };
}

/** Default capabilities before adapter init (conservative: prefer FP16 on auto). */
export const DEFAULT_FORMAT_CAPABILITIES: DeviceFormatCapabilities = {
  adapterGpuType: 'unknown',
  isMobile: false,
  supportsRgba32FloatStorage: true,
};

export function resolveColorFormat(
  mode: RenderQualityMode,
  caps: DeviceFormatCapabilities = DEFAULT_FORMAT_CAPABILITIES,
): InternalColorFormat {
  if (mode === 'ultra') {
    return ULTRA_COLOR_FORMAT;
  }
  if (mode === 'balanced') {
    return BALANCED_COLOR_FORMAT;
  }
  if (mode === 'battery') {
    return BATTERY_COLOR_FORMAT;
  }

  // auto — discrete desktop starts FP32; integrated/mobile/unknown → FP16
  if (
    caps.adapterGpuType === 'discrete'
    && !caps.isMobile
    && caps.supportsRgba32FloatStorage
  ) {
    return ULTRA_COLOR_FORMAT;
  }
  return BALANCED_COLOR_FORMAT;
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

const FP32_INFER_TAGS = new Set([
  'physics',
  'reaction-diffusion',
  'fluid',
  'simulation',
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

/** Infer FP32 requirement from catalog metadata when explicit flag is absent. */
export function inferRequiresRgba32Float(shader: {
  requiresRgba32Float?: boolean;
  category?: string;
  tags?: string[];
}): boolean {
  if (shader.requiresRgba32Float === true) return true;
  if (shader.category === 'simulation') return true;
  const tags = shader.tags ?? [];
  return tags.some((tag) => FP32_INFER_TAGS.has(tag));
}
