/**
 * Shared gpu-chores types (Tier 4b analysis / pre-FX).
 * Domain FX compute stays app-local (Tier 4a).
 */

export type GpuChoresBackend = 'webgpu' | 'wasm' | 'ts';

export type GpuChoresOp =
  | 'luma_histogram_bt709'
  | 'reduce_f32'
  | 'lut_u8_map'
  | 'downsample_2d'
  | 'auto_exposure'
  | 'apply_gain_2d';

export type SourceGainStatus = 'on' | 'off' | 'skipped-physics';

export interface ClassifyPreview {
  width: number;
  height: number;
  bands: number[];
}

export const HISTOGRAM_BINS = 256;
export const PREVIEW_SIZE = 64;
export const LUT_SIZE = 256;
export const CLASSIFY_BANDS = 8;

/** BT.709 luma weights — Chromashift-shaped histogram/mask reference. */
export const BT709_LUMA = { r: 0.2126, g: 0.7152, b: 0.0722 } as const;

export interface LumaHistogram {
  bins: Uint32Array;
  pixelCount: number;
}

export interface ReduceF32 {
  min: number;
  max: number;
  mean: number;
}

export interface AutoExposure {
  /** Histogram-weighted mean luma in [0, 1]. */
  lumaMean: number;
  /** Linear gain toward middle grey (0.18). Clamped. */
  gain: number;
  /** log2(gain). */
  ev: number;
}

export interface GpuChoresAutoUniforms {
  lumaMin: number;
  lumaMax: number;
  lumaMean: number;
  exposureGain: number;
  exposureEv: number;
}

export interface GpuChoresBreadcrumbs {
  gpuComputeAvailable: boolean;
  reason: string;
  lastOp: GpuChoresOp | null;
  backend: GpuChoresBackend;
  autoUniforms: GpuChoresAutoUniforms;
  sourceGain: SourceGainStatus;
  classifyPreview: ClassifyPreview | null;
}

export const NEUTRAL_AUTO_UNIFORMS: GpuChoresAutoUniforms = {
  lumaMin: 0,
  lumaMax: 1,
  lumaMean: 0.5,
  exposureGain: 1,
  exposureEv: 0,
};

export function createDefaultBreadcrumbs(
  overrides: Partial<GpuChoresBreadcrumbs> = {},
): GpuChoresBreadcrumbs {
  return {
    gpuComputeAvailable: false,
    reason: 'not attached',
    lastOp: null,
    backend: 'ts',
    autoUniforms: { ...NEUTRAL_AUTO_UNIFORMS },
    sourceGain: 'off',
    classifyPreview: null,
    ...overrides,
  };
}
