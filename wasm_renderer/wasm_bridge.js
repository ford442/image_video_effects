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

    const result = wasmModule.ccall(
      'initWasmRenderer',
      'number',
      ['number', 'number'],
      [state.canvasWidth, state.canvasHeight]
    );

    if (!result) {
      console.error('Failed to initialize WASM renderer (C++ returned 0)');
      resolve(false);
      return;
    }

    state.initialized = true;
    console.log('✅ WASM Renderer initialized');
    resolve(true);
  } catch (err) {
    console.error('Failed to initialize module:', err);
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
 * Set the active shader for rendering
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
 * Update uniform values.
 * State setters (updateMousePos, updateAudioData) should be called before
 * this function to push values into C++ before the render call.
 * @param {Object} uniforms - Uniform values
 */
export function updateUniforms(uniforms = {}) {
  if (!state.initialized || !wasmModule) return;

  if (uniforms.time !== undefined) state.time = uniforms.time;
  if (uniforms.mouseX !== undefined) state.mouseX = uniforms.mouseX;
  if (uniforms.mouseY !== undefined) state.mouseY = uniforms.mouseY;
  if (uniforms.mouseDown !== undefined) state.mouseDown = uniforms.mouseDown;
  if (uniforms.zoom_params) state.zoomParams = uniforms.zoom_params;

  // Propagate mouse/param state to C++ before triggering the render.
  wasmModule.ccall('updateMousePos', null, ['number', 'number'], [state.mouseX, state.mouseY]);

  // C++ updateUniforms() takes no parameters — it reads internal state and
  // triggers a Render() call.
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
 * Returns the local JS state flag which is only set to true after the C++
 * renderer confirms successful initialization (ccall 'initWasmRenderer' returns 1).
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

// Default export
export default {
  initWasmRenderer,
  shutdownWasmRenderer,
  loadShader,
  loadShaderFromURL,
  setActiveShader,
  updateUniforms,
  updateMousePos,
  updateAudioData,
  addRipple,
  clearRipples,
  getFPS,
  isInitialized,
  uploadImageData,
  uploadVideoFrame
};

