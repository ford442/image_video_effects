/**
 * Pixelocity WASM Renderer Bridge
 * 
 * This module provides a JavaScript interface to the C++ WebGPU renderer.
 * It mirrors the TypeScript Renderer API for drop-in compatibility.
 */

// The WASM module instance
let wasmModule = null;
let canvas = null;
let ctx = null;

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

  try {
    // Dynamically import the WASM module
    const wasm = await import('./pixelocity_wasm.js');
    wasmModule = await wasm.default();

    // Initialize the C++ renderer
    const result = wasmModule.ccall(
      'initWasmRenderer',
      'number',
      ['number', 'number'],
      [state.canvasWidth, state.canvasHeight]
    );

    if (result !== 0) {
      console.error('Failed to initialize WASM renderer');
      return false;
    }

    state.initialized = true;
    console.log('✅ WASM Renderer initialized');
    return true;
  } catch (err) {
    console.error('Failed to load WASM module:', err);
    return false;
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

  // Allocate memory for the strings
  const idLen = wasmModule.lengthBytesUTF8(id) + 1;
  const idPtr = wasmModule._malloc(idLen);
  wasmModule.stringToUTF8(id, idPtr, idLen);

  const codeLen = wasmModule.lengthBytesUTF8(wgslCode) + 1;
  const codePtr = wasmModule._malloc(codeLen);
  wasmModule.stringToUTF8(wgslCode, codePtr, codeLen);

  const result = wasmModule.ccall(
    'loadShader',
    'number',
    ['number', 'number'],
    [idPtr, codePtr]
  );

  // Free allocated memory
  wasmModule._free(idPtr);
  wasmModule._free(codePtr);

  return result === 0;
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
  wasmModule.ccall('setActiveShader', null, ['number'], [idPtr]);
  wasmModule._free(idPtr);

  state.activeShader = id;
}

/**
 * Update uniform values
 * @param {Object} uniforms - Uniform values
 */
export function updateUniforms(uniforms = {}) {
  if (!state.initialized || !wasmModule) return;

  state.time = uniforms.time ?? state.time;
  state.mouseX = uniforms.mouseX ?? state.mouseX;
  state.mouseY = uniforms.mouseY ?? state.mouseY;
  state.mouseDown = uniforms.mouseDown ?? state.mouseDown;
  
  if (uniforms.zoomParams) {
    state.zoomParams = uniforms.zoomParams;
  }

  wasmModule.ccall(
    'updateUniforms',
    null,
    ['number', 'number', 'number', 'number', 'number', 'number', 'number', 'number'],
    [
      state.time,
      state.mouseX,
      state.mouseY,
      state.mouseDown ? 1 : 0,
      state.zoomParams[0],
      state.zoomParams[1],
      state.zoomParams[2],
      state.zoomParams[3]
    ]
  );
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
 * Check if renderer is initialized
 * @returns {boolean}
 */
export function isInitialized() {
  if (!wasmModule) return false;
  return wasmModule.ccall('isRendererInitialized', 'number', [], []) !== 0;
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

// Default export
export default {
  initWasmRenderer,
  shutdownWasmRenderer,
  loadShader,
  loadShaderFromURL,
  setActiveShader,
  updateUniforms,
  addRipple,
  clearRipples,
  getFPS,
  isInitialized
};
