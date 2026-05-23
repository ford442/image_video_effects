/**
 * Pixelocity WASM Renderer Bridge
 *
 * This module provides a JavaScript interface to the C++ WebGPU renderer.
 * It mirrors the TypeScript Renderer API for drop-in compatibility.
 */

// The WASM module instance
let wasmModule = null;
let canvas = null;

// Renderer state
const state = {
  initialized: false,
  activeShader: null,
  canvasWidth: 0,
  canvasHeight: 0,
  time: 0,
  mouseX: 0.5,
  mouseY: 0.5,
  mouseDown: false,
  zoomParams: [0.5, 0.5, 0.5, 0.5],
  ripples: []
};

/**
 * Initialize the WASM renderer
 * @param {HTMLCanvasElement} canvasElement - The canvas to render to
 * @returns {Promise<boolean>} Success status
 */
export async function initWasmRenderer(canvasElement) {
  if (state.initialized) {
    console.warn('WASM renderer already initialized');
    return true;
  }

  canvas = canvasElement;
  state.canvasWidth = canvas.width || 2048;
  state.canvasHeight = canvas.height || 2048;

  return new Promise((resolve) => {
    const pathname = window.location.pathname;
    const basePath = pathname.endsWith('/')
      ? pathname.slice(0, -1)
      : pathname.replace(/\/[^/]*$/, '');
    const wasmJsPath = basePath + '/wasm/pixelocity_wasm.js';
    const wasmBinaryPath = basePath + '/wasm/pixelocity_wasm.wasm';

    console.log('[WASM] Loading from:', wasmJsPath);

    if (window.PixelocityWASM) {
      initializeModule(window.PixelocityWASM, wasmBinaryPath, resolve);
      return;
    }

    const script = document.createElement('script');
    script.src = wasmJsPath;
    script.async = true;

    script.onload = () => {
      if (!window.PixelocityWASM) {
        console.error('[WASM] PixelocityWASM not found on window after script load');
        resolve(false);
        return;
      }
      initializeModule(window.PixelocityWASM, wasmBinaryPath, resolve);
    };

    script.onerror = (err) => {
      console.error('[WASM] Failed to load script:', err);
      resolve(false);
    };

    document.head.appendChild(script);
  });
}

/**
 * Initialize the Emscripten module and the C++ renderer
 */
async function initializeModule(factory, wasmBinaryPath, resolve) {
  try {
    wasmModule = await factory({
      locateFile: (path) => {
        if (path.endsWith('.wasm')) return wasmBinaryPath;
        return path;
      }
    });

    if (typeof wasmModule.ccall !== 'function') {
      console.warn('[WASM] Module loaded but ccall unavailable — stub build detected. Upload a real emcc binary to public/wasm/.');
      resolve(false);
      return;
    }

    // Use { async: true } so ccall returns a Promise that resolves after the
    // Asyncify-suspended C++ function completes.  Without this, ccall returns 0
    // immediately when WASM suspends inside wgpuInstanceWaitAny (waiting for the
    // browser WebGPU adapter/device Promise), causing a false "init failed" error.
    const result = await wasmModule.ccall(
      'initWasmRenderer',
      'number',
      ['number', 'number'],
      [state.canvasWidth, state.canvasHeight],
      { async: true }
    );

    if (!result) {
      console.error('[WASM] Failed to initialize WASM renderer (C++ returned 0)');
      resolve(false);
      return;
    }

    state.initialized = true;
    console.log('✅ WASM Renderer initialized');
    resolve(true);
  } catch (err) {
    console.error('[WASM] Failed to initialize module:', err);
    resolve(false);
  }
}

/**
 * Shutdown the WASM renderer
 */
export function shutdownWasmRenderer() {
  if (!state.initialized || !wasmModule) return;

  wasmModule.ccall('shutdownWasmRenderer', null, [], []);
  wasmModule = null;
  state.initialized = false;
  console.log('🛑 WASM Renderer shutdown');
}

/**
 * Load a WGSL shader
 * @param {string} id - Shader identifier
 * @param {string} wgslCode - WGSL source code
 * @returns {boolean} Success status
 */
export function loadShader(id, wgslCode) {
  if (!state.initialized || !wasmModule) {
    console.error('Renderer not initialized');
    return false;
  }

  const idLen = wasmModule.lengthBytesUTF8(id) + 1;
  const idPtr = wasmModule._malloc(idLen);
  wasmModule.stringToUTF8(id, idPtr, idLen);

  const codeLen = wasmModule.lengthBytesUTF8(wgslCode) + 1;
  const codePtr = wasmModule._malloc(codeLen);
  wasmModule.stringToUTF8(wgslCode, codePtr, codeLen);

  let result;
  try {
    result = wasmModule.ccall(
      'loadShader',
      'number',
      ['number', 'number'],
      [idPtr, codePtr]
    );
  } finally {
    wasmModule._free(idPtr);
    wasmModule._free(codePtr);
  }

  return result !== 0;
}

/**
 * Set the active shader for rendering (legacy single-shader API).
 * Also enables slot 0 with this shader for backwards compatibility.
 * @param {string} id - Shader identifier
 */
export function setActiveShader(id) {
  if (!state.initialized || !wasmModule) return;

  const idLen = wasmModule.lengthBytesUTF8(id) + 1;
  const idPtr = wasmModule._malloc(idLen);
  wasmModule.stringToUTF8(id, idPtr, idLen);
  try {
    wasmModule.ccall('setActiveShader', null, ['number'], [idPtr]);
  } finally {
    wasmModule._free(idPtr);
  }

  state.activeShader = id;
}

/**
 * Assign a loaded shader to a slot (0-2).
 * @param {number} slotIndex - Slot index (0, 1, or 2)
 * @param {string} id - Shader identifier (empty string to disable the slot)
 */
export function setSlotShader(slotIndex, id) {
  if (!state.initialized || !wasmModule) return;

  const idLen = wasmModule.lengthBytesUTF8(id) + 1;
  const idPtr = wasmModule._malloc(idLen);
  wasmModule.stringToUTF8(id, idPtr, idLen);
  try {
    wasmModule.ccall('setSlotShader', null, ['number', 'number'], [slotIndex, idPtr]);
  } finally {
    wasmModule._free(idPtr);
  }
}

/**
 * Set the four zoom parameters for a specific slot.
 * @param {number} slotIndex - Slot index (0, 1, or 2)
 * @param {number} p1
 * @param {number} p2
 * @param {number} p3
 * @param {number} p4
 */
export function setSlotParams(slotIndex, p1, p2, p3, p4) {
  if (!state.initialized || !wasmModule) return;
  wasmModule.ccall(
    'setSlotParams',
    null,
    ['number', 'number', 'number', 'number', 'number'],
    [slotIndex, p1, p2, p3, p4]
  );
}

/**
 * Set the execution mode for a slot.
 * @param {number} slotIndex - Slot index (0, 1, or 2)
 * @param {number|string} mode - 0 or 'chained' for chained mode; 1 or 'parallel' for parallel mode
 */
export function setSlotMode(slotIndex, mode) {
  if (!state.initialized || !wasmModule) return;
  const modeInt = (mode === 'parallel' || mode === 1) ? 1 : 0;
  wasmModule.ccall('setSlotMode', null, ['number', 'number'], [slotIndex, modeInt]);
}

/**
 * Update uniform values and trigger a render frame.
 * @param {Object} uniforms - Uniform values
 */
export function updateUniforms(uniforms = {}) {
  if (!state.initialized || !wasmModule) return;

  if (uniforms.time !== undefined) state.time = uniforms.time;
  if (uniforms.mouseX !== undefined) state.mouseX = uniforms.mouseX;
  if (uniforms.mouseY !== undefined) state.mouseY = uniforms.mouseY;
  if (uniforms.mouseDown !== undefined) state.mouseDown = uniforms.mouseDown;
  if (uniforms.zoom_params) state.zoomParams = uniforms.zoom_params;

  // Push current time to C++ so time-based animations advance.
  wasmModule.ccall('setTime', null, ['number'], [state.time]);

  // Push global zoom params (per-slot params must be set via setSlotParams).
  wasmModule.ccall(
    'setZoomParams',
    null,
    ['number', 'number', 'number', 'number'],
    state.zoomParams
  );

  // Push mouse state.
  wasmModule.ccall('updateMousePos', null, ['number', 'number'], [state.mouseX, state.mouseY]);
  wasmModule.ccall('setMouseDown', null, ['number'], [state.mouseDown ? 1 : 0]);

  // Trigger one render frame.
  wasmModule.ccall('updateUniforms', null, [], []);
}

/**
 * Update mouse position (normalized 0-1 coordinates).
 * @param {number} x
 * @param {number} y
 */
export function updateMousePos(x, y) {
  if (!state.initialized || !wasmModule) return;
  state.mouseX = x;
  state.mouseY = y;
  wasmModule.ccall('updateMousePos', null, ['number', 'number'], [x, y]);
}

/**
 * Update mouse button pressed state.
 * @param {boolean} down - true when button is pressed
 */
export function setMouseDown(down) {
  if (!state.initialized || !wasmModule) return;
  state.mouseDown = down;
  wasmModule.ccall('setMouseDown', null, ['number'], [down ? 1 : 0]);
}

/**
 * Update audio frequency bands (0-1 normalized).
 * @param {number} bass
 * @param {number} mid
 * @param {number} treble
 */
export function updateAudioData(bass, mid, treble) {
  if (!state.initialized || !wasmModule) return;
  wasmModule.ccall('updateAudioData', null, ['number', 'number', 'number'], [bass, mid, treble]);
}

/**
 * Upload a depth map (Float32Array, one float per pixel, row-major) from the
 * AI depth estimation model.
 * @param {Float32Array} float32Data - Depth values (0=far, 1=near)
 * @param {number} width
 * @param {number} height
 */
export function updateDepthMap(float32Data, width, height) {
  if (!state.initialized || !wasmModule) return;

  const byteLen = float32Data.length * 4;
  const ptr = wasmModule._malloc(byteLen);
  wasmModule.HEAPF32.set(float32Data, ptr >> 2);
  try {
    wasmModule.ccall(
      'updateDepthMap',
      null,
      ['number', 'number', 'number'],
      [ptr, width, height]
    );
  } finally {
    wasmModule._free(ptr);
  }
}

/**
 * Set the active input source.
 * @param {number|string} source
 *   0 or 'none'       - no input (black placeholder)
 *   1 or 'image'      - static image
 *   2 or 'video'      - video / webcam frames
 *   3 or 'webcam'     - webcam (same as video in WASM)
 *   4 or 'generative' - procedural, no input required
 */
export function setInputSource(source) {
  if (!state.initialized || !wasmModule) return;
  const sourceMap = { none: 0, image: 1, video: 2, webcam: 3, generative: 4 };
  const sourceInt = typeof source === 'string'
    ? (sourceMap[source] ?? 0)
    : source;
  wasmModule.ccall('setInputSource', null, ['number'], [sourceInt]);
}

/**
 * Add a ripple effect at the given position
 * @param {number} x - Normalized X position (0-1)
 * @param {number} y - Normalized Y position (0-1)
 */
export function addRipple(x, y) {
  if (!state.initialized || !wasmModule) return;

  wasmModule.ccall('addRipple', null, ['number', 'number'], [x, y]);
  state.ripples.push({ x, y, time: state.time });
}

/**
 * Clear all ripples
 */
export function clearRipples() {
  if (!state.initialized || !wasmModule) return;

  wasmModule.ccall('clearRipples', null, [], []);
  state.ripples = [];
}

/**
 * Get current FPS
 * @returns {number} Frames per second
 */
export function getFPS() {
  if (!state.initialized || !wasmModule) return 0;

  return wasmModule.ccall('getFPS', 'number', [], []);
}

/**
 * Check if renderer is initialized.
 * @returns {boolean}
 */
export function isInitialized() {
  return state.initialized;
}

/**
 * Load a shader from a URL
 * @param {string} id - Shader identifier
 * @param {string} url - URL to fetch WGSL code from
 * @returns {Promise<boolean>}
 */
export async function loadShaderFromURL(id, url) {
  try {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    const wgslCode = await response.text();
    return loadShader(id, wgslCode);
  } catch (err) {
    console.error(`Failed to load shader from ${url}:`, err);
    return false;
  }
}

/**
 * Upload RGBA pixel data as an image (one-time load).
 * @param {Uint8Array|Uint8ClampedArray} rgbaPixels - RGBA bytes (width * height * 4)
 * @param {number} width
 * @param {number} height
 */
export function uploadImageData(rgbaPixels, width, height) {
  if (!state.initialized || !wasmModule) return;

  const ptr = wasmModule._malloc(rgbaPixels.length);
  wasmModule.HEAPU8.set(rgbaPixels, ptr);
  try {
    wasmModule.ccall('loadImageData', null, ['number', 'number', 'number'], [ptr, width, height]);
  } finally {
    wasmModule._free(ptr);
  }
}

/**
 * Upload RGBA pixel data as a video frame (called every frame).
 * The C++ side uses a persistent staging buffer to avoid per-frame heap allocation.
 * @param {Uint8Array|Uint8ClampedArray} rgbaPixels - RGBA bytes (width * height * 4)
 * @param {number} width
 * @param {number} height
 */
export function uploadVideoFrame(rgbaPixels, width, height) {
  if (!state.initialized || !wasmModule) return;

  const ptr = wasmModule._malloc(rgbaPixels.length);
  wasmModule.HEAPU8.set(rgbaPixels, ptr);
  try {
    wasmModule.ccall('uploadVideoFrame', null, ['number', 'number', 'number'], [ptr, width, height]);
  } finally {
    wasmModule._free(ptr);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PHASE 2: Canvas resizing
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Resize the rendering canvas and recreate all size-dependent GPU resources.
 * Call this whenever the display canvas dimensions change.
 * @param {number} newWidth  - New canvas width in pixels
 * @param {number} newHeight - New canvas height in pixels
 */
export function resizeCanvas(newWidth, newHeight) {
  if (!state.initialized || !wasmModule) return;
  if (newWidth <= 0 || newHeight <= 0) return;
  state.canvasWidth  = newWidth;
  state.canvasHeight = newHeight;
  wasmModule.ccall('resizeCanvas', null, ['number', 'number'], [newWidth, newHeight]);
}

// ─────────────────────────────────────────────────────────────────────────────
// PHASE 2: Frame capture / screenshot
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Capture the current rendered frame as RGBA8 pixel data.
 *
 * The capture is asynchronous (GPU readback via CopyTextureToBuffer + mapAsync).
 * This function polls requestAnimationFrame until the GPU has finished, then
 * converts the RGBA32Float frame data to RGBA8 and resolves the Promise.
 *
 * @returns {Promise<ImageData>} Resolves with an ImageData containing the frame pixels.
 */
export function captureFrame() {
  return new Promise((resolve, reject) => {
    if (!state.initialized || !wasmModule) {
      reject(new Error('[WASM] Renderer not initialized'));
      return;
    }

    // Kick off the async GPU readback.
    wasmModule.ccall('beginFrameCapture', null, [], []);

    // Poll until the GPU map operation completes.
    function poll() {
      const captureState = wasmModule.ccall('getFrameCaptureState', 'number', [], []);

      if (captureState === 2) {
        // Ready — read the pixel data from the mapped buffer.
        const w = wasmModule.ccall('getCanvasWidth',  'number', [], []);
        const h = wasmModule.ccall('getCanvasHeight', 'number', [], []);
        const byteLen = w * h * 4;
        const ptr = wasmModule._malloc(byteLen);
        let written = 0;
        try {
          written = wasmModule.ccall(
            'readCapturedFrame',
            'number',
            ['number', 'number'],
            [ptr, byteLen]
          );
        } catch (e) {
          wasmModule._free(ptr);
          wasmModule.ccall('endFrameCapture', null, [], []);
          reject(e);
          return;
        }

        if (written > 0) {
          // Copy out of WASM heap before freeing.
          const raw = new Uint8ClampedArray(wasmModule.HEAPU8.buffer, ptr, written).slice();
          wasmModule._free(ptr);
          wasmModule.ccall('endFrameCapture', null, [], []);
          resolve(new ImageData(raw, w, h));
        } else {
          wasmModule._free(ptr);
          wasmModule.ccall('endFrameCapture', null, [], []);
          reject(new Error('[WASM] readCapturedFrame returned 0 bytes'));
        }
      } else if (captureState === 3) {
        // Error state.
        reject(new Error('[WASM] Frame capture failed (GPU error)'));
      } else {
        // Still pending — try again next frame.
        requestAnimationFrame(poll);
      }
    }

    poll();
  });
}

/**
 * Take a screenshot of the current frame and download it as a PNG file.
 * Uses OffscreenCanvas when available (Chrome/Firefox), falls back to a
 * regular canvas element for Safari compatibility.
 * @param {string} [filename='screenshot.png'] - Download filename.
 * @returns {Promise<void>}
 */
export async function takeScreenshot(filename = 'screenshot.png') {
  const imageData = await captureFrame();

  let blob;
  if (typeof OffscreenCanvas !== 'undefined') {
    // Fast path: OffscreenCanvas is available (Chrome, Edge, Firefox).
    const offscreen = new OffscreenCanvas(imageData.width, imageData.height);
    const ctx = offscreen.getContext('2d');
    ctx.putImageData(imageData, 0, 0);
    blob = await offscreen.convertToBlob({ type: 'image/png' });
  } else {
    // Fallback for Safari: use a regular <canvas> element.
    blob = await new Promise((resolve) => {
      const tmpCanvas  = document.createElement('canvas');
      tmpCanvas.width  = imageData.width;
      tmpCanvas.height = imageData.height;
      const ctx = tmpCanvas.getContext('2d');
      ctx.putImageData(imageData, 0, 0);
      tmpCanvas.toBlob((b) => resolve(b), 'image/png');
    });
  }

  const url = URL.createObjectURL(blob);
  const a   = document.createElement('a');
  a.href    = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

// ─────────────────────────────────────────────────────────────────────────────
// PHASE 2: Video recording via MediaRecorder + canvas.captureStream()
// ─────────────────────────────────────────────────────────────────────────────

/** @type {MediaRecorder|null} */
let _recorder      = null;
/** @type {Blob[]} */
let _recordChunks  = [];
/** @type {((blob: Blob) => void)|null} */
let _recordResolve = null;

/**
 * Start recording the canvas output to a WebM video.
 *
 * The recording captures the canvas directly using canvas.captureStream(),
 * which works with WebGPU canvases in Chrome / Edge 113+.
 *
 * @param {HTMLCanvasElement} canvasElement - The canvas to record.
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

    if (!canvasElement) {
      reject(new Error('[WASM] No canvas element provided'));
      return;
    }

    // Prefer VP9 in WebM; fall back to browser default.
    const mimeType = MediaRecorder.isTypeSupported('video/webm;codecs=vp9')
      ? 'video/webm;codecs=vp9'
      : 'video/webm';

    let stream;
    try {
      stream = canvasElement.captureStream(frameRate);
    } catch (e) {
      reject(new Error(`[WASM] canvas.captureStream() failed: ${e.message}`));
      return;
    }

    _recordChunks  = [];
    _recordResolve = resolve;

    _recorder = new MediaRecorder(stream, { mimeType, videoBitsPerSecond });

    _recorder.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) _recordChunks.push(e.data);
    };

    _recorder.onstop = () => {
      const blob = new Blob(_recordChunks, { type: mimeType });
      _recordChunks  = [];
      const cb       = _recordResolve;
      _recordResolve = null;
      _recorder      = null;
      if (cb) cb(blob);
    };

    _recorder.onerror = (e) => {
      _recorder      = null;
      _recordChunks  = [];
      _recordResolve = null;
      reject(new Error(`[WASM] MediaRecorder error: ${e.error?.message ?? e}`));
    };

    // Collect data every 100 ms for low-latency chunks.
    _recorder.start(100);
    console.log(`[WASM] Recording started (${durationMs}ms, ${mimeType})`);

    // Auto-stop after requested duration.
    if (durationMs > 0) {
      setTimeout(() => stopRecording(), durationMs);
    }
  });
}

/**
 * Stop an in-progress recording immediately.
 * If no recording is in progress this is a no-op.
 */
export function stopRecording() {
  if (_recorder && _recorder.state === 'recording') {
    _recorder.stop();
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

// Default export
const wasmBridge = {
  initWasmRenderer,
  shutdownWasmRenderer,
  loadShader,
  loadShaderFromURL,
  setActiveShader,
  setSlotShader,
  setSlotParams,
  setSlotMode,
  updateUniforms,
  updateMousePos,
  setMouseDown,
  updateAudioData,
  updateDepthMap,
  setInputSource,
  addRipple,
  clearRipples,
  getFPS,
  isInitialized,
  uploadImageData,
  uploadVideoFrame,
  resizeCanvas,
  captureFrame,
  takeScreenshot,
  startRecording,
  stopRecording,
  recordAndDownload,
};

export default wasmBridge;

