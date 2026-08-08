/**
 * performanceStatus.ts
 *
 * Pure seams for format tier / FP32 pin / pass-budget policy surface.
 * Mirrors webgpu quality caps without touching engine internals.
 */

import {
  computeInternalDimensions,
  estimateInternalTextureMiB,
  INTERNAL_RENDER_RESOLUTION,
  RenderQualityMode,
  ResolvedPerformancePolicy,
  resolvePerformancePolicy,
} from '../config/performancePolicy';
import {
  DEFAULT_FORMAT_CAPABILITIES,
  DeviceFormatCapabilities,
  Fp32PinDecision,
  InternalColorFormat,
  resolveFp32Pin,
} from '../config/formatPolicy';
import { AdaptivePerformanceController } from './adaptivePerformance';
import { RendererConfig } from './Renderer';
import { WASMRenderer } from './WASMRenderer';
import { WebGPURenderer } from './WebGPURenderer';
import type { RendererType } from './backendLifecycle';

export interface RendererPerformanceStatus {
  qualityMode: RenderQualityMode;
  backend: RendererType;
  scale: number;
  internalWidth: number;
  internalHeight: number;
  maxActiveSlots: number;
  targetFps: number;
  adaptive: boolean;
  fps: number;
  colorFormat: InternalColorFormat;
  estimatedTextureMiB: number;
  /** Format the quality tier asked for, before any FP32 pin. */
  requestedColorFormat: InternalColorFormat;
  /** True when an FP32-required shader forced rgba32float over the tier default. */
  fp32Pinned: boolean;
  /** Shader ids holding the FP32 pin. */
  fp32PinnedBy: string[];
  /** Graph dispatch cap for this tier (Tier C multipass). */
  maxPassesPerFrame: number;
}

export interface PerformancePolicyState {
  qualityMode: RenderQualityMode;
  performancePolicy: ResolvedPerformancePolicy;
  requestedColorFormat: InternalColorFormat;
  fp32Pin: Fp32PinDecision;
  formatCapabilities: DeviceFormatCapabilities;
  resolutionScale: number;
  fp32RequiredShaders: Set<string>;
}

export function createPerformancePolicyState(): PerformancePolicyState {
  const initialPolicy = resolvePerformancePolicy('auto', { supportsDeepWorkgroup: true });
  return {
    qualityMode: 'auto',
    performancePolicy: initialPolicy,
    requestedColorFormat: initialPolicy.colorFormat,
    fp32Pin: {
      colorFormat: initialPolicy.colorFormat,
      pinned: false,
      pinnedBy: [],
    },
    formatCapabilities: DEFAULT_FORMAT_CAPABILITIES,
    resolutionScale: 1.0,
    fp32RequiredShaders: new Set<string>(),
  };
}

export function refreshFormatCapabilities(
  state: PerformancePolicyState,
  renderer: WebGPURenderer | WASMRenderer | null,
): void {
  const fromRenderer = renderer && 'getFormatCapabilities' in renderer
    ? renderer.getFormatCapabilities?.()
    : undefined;
  if (fromRenderer) {
    state.formatCapabilities = fromRenderer;
  }
}

export function applyQualityPolicy(
  state: PerformancePolicyState,
  mode: RenderQualityMode,
  hints?: { supportsDeepWorkgroup?: boolean; formatCaps?: DeviceFormatCapabilities },
  getSupportsDeepWorkgroup?: () => boolean,
): void {
  state.qualityMode = mode;
  const supportsDeep = hints?.supportsDeepWorkgroup ?? getSupportsDeepWorkgroup?.() ?? true;
  const formatCaps = hints?.formatCaps ?? state.formatCapabilities;
  const resolved = resolvePerformancePolicy(mode, {
    supportsDeepWorkgroup: supportsDeep,
    formatCaps,
  });
  state.requestedColorFormat = resolved.colorFormat;
  const pin = resolveFp32Pin(resolved.colorFormat, state.fp32RequiredShaders);
  state.fp32Pin = pin;
  if (pin.pinned) {
    console.warn(
      `[RendererManager] Quality "${mode}" requests ${resolved.colorFormat}, but ` +
        `${pin.pinnedBy.join(', ')} require rgba32float — storage format pinned to FP32`,
    );
  }
  state.performancePolicy = { ...resolved, colorFormat: pin.colorFormat };
}

export function registerFp32Requirement(state: PerformancePolicyState, shaderId: string): boolean {
  const wasNew = !state.fp32RequiredShaders.has(shaderId);
  state.fp32RequiredShaders.add(shaderId);
  return wasNew;
}

export function releaseFp32Requirement(state: PerformancePolicyState, shaderId: string): boolean {
  return state.fp32RequiredShaders.delete(shaderId);
}

export function readResolutionScale(
  state: PerformancePolicyState,
  config: RendererConfig,
  renderer: WebGPURenderer | WASMRenderer | null,
): { scale: number; scaled: { w: number; h: number } } {
  const fromRenderer = renderer && 'getResolutionScale' in renderer
    ? renderer.getResolutionScale?.()
    : undefined;
  if (fromRenderer) {
    state.resolutionScale = fromRenderer.scale;
    return {
      scale: fromRenderer.scale,
      scaled: { w: fromRenderer.scaled.w, h: fromRenderer.scaled.h },
    };
  }
  const base = config.width || INTERNAL_RENDER_RESOLUTION;
  const dims = computeInternalDimensions(base, state.resolutionScale);
  return {
    scale: dims.scale,
    scaled: { w: dims.width, h: dims.height },
  };
}

export function buildPerformanceStatus(
  state: PerformancePolicyState,
  backend: RendererType,
  getFps: () => number,
  scaleInfo: { scale: number; scaled: { w: number; h: number } },
): RendererPerformanceStatus {
  return {
    qualityMode: state.qualityMode,
    backend,
    scale: scaleInfo.scale,
    internalWidth: scaleInfo.scaled.w,
    internalHeight: scaleInfo.scaled.h,
    maxActiveSlots: state.performancePolicy.maxActiveSlots,
    targetFps: state.performancePolicy.targetFps,
    adaptive: state.performancePolicy.adaptive,
    fps: getFps(),
    colorFormat: state.performancePolicy.colorFormat,
    estimatedTextureMiB: estimateInternalTextureMiB(
      scaleInfo.scaled.w,
      scaleInfo.scaled.h,
      state.performancePolicy.colorFormat,
    ),
    requestedColorFormat: state.requestedColorFormat,
    fp32Pinned: state.fp32Pin.pinned,
    fp32PinnedBy: state.fp32Pin.pinnedBy,
    maxPassesPerFrame: state.performancePolicy.maxPassesPerFrame,
  };
}

export function applyPerformancePolicyToRenderer(
  state: PerformancePolicyState,
  renderer: WebGPURenderer | WASMRenderer | null,
  adaptiveController: AdaptivePerformanceController,
): void {
  applyResolutionScale(state, renderer, state.performancePolicy.scale);
  applyColorFormat(renderer, state.performancePolicy.colorFormat);
  if (renderer instanceof WebGPURenderer) {
    renderer.setAdaptiveQuality(false);
    renderer.setMaxPassesPerFrame(state.performancePolicy.maxPassesPerFrame);
  }
  adaptiveController.updatePolicy(state.performancePolicy);
}

function applyColorFormat(renderer: WebGPURenderer | WASMRenderer | null, format: InternalColorFormat): void {
  if (renderer instanceof WebGPURenderer) {
    renderer.setColorFormat(format);
  } else if (renderer instanceof WASMRenderer) {
    renderer.setColorFormat(format);
  }
}

function applyResolutionScale(
  state: PerformancePolicyState,
  renderer: WebGPURenderer | WASMRenderer | null,
  scale: number,
): void {
  state.resolutionScale = scale;
  if (renderer instanceof WebGPURenderer) {
    renderer.setResolutionScale(scale);
    renderer.setAdaptiveQuality(false);
  } else if (renderer instanceof WASMRenderer) {
    renderer.setResolutionScale(scale);
  }
}

export function applyResolutionScaleToRenderer(
  state: PerformancePolicyState,
  renderer: WebGPURenderer | WASMRenderer | null,
  scale: number,
): void {
  applyResolutionScale(state, renderer, scale);
}
