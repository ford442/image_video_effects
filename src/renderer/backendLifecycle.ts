/**
 * backendLifecycle.ts
 *
 * Pure seams for renderer backend create/destroy/switch and ?renderer= URL preference.
 * Mirrors the lifecycle split in webgpu/device.ts — RendererManager stays a thin facade.
 */

import { isWasmBlockedAfterOom } from '../config/vramBudget';
import { Renderer, RendererConfig } from './Renderer';
import { JSRenderer } from './JSRenderer';
import { WASMRenderer } from './WASMRenderer';
import { WebGPURenderer } from './WebGPURenderer';
import type { WebGpuProbeHandoff } from './webgpuBootProbe';
import { isWebGpuBackend } from './webgpuBackendApi';
import { isCanvasTransferred, WorkerWebGPUBackend } from './worker/WorkerWebGPUBackend';
import { readRendererVideo } from './inputSourceBridge';
import { getRendererTypeFromURL } from './rendererUrl';

export type { WebGpuProbeHandoff };

/** Optional init knobs for RendererManager (probe handoff avoids double requestDevice). */
export interface RendererInitOptions {
  webGpuHandoff?: WebGpuProbeHandoff;
}

/** Supported renderer backend identifiers. */
export type RendererType = 'webgpu' | 'wasm' | 'js';

// URL readers live in a dependency-free module so UI chrome can import them
// without pulling the renderer graph (WASM bridge, worker backend).
export { getRendererTypeFromURL, isWasmForcedByURL } from './rendererUrl';

/** Where the TS WebGPU backend renders (#1314 WP-1). */
export type RenderThread = 'main' | 'worker';

/**
 * `?renderer=worker` runs the TS WebGPU renderer in the render worker
 * (OffscreenCanvas); `?renderer=main` (or anything else) keeps it on the page.
 */
export function getRenderThreadFromURL(): RenderThread | null {
  try {
    const value = new URLSearchParams(window.location.search).get('renderer');
    if (value === 'worker' || value === 'main') return value;
  } catch {
    // Not in a browser context
  }
  return null;
}

/**
 * Synchronous render-worker capability check: a Worker, OffscreenCanvas,
 * canvas transfer and WebGPU. WebGPU *inside* the worker is confirmed by the
 * worker's hello; if it is missing the page renders instead.
 */
export function supportsRenderWorker(): boolean {
  try {
    return (
      typeof Worker !== 'undefined' &&
      typeof OffscreenCanvas !== 'undefined' &&
      typeof HTMLCanvasElement !== 'undefined' &&
      typeof HTMLCanvasElement.prototype.transferControlToOffscreen === 'function' &&
      typeof navigator !== 'undefined' &&
      !!(navigator as Navigator & { gpu?: unknown }).gpu
    );
  } catch {
    return false;
  }
}

/**
 * The render thread the TS WebGPU backend uses (#1314): the render worker by
 * default where supported; `?renderer=main` keeps it on the page (escape hatch,
 * deterministic pixel diffs), `?renderer=worker` insists on the worker.
 */
export function resolveRenderThread(): RenderThread {
  const fromUrl = getRenderThreadFromURL();
  if (fromUrl) return fromUrl;
  return supportsRenderWorker() ? 'worker' : 'main';
}

/** Both TS WebGPU and emdawnwebgpu (WASM) claim exclusive adapter/device ownership. */
export function usesExclusiveWebGpu(type: RendererType): boolean {
  return type === 'webgpu' || type === 'wasm';
}

/** Yield one frame so the previous backend can release GPU handles before the next init. */
export function yieldForGpuRelease(): Promise<void> {
  return new Promise((resolve) => {
    if (typeof requestAnimationFrame === 'function') {
      requestAnimationFrame(() => resolve());
    } else {
      setTimeout(resolve, 0);
    }
  });
}

/**
 * Tear a renderer down and resolve once its GPU device is released, so the next
 * requestDevice (backend switch or remount re-probe) cannot race the old device.
 */
export async function releaseRendererGpu(renderer: Renderer): Promise<void> {
  const exclusive = renderer as Renderer & { releaseExclusiveGpu?: () => Promise<void> };
  if (typeof exclusive.releaseExclusiveGpu === 'function') {
    await exclusive.releaseExclusiveGpu();
    return;
  }
  await renderer.destroy();
  await yieldForGpuRelease();
}

/** Factory for the three renderer backends — keeps RendererManager free of `new` branches. */
export function createRendererForType(
  type: RendererType,
  config: RendererConfig,
  renderThread: RenderThread = resolveRenderThread(),
): Renderer {
  if (type === 'webgpu') {
    return renderThread === 'worker' ? new WorkerWebGPUBackend(config) : new WebGPURenderer(config);
  }
  if (type === 'wasm') return new WASMRenderer(config);
  return new JSRenderer(config);
}

export interface BackendSwitchInput {
  targetType: RendererType;
  /** TS WebGPU only: force the render thread (fallback after a worker failure). */
  renderThread?: RenderThread;
  canvas: HTMLCanvasElement;
  config: RendererConfig;
  previousType: RendererType | null;
  previousRenderer: Renderer | null;
  /** Pre-probed WebGPU handoff — avoids double requestDevice on boot. */
  webGpuHandoff?: WebGpuProbeHandoff;
}

export interface BackendSwitchResult {
  success: boolean;
  renderer: Renderer | null;
  type: RendererType | null;
  canvas: HTMLCanvasElement;
  isWASM: boolean;
  failedWasmRenderer: WASMRenderer | null;
  /** When set, caller should recursively restore this type after exclusive release failure. */
  restoreType: RendererType | null;
}

/**
 * Attempt to switch renderer backends with exclusive WebGPU release ordering preserved.
 * Does not recurse on restore — RendererManager handles restore to avoid import cycles.
 */
export async function performBackendSwitch(input: BackendSwitchInput): Promise<BackendSwitchResult> {
  const { targetType, canvas, config, previousType, previousRenderer } = input;

  if (targetType === 'wasm' && isWasmBlockedAfterOom()) {
    console.warn(
      '[RendererManager] WASM blocked after GPUOutOfMemoryError this tab — hard reload before switching backends',
    );
    return {
      success: false,
      renderer: previousRenderer,
      type: previousType,
      canvas,
      isWASM: false,
      failedWasmRenderer: null,
      restoreType: null,
    };
  }

  const mustReleaseFirst =
    usesExclusiveWebGpu(targetType) &&
    previousRenderer != null &&
    previousType != null &&
    usesExclusiveWebGpu(previousType);

  if (mustReleaseFirst) {
    console.log(
      `[RendererManager] Releasing ${previousType} before switching to ${targetType} ` +
        '(exclusive WebGPU adapter/device ownership)',
    );
    await releaseRendererGpu(previousRenderer!);
  }

  let renderer = createRendererForType(targetType, config, input.renderThread);
  let success = false;
  if (isWebGpuBackend(renderer)) {
    success = await renderer.init(canvas, input.webGpuHandoff);
    if (!success && renderer.renderThread === 'worker' && !isCanvasTransferred(canvas)) {
      // The worker never took the canvas (no worker WebGPU, spawn failure): render on the page.
      console.warn('[RendererManager] Render worker unavailable — rendering on the page');
      const pageRenderer = new WebGPURenderer(config);
      success = await pageRenderer.init(canvas, input.webGpuHandoff);
      renderer = pageRenderer;
    }
  } else {
    success = await renderer.init(canvas);
  }

  if (success) {
    if (!mustReleaseFirst && previousRenderer) {
      await releaseRendererGpu(previousRenderer);
    }

    let nextCanvas = canvas;
    if (targetType === 'js' && typeof (renderer as JSRenderer).getCanvas === 'function') {
      const replaced = (renderer as JSRenderer).getCanvas();
      if (replaced) nextCanvas = replaced;
    }

    const video = readRendererVideo(previousRenderer) ?? readRendererVideo(renderer);
    if (video) renderer.setVideo(video);

    return {
      success: true,
      renderer,
      type: targetType,
      canvas: nextCanvas,
      isWASM: targetType === 'wasm',
      failedWasmRenderer: null,
      restoreType: null,
    };
  }

  console.warn(`[RendererManager] switchRenderer('${targetType}') failed`);
  const failedWasmRenderer = targetType === 'wasm' ? (renderer as WASMRenderer) : null;

  return {
    success: false,
    renderer: mustReleaseFirst ? null : previousRenderer,
    type: mustReleaseFirst ? null : previousType,
    canvas,
    isWASM: false,
    failedWasmRenderer,
    restoreType: mustReleaseFirst ? previousType : null,
  };
}

export interface InitBackendPreference {
  /** First backend to try after URL overrides (null = default webgpu→js chain). */
  preferredType: RendererType | null;
  /** When wasm was requested via URL but failed — fall through without auto-wasm elsewhere. */
  wasmUrlFailed: boolean;
}

/** Resolve which backend init() should attempt first (URL query only; no auto-wasm). */
export function resolveInitBackendPreference(): InitBackendPreference {
  const urlPreference = getRendererTypeFromURL();
  if (urlPreference === 'wasm') return { preferredType: 'wasm', wasmUrlFailed: false };
  if (urlPreference === 'js') return { preferredType: 'js', wasmUrlFailed: false };
  return { preferredType: null, wasmUrlFailed: false };
}
