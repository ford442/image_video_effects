/**
 * Shared render-performance policy for TypeScript and C++ (wasm_renderer/performance_policy.h).
 * Keep numeric values in sync across both files.
 */

/** Full internal buffer dimension before quality scaling. */
export const INTERNAL_RENDER_RESOLUTION = 2048;

/** Workgroup tile size used when snapping scaled dimensions. */
export const RENDER_WORKGROUP_SIZE = 16;

/** Minimum / maximum internal resolution scale. */
export const MIN_RENDER_SCALE = 0.25;
export const MAX_RENDER_SCALE = 1.0;

/** Scale step used by adaptive quality adjustments. */
export const ADAPTIVE_SCALE_STEP_DOWN = 0.125;
export const ADAPTIVE_SCALE_STEP_UP = 0.0625;

/** FPS ratio thresholds for adaptive scale changes. */
export const ADAPTIVE_FPS_LOW_RATIO = 0.7;
export const ADAPTIVE_FPS_HIGH_RATIO = 0.95;

export type RenderQualityMode = 'battery' | 'balanced' | 'ultra' | 'auto';

export interface ResolvedPerformancePolicy {
  mode: RenderQualityMode;
  /** Internal render scale (0.25–1.0). */
  scale: number;
  /** Max shader slots that may be active simultaneously. */
  maxActiveSlots: number;
  /** Target FPS for adaptive mode (30 on low-end, 60 otherwise). */
  targetFps: number;
  /** When true, resolution scale is adjusted from measured FPS. */
  adaptive: boolean;
  /** Skip shaders flagged requiresDeepWorkgroup when a standard variant exists. */
  preferNonDeepVariants: boolean;
}

export interface PerformancePolicyPreset {
  scale: number;
  maxActiveSlots: number;
  targetFps: number;
  adaptive: boolean;
  preferNonDeepVariants: boolean;
}

/** Fixed presets — `auto` is resolved at runtime via resolveAutoPolicy(). */
export const QUALITY_PRESETS: Record<Exclude<RenderQualityMode, 'auto'>, PerformancePolicyPreset> = {
  battery: {
    scale: 0.5,
    maxActiveSlots: 1,
    targetFps: 30,
    adaptive: false,
    preferNonDeepVariants: true,
  },
  balanced: {
    scale: 0.75,
    maxActiveSlots: 2,
    targetFps: 60,
    adaptive: false,
    preferNonDeepVariants: true,
  },
  ultra: {
    scale: 1.0,
    maxActiveSlots: 3,
    targetFps: 60,
    adaptive: false,
    preferNonDeepVariants: false,
  },
};

export interface DevicePerformanceHints {
  supportsDeepWorkgroup: boolean;
  isMobile?: boolean;
}

export function isMobileDevice(): boolean {
  if (typeof navigator === 'undefined') return false;
  return /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent);
}

export function isLowEndGPU(supportsDeepWorkgroup: boolean): boolean {
  return !supportsDeepWorkgroup;
}

/** Snap scale to workgroup-friendly increments (1/8 steps). */
export function snapRenderScale(scale: number): number {
  const clamped = Math.max(MIN_RENDER_SCALE, Math.min(MAX_RENDER_SCALE, scale));
  return Math.round(clamped * 8) / 8;
}

/** Compute square internal dimensions from base resolution and scale. */
export function computeInternalDimensions(
  baseResolution = INTERNAL_RENDER_RESOLUTION,
  scale: number,
  workgroupSize = RENDER_WORKGROUP_SIZE,
): { width: number; height: number; scale: number } {
  const snapped = snapRenderScale(scale);
  const dim = Math.ceil((baseResolution * snapped) / workgroupSize) * workgroupSize;
  return { width: dim, height: dim, scale: snapped };
}

/** Starting policy for Auto mode before FPS-driven adjustments. */
export function resolveAutoPolicy(hints: DevicePerformanceHints): ResolvedPerformancePolicy {
  const mobile = hints.isMobile ?? isMobileDevice();
  const lowEnd = isLowEndGPU(hints.supportsDeepWorkgroup);

  if (lowEnd) {
    return {
      mode: 'auto',
      scale: 0.5,
      maxActiveSlots: 1,
      targetFps: 30,
      adaptive: true,
      preferNonDeepVariants: true,
    };
  }

  if (mobile) {
    return {
      mode: 'auto',
      scale: 0.75,
      maxActiveSlots: 2,
      targetFps: 60,
      adaptive: true,
      preferNonDeepVariants: true,
    };
  }

  return {
    mode: 'auto',
    scale: 1.0,
    maxActiveSlots: 3,
    targetFps: 60,
    adaptive: true,
    preferNonDeepVariants: true,
  };
}

export function resolvePerformancePolicy(
  mode: RenderQualityMode,
  hints: DevicePerformanceHints,
): ResolvedPerformancePolicy {
  if (mode === 'auto') {
    return resolveAutoPolicy(hints);
  }
  const preset = QUALITY_PRESETS[mode];
  let maxActiveSlots = preset.maxActiveSlots;
  if (isLowEndGPU(hints.supportsDeepWorkgroup)) {
    maxActiveSlots = Math.min(maxActiveSlots, 1);
  }
  return { mode, ...preset, maxActiveSlots };
}
