// src/wasm/bridge/recording.js
// Video recording via MediaRecorder and GPU readback pump.

import { captureFrame } from './capture.js';
import { state, wasmRef } from './state.js';

/** @type {MediaRecorder|null} */
let _recorder      = null;
/** @type {Blob[]} */
let _recordChunks  = [];
/** @type {((blob: Blob) => void)|null} */
let _recordResolve = null;
/** @type {HTMLCanvasElement|null} */
let _recordCanvas  = null;
/** @type {CanvasRenderingContext2D|null} */
let _recordCtx     = null;
/** @type {number|null} */
let _recordRafId   = null;
let _recordFrameActive = false;
/** @type {ReturnType<typeof setTimeout>|null} */
let _recordAutoStopTimer = null;

function cleanupRecordingPump() {
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

function startGpuReadbackPump(drawCanvas) {
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

/**
 * Set recording mode in C++ renderer
 * @param {boolean} active
 */
export function setRecording(active) {
  if (!state.initialized || !wasmRef.module) return;
  wasmRef.module.ccall('setRecording', null, ['number'], [active ? 1 : 0]);
}

/**
 * Check if C++ recording mode is active
 * @returns {boolean}
 */
export function isRecordingActive() {
  if (!state.initialized || !wasmRef.module) return false;
  return Boolean(wasmRef.module.ccall('isRecording', 'number', [], []));
}

/**
 * Start recording video from the rendering canvas.
 * @param {HTMLCanvasElement} canvasElement
 * @param {Object} [options]
 * @param {number} [options.fps=30]
 * @param {number} [options.bitrate=5000000]
 * @param {string} [options.mimeType]
 * @param {number} [options.durationMs]
 * @returns {Promise<Blob>} Resolves with WebM/MP4 Blob when recording completes
 */
export function startRecording(canvasElement, options = {}) {
  return new Promise((resolve, reject) => {
    if (_recorder && _recorder.state !== 'inactive') {
      reject(new Error('[WASM Recording] Recording already in progress'));
      return;
    }

    const fps        = options.fps ?? 30;
    const bitrate    = options.bitrate ?? 5000000;
    const mimeType   = options.mimeType || (
      MediaRecorder.isTypeSupported('video/webm;codecs=vp9')
        ? 'video/webm;codecs=vp9'
        : MediaRecorder.isTypeSupported('video/webm')
        ? 'video/webm'
        : 'video/mp4'
    );

    _recordChunks  = [];
    _recordResolve = resolve;

    setRecording(true);

    try {
      let stream;
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
    } catch (err) {
      setRecording(false);
      cleanupRecordingPump();
      reject(new Error(`[WASM Recording] MediaRecorder failed: ${err.message}`));
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
      reject(new Error(`[WASM Recording] MediaRecorder error: ${e.error}`));
      _recorder = null;
    };

    _recorder.start(100); // Collect data every 100ms

    if (options.durationMs && options.durationMs > 0) {
      _recordAutoStopTimer = setTimeout(() => {
        stopRecording();
      }, options.durationMs);
    }
  });
}

/**
 * Stop active recording and return the recorded Blob.
 */
export function stopRecording() {
  if (_recordAutoStopTimer !== null) {
    clearTimeout(_recordAutoStopTimer);
    _recordAutoStopTimer = null;
  }
  if (_recorder && _recorder.state !== 'inactive') {
    _recorder.stop();
  }
}

/**
 * Convenience helper: record canvas for durationMs and trigger file download.
 *
 * @param {HTMLCanvasElement} canvasElement
 * @param {number}            [durationMs=8000]
 * @param {string}            [filename='recording.webm']
 * @returns {Promise<void>}
 */
export async function recordAndDownload(
  canvasElement,
  durationMs = 8000,
  filename   = 'recording.webm'
) {
  const blob = await startRecording(canvasElement, { durationMs });
  const url  = URL.createObjectURL(blob);
  const a    = document.createElement('a');
  a.href     = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
