/**
 * Cached depth pipeline loader with WebGPU preference, progress, and cancel.
 */

import { DEPTH_MODEL_ID } from '../../config/appConfig';
import { loadTransformersModule } from '../aiModels/transformersLoader';
import type {
  DepthBackend,
  DepthEstimatorPipeline,
  DepthLoadProgress,
  DepthLoadState,
} from './types';
import { classifyDepthLoadError } from './types';

const DEPTH_TASK = 'depth-estimation';

interface CachedDepth {
  pipeline: DepthEstimatorPipeline;
  backend: DepthBackend;
}

let cached: CachedDepth | null = null;
let inflight: Promise<CachedDepth> | null = null;
let abortController: AbortController | null = null;

/**
 * WebGPU depth is only considered when the boot probe succeeded.
 * Never call requestAdapter() here — the renderer owns the sole adapter/device.
 *
 * Note: @xenova/transformers with device:'webgpu' may still allocate its own
 * GPUDevice internally. Prefer WASM/CPU while the canvas renderer is live.
 */
function webGpuAvailable(): boolean {
  return (
    typeof navigator !== 'undefined' &&
    !!navigator.gpu &&
    window.webgpuProbe?.ok === true
  );
}

/** @internal Exported for unit tests — never calls requestAdapter. */
export function isDepthWebGpuAvailable(): boolean {
  return webGpuAvailable();
}

function wrapPipeline(estimator: unknown): DepthEstimatorPipeline {
  return estimator as DepthEstimatorPipeline;
}

function throwIfAborted(signal: AbortSignal | undefined): void {
  if (signal?.aborted) {
    throw new DOMException('Depth load aborted', 'AbortError');
  }
}

async function createPipeline(
  backend: DepthBackend,
  onProgress?: (p: DepthLoadProgress) => void,
  signal?: AbortSignal
): Promise<CachedDepth> {
  throwIfAborted(signal);
  const { pipeline } = await loadTransformersModule();
  throwIfAborted(signal);

  const options: Record<string, unknown> = {
    progress_callback: (p: DepthLoadProgress) => onProgress?.(p),
  };
  if (backend === 'webgpu') {
    options.device = 'webgpu';
  }

  const estimator = await pipeline(DEPTH_TASK, DEPTH_MODEL_ID, options);
  throwIfAborted(signal);

  return { pipeline: wrapPipeline(estimator), backend };
}

export function getCachedDepthPipeline(): CachedDepth | null {
  return cached;
}

export function cancelDepthPipelineLoad(): void {
  abortController?.abort();
  abortController = null;
  inflight = null;
}

export async function loadDepthPipeline(options?: {
  onProgress?: (progress: DepthLoadProgress) => void;
  onStateChange?: (state: DepthLoadState) => void;
  preferWebGpu?: boolean;
  /** When true, skip WebGPU backend to avoid a third GPUDevice while the canvas renderer is live. */
  rendererDeviceActive?: boolean;
}): Promise<CachedDepth> {
  if (cached) {
    return cached;
  }
  if (inflight) {
    return inflight;
  }

  abortController = new AbortController();
  const signal = abortController.signal;

  const setState = (state: DepthLoadState) => options?.onStateChange?.(state);

  inflight = (async () => {
    setState({ phase: 'loading', message: 'Loading depth model library...' });

    try {
      const preferWebGpu =
        options?.preferWebGpu !== false &&
        webGpuAvailable() &&
        !options?.rendererDeviceActive;

      if (preferWebGpu) {
        setState({ phase: 'loading', message: 'Loading depth model (WebGPU)...', backend: 'webgpu' });
        try {
          cached = await createPipeline('webgpu', options?.onProgress, signal);
          setState({ phase: 'ready', message: 'Depth model loaded (WebGPU).', backend: 'webgpu' });
          return cached;
        } catch (webgpuError) {
          console.warn('[depth] WebGPU pipeline failed, falling back to WASM:', webgpuError);
          throwIfAborted(signal);
        }
      }

      setState({ phase: 'loading', message: 'Loading depth model (WASM)...', backend: 'wasm' });
      cached = await createPipeline('wasm', options?.onProgress, signal);
      setState({ phase: 'ready', message: 'Depth model loaded.', backend: cached.backend });
      return cached;
    } catch (error) {
      const classified = classifyDepthLoadError(error);
      setState({
        phase: classified.phase,
        message: classified.message,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    } finally {
      inflight = null;
      abortController = null;
    }
  })();

  return inflight;
}

/** Reset singleton — for tests only. */
export function resetDepthPipelineCache(): void {
  cancelDepthPipelineLoad();
  cached = null;
}
