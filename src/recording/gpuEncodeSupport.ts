/**
 * gpuEncodeSupport.ts
 *
 * Main-bundle half of Recording 2.0: feature detection, the opt-in toggle, and
 * the lazy loader. The encoder + webm-muxer live in the "gpu-encode" chunk.
 */

import type * as GpuEncoderModule from './gpuEncoder';

export const GPU_ENCODE_STORAGE_KEY = 'pixelocity.recording.gpuEncode';

/** WebCodecs encode + VideoFrame construction are both required. */
export function isGpuEncodeAvailable(): boolean {
  return typeof VideoEncoder !== 'undefined' && typeof VideoFrame !== 'undefined';
}

export function readGpuEncodePreference(): boolean {
  try {
    return window.localStorage.getItem(GPU_ENCODE_STORAGE_KEY) === '1';
  } catch {
    return false;
  }
}

export function writeGpuEncodePreference(enabled: boolean): void {
  try {
    window.localStorage.setItem(GPU_ENCODE_STORAGE_KEY, enabled ? '1' : '0');
  } catch {
    // Private mode / blocked storage: the toggle still works for this session.
  }
}

/** `?record=mediarecorder` forces the legacy MediaRecorder path on every backend. */
export function forcesMediaRecorder(
  search: string = typeof window !== 'undefined' ? window.location.search : '',
): boolean {
  return new URLSearchParams(search).get('record') === 'mediarecorder';
}

/** Where a WebCodecs take gets its frames from (TS or WASM backend). */
export interface GpuEncodeFrames {
  canvas: HTMLCanvasElement;
  /** Swapchain can take COPY_SRC (boot / WASM init probe was green). */
  supportsCanvasCopySrc(): boolean;
  /** Reconfigure the swapchain for the take; false when refused. */
  setCanvasCopySrc(enabled: boolean): boolean;
  /** RGBA8 readback (WASM beginFrameCapture), null when unavailable. */
  readback: (() => Promise<ImageData>) | null;
}

/** One WebCodecs take. stop() also restores the render-only swapchain. */
export interface GpuEncodeSession {
  readonly kind: 'canvas' | 'readback';
  stop(): Promise<Blob>;
}

/**
 * Start a WebCodecs take on whichever frame source the backend offers: the
 * canvas VideoFrame when COPY_SRC is available (canvas_configure.json
 * optIn.copySrc), else the RGBA readback. Resolves null when there is no source
 * or no supported WebM codec (caller falls back to MediaRecorder). The
 * swapchain goes back to render-only on stop, on null and on throw.
 */
export async function startGpuEncodeSession(
  frames: GpuEncodeFrames,
  opts: GpuEncoderModule.GpuEncodeOptions,
): Promise<GpuEncodeSession | null> {
  const { GpuEncodeRecorder, canvasFrameSource, readbackFrameSource } = await loadGpuEncoder();
  let source: GpuEncoderModule.GpuFrameSource;
  if (frames.supportsCanvasCopySrc() && frames.setCanvasCopySrc(true)) {
    source = canvasFrameSource(frames.canvas);
  } else if (frames.readback) {
    source = readbackFrameSource(frames.readback);
  } else {
    return null;
  }
  const restore = () => {
    if (source.kind === 'canvas') frames.setCanvasCopySrc(false);
  };

  let recorder: GpuEncoderModule.GpuEncodeRecorder | null;
  try {
    recorder = await GpuEncodeRecorder.start(source, opts);
  } catch (e) {
    restore();
    throw e;
  }
  if (!recorder) {
    restore();
    return null;
  }
  const started = recorder;
  return {
    kind: source.kind,
    stop: () => started.stop().finally(restore),
  };
}

let modulePromise: Promise<typeof GpuEncoderModule> | null = null;

export function loadGpuEncoder(): Promise<typeof GpuEncoderModule> {
  if (!modulePromise) {
    modulePromise = import(/* webpackChunkName: "gpu-encode" */ './gpuEncoder').catch((err) => {
      modulePromise = null;
      throw err;
    });
  }
  return modulePromise;
}
