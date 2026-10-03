import { captureFrame } from './capture.js';
import { readCanvasCopySrc, state, wasmRef } from './state.js';

/** One WebCodecs take (src/recording/gpuEncodeSupport.ts GpuEncodeSession). */
export interface WasmEncodeSession {
  readonly kind?: 'canvas' | 'readback';
  stop(): Promise<Blob>;
}

/**
 * WebCodecs starter, injected by WASMRenderer. The bridge is emitted unbundled
 * into public/wasm/, so it cannot import src/recording itself. It gets the RGBA
 * readback as its fallback frame source and uses the COPY_SRC canvas when it
 * can. Resolves null when no WebM codec is supported.
 */
export type WasmGpuEncodeStarter = (
  capture: () => Promise<ImageData>,
  opts: { width: number; height: number; fps: number; bitrate: number },
) => Promise<WasmEncodeSession | null>;

export interface RecordingOptions {
  durationMs?: number;
  frameRate?: number;
  videoBitsPerSecond?: number;
  fps?: number;
  bitrate?: number;
  mimeType?: string;
  /** WebCodecs encoder; the default whenever VideoEncoder exists. */
  gpuEncode?: WasmGpuEncodeStarter;
}

let _recorder: MediaRecorder | null = null;
let _recordChunks: Blob[] = [];
let _recordResolve: ((blob: Blob) => void) | null = null;
let _recordCanvas: HTMLCanvasElement | null = null;
let _recordCtx: CanvasRenderingContext2D | null = null;
let _recordRafId: number | null = null;
let _recordFrameActive = false;
let _recordAutoStopTimer: ReturnType<typeof setTimeout> | null = null;
let _encodeSession: WasmEncodeSession | null = null;
let _encodeStarting = false;
let _finishEncode: (() => void) | null = null;

function cleanupRecordingPump(): void {
  if (_recordRafId !== null) {
    cancelAnimationFrame(_recordRafId);
    _recordRafId = null;
  }
  if (_recordAutoStopTimer !== null) {
    clearTimeout(_recordAutoStopTimer);
    _recordAutoStopTimer = null;
  }
  _recordFrameActive = false;
  _recordCanvas = null;
  _recordCtx = null;
}

function hasVideoEncoder(): boolean {
  return typeof VideoEncoder !== 'undefined' && typeof VideoFrame !== 'undefined';
}

/** Same rule as forcesMediaRecorder() in src/recording/gpuEncodeSupport.ts. */
function forcesMediaRecorder(): boolean {
  try {
    return new URLSearchParams(window.location.search).get('record') === 'mediarecorder';
  } catch {
    return false;
  }
}

/**
 * Last-resort MediaRecorder pump, and the ONLY place recording creates a 2D
 * context (gated by WASMBridge.recording.test.ts). Reached only when
 * VideoEncoder is missing, no WebM codec is supported, the encoder failed to
 * start, or ?record=mediarecorder. The default path feeds the COPY_SRC canvas
 * or captureFrame() RGBA straight into a WebCodecs VideoFrame instead.
 */
function startGpuReadbackPump(drawCanvas: HTMLCanvasElement): void {
  _recordCanvas = drawCanvas;
  _recordCtx = drawCanvas.getContext('2d');
  _recordFrameActive = false;

  const pump = () => {
    if (!_recorder || _recorder.state !== 'recording') {
      cleanupRecordingPump();
      return;
    }

    if (!_recordFrameActive && state.initialized && wasmRef.module) {
      _recordFrameActive = true;
      captureFrame()
        .then((imgData) => {
          if (_recordCtx && _recordCanvas && _recorder && _recorder.state === 'recording') {
            _recordCtx.putImageData(imgData, 0, 0);
          }
        })
        .catch((err) => {
          console.warn('[WASM Recording] GPU readback frame skipped:', err);
        })
        .finally(() => {
          _recordFrameActive = false;
        });
    }

    _recordRafId = requestAnimationFrame(pump);
  };

  _recordRafId = requestAnimationFrame(pump);
}

export function setRecording(active: boolean): void {
  if (!state.initialized || !wasmRef.module) return;
  wasmRef.module.ccall('setRecording', null, ['number'], [active ? 1 : 0]);
}

export function isRecordingActive(): boolean {
  if (!state.initialized || !wasmRef.module) return false;
  return Boolean(wasmRef.module.ccall('isRecording', 'number', [], []));
}

/** Loaded artifact probed canvas COPY_SRC as supported and exports the setter. */
export function supportsCanvasCopySrc(): boolean {
  return typeof wasmRef.module?._setCanvasCopySrc === 'function' && readCanvasCopySrc() === true;
}

/**
 * Reconfigure the C++ swapchain with (or without) COPY_SRC for a WebCodecs take
 * (canvas_configure.json optIn.copySrc). Returns false when unsupported, or when
 * getConfiguration() shows the browser dropped the bit (then backs out).
 */
export function setCanvasCopySrc(enabled: boolean): boolean {
  const mod = wasmRef.module;
  if (!state.initialized || !mod || typeof mod._setCanvasCopySrc !== 'function') return false;
  if (enabled && readCanvasCopySrc() !== true) return false;
  try {
    if (!mod._setCanvasCopySrc(enabled ? 1 : 0)) return false;
  } catch (err) {
    console.warn('[WASM] canvas COPY_SRC reconfigure failed:', err);
    return false;
  }
  if (!enabled) return true;
  const ctx = wasmRef.canvas?.getContext('webgpu') as
    | (GPUCanvasContext & { getConfiguration?: () => GPUCanvasConfiguration | null })
    | null
    | undefined;
  const cfg = ctx?.getConfiguration?.();
  const copySrcBit = typeof GPUTextureUsage !== 'undefined' ? GPUTextureUsage.COPY_SRC : 0x01;
  if (cfg && typeof cfg.usage === 'number' && !(cfg.usage & copySrcBit)) {
    console.warn('[WASM] canvas COPY_SRC dropped by getConfiguration(); restoring render-only');
    mod._setCanvasCopySrc(0);
    return false;
  }
  return true;
}

function logRecordingFallback(reason: string, err?: unknown): void {
  if (err !== undefined) {
    console.warn(`[WASM Recording] fallback to MediaRecorder: ${reason}`, err);
  } else {
    console.warn(`[WASM Recording] fallback to MediaRecorder: ${reason}`);
  }
}

export async function startRecording(
  canvasElement: HTMLCanvasElement,
  options: RecordingOptions = {},
): Promise<Blob> {
  if ((_recorder && _recorder.state !== 'inactive') || _encodeSession || _encodeStarting) {
    throw new Error('[WASM Recording] Recording already in progress');
  }

  const fps = options.fps ?? options.frameRate ?? 30;
  const bitrate = options.bitrate ?? options.videoBitsPerSecond ?? 5000000;

  if (forcesMediaRecorder()) {
    logRecordingFallback('?record=mediarecorder');
  } else if (!hasVideoEncoder()) {
    logRecordingFallback('VideoEncoder / VideoFrame unavailable');
  } else if (!options.gpuEncode) {
    logRecordingFallback('no WebCodecs starter injected');
  } else if (state.initialized && wasmRef.module) {
    _encodeStarting = true;
    let session: WasmEncodeSession | null = null;
    try {
      session = await options.gpuEncode(captureFrame, {
        width: state.canvasWidth || canvasElement.width,
        height: state.canvasHeight || canvasElement.height,
        fps,
        bitrate,
      });
      if (!session) logRecordingFallback('no supported WebM codec for VideoEncoder');
    } catch (err) {
      logRecordingFallback('WebCodecs session failed to start', err);
    } finally {
      _encodeStarting = false;
    }
    if (session) return runEncodeSession(session, options.durationMs);
  }

  return startMediaRecorder(canvasElement, options, fps, bitrate);
}

function runEncodeSession(session: WasmEncodeSession, durationMs?: number): Promise<Blob> {
  _encodeSession = session;
  setRecording(true);
  console.log(`[WASM Recording] WebCodecs take started (source=${session.kind ?? 'unknown'})`);
  return new Promise((resolve, reject) => {
    _finishEncode = () => {
      _finishEncode = null;
      _encodeSession = null;
      session.stop()
        .then(resolve, reject)
        .finally(() => setRecording(false));
    };
    if (durationMs && durationMs > 0) {
      _recordAutoStopTimer = setTimeout(stopRecording, durationMs);
    }
  });
}

function startMediaRecorder(
  canvasElement: HTMLCanvasElement,
  options: RecordingOptions,
  fps: number,
  bitrate: number,
): Promise<Blob> {
  return new Promise((resolve, reject) => {
    const mimeType = options.mimeType || (
      MediaRecorder.isTypeSupported('video/webm;codecs=vp9')
        ? 'video/webm;codecs=vp9'
        : MediaRecorder.isTypeSupported('video/webm')
          ? 'video/webm'
          : 'video/mp4'
    );

    _recordChunks = [];
    _recordResolve = resolve;

    setRecording(true);

    try {
      let stream: MediaStream;
      if (state.initialized && wasmRef.module) {
        const offscreen = document.createElement('canvas');
        offscreen.width = canvasElement.width || 2048;
        offscreen.height = canvasElement.height || 2048;
        stream = offscreen.captureStream(fps);
        startGpuReadbackPump(offscreen);
      } else {
        stream = canvasElement.captureStream(fps);
      }

      _recorder = new MediaRecorder(stream, {
        mimeType,
        videoBitsPerSecond: bitrate,
      });
    } catch (err: unknown) {
      setRecording(false);
      cleanupRecordingPump();
      const message = err instanceof Error ? err.message : String(err);
      reject(new Error(`[WASM Recording] MediaRecorder failed: ${message}`));
      return;
    }

    _recorder.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) {
        _recordChunks.push(e.data);
      }
    };

    _recorder.onstop = () => {
      const blob = new Blob(_recordChunks, { type: mimeType });
      setRecording(false);
      cleanupRecordingPump();
      if (_recordResolve) {
        _recordResolve(blob);
        _recordResolve = null;
      }
      _recorder = null;
      _recordChunks = [];
    };

    _recorder.onerror = (e) => {
      setRecording(false);
      cleanupRecordingPump();
      const error = (e as ErrorEvent).error;
      reject(new Error(`[WASM Recording] MediaRecorder error: ${error}`));
      _recorder = null;
    };

    _recorder.start(100);

    if (options.durationMs && options.durationMs > 0) {
      _recordAutoStopTimer = setTimeout(() => {
        stopRecording();
      }, options.durationMs);
    }
  });
}

export function stopRecording(): void {
  if (_recordAutoStopTimer !== null) {
    clearTimeout(_recordAutoStopTimer);
    _recordAutoStopTimer = null;
  }
  if (_finishEncode) {
    _finishEncode();
    return;
  }
  if (_recorder && _recorder.state !== 'inactive') {
    _recorder.stop();
  }
}

export async function recordAndDownload(
  canvasElement: HTMLCanvasElement,
  durationMs = 8000,
  filename = 'recording.webm',
  gpuEncode?: WasmGpuEncodeStarter,
): Promise<void> {
  const blob = await startRecording(canvasElement, { durationMs, gpuEncode });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
