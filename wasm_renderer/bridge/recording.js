// Video recording via MediaRecorder and GPU readback pump.

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

async function pumpReadbackRecordingFrame() {
  if (!_recorder || _recorder.state !== 'recording') return;
  if (_recordFrameActive) {
    _recordRafId = requestAnimationFrame(pumpReadbackRecordingFrame);
    return;
  }

  _recordFrameActive = true;
  try {
    const imageData = await captureFrame();
    if (_recordCtx && _recordCanvas) {
      if (_recordCanvas.width !== imageData.width) _recordCanvas.width = imageData.width;
      if (_recordCanvas.height !== imageData.height) _recordCanvas.height = imageData.height;
      _recordCtx.putImageData(imageData, 0, 0);
    }
  } catch (e) {
    console.warn('[WASM] Recording frame readback failed:', e);
  } finally {
    _recordFrameActive = false;
    if (_recorder && _recorder.state === 'recording') {
      _recordRafId = requestAnimationFrame(pumpReadbackRecordingFrame);
    }
  }
}

function beginMediaRecorder(stream, mimeType, videoBitsPerSecond, durationMs, resolve, reject) {
  _recordChunks = [];
  _recordResolve = resolve;

  _recorder = new MediaRecorder(stream, { mimeType, videoBitsPerSecond });

  _recorder.ondataavailable = (e) => {
    if (e.data && e.data.size > 0) _recordChunks.push(e.data);
  };

  _recorder.onstop = () => {
    cleanupRecordingPump();
    const blob = new Blob(_recordChunks, { type: mimeType });
    _recordChunks = [];
    const cb = _recordResolve;
    _recordResolve = null;
    _recorder = null;
    setRecording(false);
    if (cb) cb(blob);
  };

  _recorder.onerror = (e) => {
    cleanupRecordingPump();
    _recorder = null;
    _recordChunks = [];
    _recordResolve = null;
    setRecording(false);
    reject(new Error(`[WASM] MediaRecorder error: ${e.error?.message ?? e}`));
  };

  _recorder.start(100);
  setRecording(true);

  if (durationMs > 0) {
    _recordAutoStopTimer = setTimeout(() => stopRecording(), durationMs);
  }
}

function startReadbackRecording(resolve, reject, { durationMs, frameRate, videoBitsPerSecond }) {
  const w = state.canvasWidth || 1920;
  const h = state.canvasHeight || 1080;

  _recordCanvas = document.createElement('canvas');
  _recordCanvas.width = w;
  _recordCanvas.height = h;
  _recordCtx = _recordCanvas.getContext('2d', { willReadFrequently: true });

  const mimeType = MediaRecorder.isTypeSupported('video/webm;codecs=vp9')
    ? 'video/webm;codecs=vp9'
    : 'video/webm';

  let stream;
  try {
    stream = _recordCanvas.captureStream(frameRate);
  } catch (e) {
    cleanupRecordingPump();
    reject(new Error(`[WASM] readback canvas.captureStream() failed: ${e.message}`));
    return;
  }

  beginMediaRecorder(stream, mimeType, videoBitsPerSecond, durationMs, resolve, reject);
  console.log(`[WASM] Readback recording started (${durationMs}ms, ${w}x${h}, ${mimeType})`);
  pumpReadbackRecordingFrame();
}

export function setRecording(recording) {
  if (!state.initialized || !wasmModule) return;
  wasmModule.ccall('setRecording', null, ['number'], [recording ? 1 : 0]);
}

export function isRecordingActive() {
  if (!state.initialized || !wasmModule) return false;
  return wasmModule.ccall('isRecording', 'number', [], []) === 1;
}

/**
 * Start recording the renderer output to a WebM video.
 *
 * When the WASM renderer is initialized, frames are captured via GPU readback
 * (`captureFrame`) into an offscreen canvas — the DOM canvas is blank because
 * `PresentToSurface()` drives the WebGPU swap chain directly.
 *
 * @param {HTMLCanvasElement} canvasElement - Fallback capture target when WASM is not active.
 * @param {object}            [options]
 * @param {number}            [options.durationMs=8000]       - Auto-stop after this many ms.
 * @param {number}            [options.frameRate=60]          - Target capture frame rate.
 * @param {number}            [options.videoBitsPerSecond=8e6] - Encoder bit-rate.
 * @returns {Promise<Blob>} Resolves with the recorded WebM Blob when recording stops.
 */
export function startRecording(canvasElement, {
  durationMs          = 8000,
  frameRate           = 60,
  videoBitsPerSecond  = 8_000_000
} = {}) {
  return new Promise((resolve, reject) => {
    if (_recorder && _recorder.state === 'recording') {
      reject(new Error('[WASM] Recording already in progress'));
      return;
    }

    const mimeType = MediaRecorder.isTypeSupported('video/webm;codecs=vp9')
      ? 'video/webm;codecs=vp9'
      : 'video/webm';

    if (state.initialized && wasmModule) {
      startReadbackRecording(resolve, reject, { durationMs, frameRate, videoBitsPerSecond });
      return;
    }

    if (!canvasElement) {
      reject(new Error('[WASM] No canvas element provided'));
      return;
    }

    let stream;
    try {
      stream = canvasElement.captureStream(frameRate);
    } catch (e) {
      reject(new Error(`[WASM] canvas.captureStream() failed: ${e.message}`));
      return;
    }

    beginMediaRecorder(stream, mimeType, videoBitsPerSecond, durationMs, resolve, reject);
    console.log(`[WASM] Canvas-stream recording started (${durationMs}ms, ${mimeType})`);
  });
}

/**
 * Stop an in-progress recording immediately.
 * If no recording is in progress this is a no-op.
 */
export function stopRecording() {
  if (_recorder && _recorder.state === 'recording') {
    _recorder.stop();
  } else {
    cleanupRecordingPump();
    setRecording(false);
  }
}

/**
 * Record the canvas for `durationMs` milliseconds and automatically download
 * the resulting WebM file.
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
