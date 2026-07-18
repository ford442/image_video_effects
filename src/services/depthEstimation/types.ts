/**
 * Typed contracts for depth-estimation pipeline I/O.
 * Matches @xenova/transformers depth-estimation output and App updateDepthMap path.
 */

/** Raw depth tensor from the model (typically [batch, height, width] or [height, width]). */
export interface DepthTensor {
  data: ArrayLike<number>;
  dims: number[];
}

/** Pipeline output shape consumed by normalizeDepthMap → updateDepthMap. */
export interface DepthPipelineOutput {
  predicted_depth: DepthTensor;
}

/** Callable depth pipeline (narrow surface — avoids importing library types). */
export interface DepthEstimatorPipeline {
  (input: string | DepthImageInput): Promise<DepthPipelineOutput>;
}

/** Minimal image input accepted by transformers RawImage paths. */
export type DepthImageInput = string | { src: string };

export interface DepthLoadProgress {
  status: string;
  progress?: number;
  file?: string;
}

export type DepthLoadPhase =
  | 'idle'
  | 'loading'
  | 'ready'
  | 'error'
  | 'cancelled'
  | 'offline';

export type DepthBackend = 'webgpu' | 'wasm' | 'cpu';

export interface DepthLoadState {
  phase: DepthLoadPhase;
  message: string;
  progress?: number;
  backend?: DepthBackend;
  error?: string;
}

/** Normalized depth map passed to RendererManager.updateDepthMap. */
export interface NormalizedDepthMap {
  data: Float32Array;
  width: number;
  height: number;
}

export function depthTensorHeightWidth(dims: number[]): { height: number; width: number } {
  if (dims.length < 2) {
    throw new Error(`Depth tensor dims must be at least 2-D, got ${JSON.stringify(dims)}`);
  }
  const height = dims[dims.length - 2];
  const width = dims[dims.length - 1];
  if (!Number.isFinite(height) || !Number.isFinite(width) || height <= 0 || width <= 0) {
    throw new Error(`Invalid depth dimensions: ${JSON.stringify(dims)}`);
  }
  return { height, width };
}

/**
 * Normalize raw depth values to 0–1 inverted range for parallax (matches former App.tsx logic).
 */
export function normalizeDepthMap(tensor: DepthTensor): NormalizedDepthMap {
  const { data, dims } = tensor;
  const { height, width } = depthTensorHeightWidth(dims);

  const normalizedData = new Float32Array(data.length);
  let min = Infinity;
  let max = -Infinity;

  for (let i = 0; i < data.length; i++) {
    const v = data[i];
    if (Number.isFinite(v)) {
      min = Math.min(min, v);
      max = Math.max(max, v);
    }
  }

  if (!Number.isFinite(min) || !Number.isFinite(max)) {
    throw new Error('Depth tensor contains no finite values');
  }

  const range = max - min || 1;
  for (let i = 0; i < data.length; i++) {
    normalizedData[i] = 1.0 - ((data[i] - min) / range);
  }

  return { data: normalizedData, width, height };
}

/** Map fetch/CDN failures to user-facing offline messages. */
export function classifyDepthLoadError(error: unknown): { phase: DepthLoadPhase; message: string } {
  const raw = error instanceof Error ? error.message : String(error);
  const lower = raw.toLowerCase();

  if (
    lower.includes('failed to fetch') ||
    lower.includes('networkerror') ||
    lower.includes('network error') ||
    lower.includes('load failed') ||
    lower.includes('err_connection') ||
    lower.includes('ecconnreset') ||
    lower.includes('offline')
  ) {
    return {
      phase: 'offline',
      message:
        'Depth model download blocked (offline or restricted network). Shaders still work — depth effects need model files from Hugging Face CDN.',
    };
  }

  if (lower.includes('aborted') || lower.includes('abort')) {
    return { phase: 'cancelled', message: 'Depth model load cancelled.' };
  }

  return { phase: 'error', message: `Failed to load depth model: ${raw}` };
}
