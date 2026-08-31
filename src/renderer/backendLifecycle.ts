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

export type { WebGpuProbeHandoff };

/** Optional init knobs for RendererManager (probe handoff avoids double requestDevice). */
export interface RendererInitOptions {
  webGpuHandoff?: WebGpuProbeHandoff;
}

/** Supported renderer backend identifiers. */
export type RendererType = 'webgpu' | 'wasm' | 'js';

/**
 * Read the preferred renderer type from the URL query string.
 *
 * Supported values for the `renderer` parameter:
 *   - `wasm`   → C++ Emscripten WASM renderer (**experimental** — see WASM_BACKEND_POLICY.md)
 *   - `webgpu` → TypeScript native WebGPU renderer (default)
 *   - `js`     → Canvas 2D fallback (no shaders)
 *
 * Example: `http://localhost:3000/?renderer=wasm`
 *
 * Related: `?no_gpu_compute` forces gpu-chores (Tier 4b) onto the TS backend.
 * See docs/GPU_CHORES.md — it does not switch the renderer.
 */
export function getRendererTypeFromURL(): RendererType | null {
  try {
    const params = new URLSearchParams(window.location.search);
    const value = params.get('renderer');
    if (value === 'wasm' || value === 'webgpu' || value === 'js') {
      return value as RendererType;
    }
  } catch {
    // Not in a browser context (e.g. tests)
  }
  return null;
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

/** Factory for the three renderer backends — keeps RendererManager free of `new` branches. */
export function createRendererForType(type: RendererType, config: RendererConfig): Renderer {
  if (type === 'webgpu') return new WebGPURenderer(config);
  if (type === 'wasm') return new WASMRenderer(config);
  return new JSRenderer(config);
}

export interface BackendSwitchInput {
  targetType: RendererType;
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
    const exclusive = previousRenderer as Renderer & { releaseExclusiveGpu?: () => Promise<void> };
    if (typeof exclusive.releaseExclusiveGpu === 'function') {
      await exclusive.releaseExclusiveGpu();
    } else {
      previousRenderer!.destroy();
      await yieldForGpuRelease();
    }
  }

  const renderer = createRendererForType(targetType, config);
  let success = false;
  if (targetType === 'webgpu') {
    success = await (renderer as WebGPURenderer).init(canvas, input.webGpuHandoff);
  } else {
    success = await renderer.init(canvas);
  }

  if (success) {
    if (!mustReleaseFirst) {
      previousRenderer?.destroy();
    }

    let nextCanvas = canvas;
    if (targetType === 'js' && typeof (renderer as JSRenderer).getCanvas === 'function') {
      const replaced = (renderer as JSRenderer).getCanvas();
      if (replaced) nextCanvas = replaced;
    }

    const video = (previousRenderer as { video?: HTMLVideoElement } | null)?.video;
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
