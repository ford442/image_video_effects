import { captureFrame } from './capture.js';
import { state, wasmRef } from './state.js';

export interface RecordingOptions {
  durationMs?: number;
  frameRate?: number;
  videoBitsPerSecond?: number;
  fps?: number;
  bitrate?: number;
  mimeType?: string;
}

let _recorder: MediaRecorder | null = null;
let _recordChunks: Blob[] = [];
let _recordResolve: ((blob: Blob) => void) | null = null;
let _recordCanvas: HTMLCanvasElement | null = null;
let _recordCtx: CanvasRenderingContext2D | null = null;
let _recordRafId: number | null = null;
let _recordFrameActive = false;
let _recordAutoStopTimer: ReturnType<typeof setTimeout> | null = null;

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

export function startRecording(
  canvasElement: HTMLCanvasElement,
  options: RecordingOptions = {},
): Promise<Blob> {
  return new Promise((resolve, reject) => {
    if (_recorder && _recorder.state !== 'inactive') {
      reject(new Error('[WASM Recording] Recording already in progress'));
      return;
    }

    const fps = options.fps ?? options.frameRate ?? 30;
    const bitrate = options.bitrate ?? options.videoBitsPerSecond ?? 5000000;
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
  if (_recorder && _recorder.state !== 'inactive') {
    _recorder.stop();
  }
}

export async function recordAndDownload(
  canvasElement: HTMLCanvasElement,
  durationMs = 8000,
  filename = 'recording.webm',
): Promise<void> {
  const blob = await startRecording(canvasElement, { durationMs });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
