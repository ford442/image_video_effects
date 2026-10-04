/**
 * webgpuBackendApi.ts
 *
 * The TS WebGPU backend's public surface as RendererManager and friends use
 * it. It is implemented by the in-thread WebGPURenderer and by
 * WorkerWebGPUBackend, the main-thread proxy for the render worker (#1314
 * WP-1). Defining it as a Pick of the real class makes tsc keep the two in
 * lock-step.
 */

import type { Renderer } from './Renderer';
import type { WebGPURenderer } from './WebGPURenderer';

export type WebGPUBackendApi = Pick<
  WebGPURenderer,
  | 'backendKind'
  | 'renderThread'
  | 'init'
  | 'destroy'
  | 'releaseExclusiveGpu'
  | 'setVideo'
  | 'updateVideoFrame'
  | 'updateAudioData'
  | 'updateAudioFrequencyBins'
  | 'updateMouse'
  | 'setParam'
  | 'setInputSource'
  | 'getInputSource'
  | 'loadShader'
  | 'preloadShader'
  | 'setActiveShader'
  | 'setSlotShader'
  | 'setSlotEnabled'
  | 'setSlotMode'
  | 'getSlotMode'
  | 'getSlotState'
  | 'setSlotParams'
  | 'updateSlotParams'
  | 'addRipple'
  | 'clearRipples'
  | 'loadImage'
  | 'updateDepthMap'
  | 'getGPUTimings'
  | 'getPassTimings'
  | 'getTimingInfo'
  | 'getFrameStats'
  | 'getVideoIngestStats'
  | 'getVideoStatus'
  | 'getFPS'
  | 'getAudioData'
  | 'getSupportsDeepWorkgroup'
  | 'getColorFormat'
  | 'getFormatCapabilities'
  | 'getHistoryLayers'
  | 'getWorkingSizeCap'
  | 'getResolutionScale'
  | 'setResolutionScale'
  | 'setColorFormat'
  | 'setAdaptiveQuality'
  | 'setMaxPassesPerFrame'
  | 'setFramePassBudget'
  | 'setNodeScale'
  | 'getNodeScales'
  | 'getScalableNodes'
  | 'isShaderCached'
  | 'warmShaders'
  | 'captureChoresThumbnailPng'
  | 'setSourceAutoExposure'
  | 'applyTestRenderState'
  | 'supportsCanvasCopySrc'
  | 'setCanvasCopySrc'
  | 'getAdapterSummary'
  | 'getAdapterAttemptLabel'
  | 'getLastGraphReport'
  | 'getGpuChoresBreadcrumbs'
  | 'initialized'
> & Required<Pick<Renderer, 'loadImageFromElement' | 'getCpuInputBitmap'>>;

/** Narrow any renderer to the TS WebGPU backend (in-thread or worker proxy). */
export function isWebGpuBackend(renderer: unknown): renderer is WebGPUBackendApi {
  return !!renderer && (renderer as { backendKind?: unknown }).backendKind === 'webgpu';
}
