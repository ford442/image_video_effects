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
 * Initialize the WASM renderer using script tag loading
 * This is more reliable than ES module dynamic imports for Emscripten UMD output
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
    // Determine the correct base path for WASM files
    const pathname = window.location.pathname;
    const basePath = pathname.endsWith('/') 
      ? pathname.slice(0, -1) 
      : pathname.replace(/\/[^/]*$/, '');
    const wasmJsPath = basePath + '/wasm/pixelocity_wasm.js';
    const wasmBinaryPath = basePath + '/wasm/pixelocity_wasm.wasm';
    
    console.log('[WASM] Loading from:', wasmJsPath);
    console.log('[WASM] Binary path:', wasmBinaryPath);
    
    // Check if already loaded (e.g., from previous session)
    if (window.PixelocityWASM) {
      console.log('[WASM] Module already loaded on window');
      initializeModule(window.PixelocityWASM, wasmBinaryPath, resolve);
      return;
    }
    
    // Load script dynamically
    const script = document.createElement('script');
    script.src = wasmJsPath;
    script.async = true;
    
    script.onload = () => {
      if (!window.PixelocityWASM) {
        console.error('[WASM] PixelocityWASM not found on window after script load');
        console.log('[WASM] window keys:', Object.keys(window).filter(k => k.includes('WASM') || k.includes('Pixel')));
        resolve(false);
        return;
      }
      console.log('[WASM] Script loaded, initializing module...');
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
    console.log('[WASM] Factory type:', typeof factory);
    
    // Initialize the module with locateFile to find the .wasm binary
    wasmModule = await factory({
      locateFile: (path) => {
        if (path.endsWith('.wasm')) {
          return wasmBinaryPath;
        }
        return path;
      }
    });

    if (typeof wasmModule.ccall !== 'function') {
      console.warn('[WASM] Module loaded but ccall unavailable (stub build — upload real emcc binary to public/wasm/)');
      resolve(false);
      return;
    }

    console.log('[WASM] Module initialized, calling C++ init...');

    // Initialize the C++ renderer
    const result = wasmModule.ccall(
      'initWasmRenderer',
      'number',
      ['number', 'number'],
      [state.canvasWidth, state.canvasHeight]
    );

    if (result !== 0) {
      console.error('Failed to initialize WASM renderer');
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

  // Allocate memory for the strings
  const idLen = wasmModule.lengthBytesUTF8(id) + 1;
  const idPtr = wasmModule._malloc(idLen);
  wasmModule.stringToUTF8(id, idPtr, idLen);

  const codeLen = wasmModule.lengthBytesUTF8(wgslCode) + 1;
  const codePtr = wasmModule._malloc(codeLen);
  wasmModule.stringToUTF8(wgslCode, codePtr, codeLen);

  // Call the C++ function
  const result = wasmModule.ccall(
    'loadShader',
    'number',
    ['number', 'number'],
    [idPtr, codePtr]
  );

  // Free memory
  wasmModule._free(idPtr);
  wasmModule._free(codePtr);

  return result !== 0;
}

/**
 * Load a shader from a URL
 * @param {string} id - Shader identifier
 * @param {string} url - URL to fetch WGSL from
 * @returns {Promise<boolean>} Success status
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
    // Fallback to local /shaders/ path if API URL failed
    if (!url.startsWith('/shaders/')) {
      console.warn(`API fetch failed for ${id}, trying local fallback...`);
      try {
        const fallback = await fetch(`/shaders/${id}.wgsl`);
        if (fallback.ok) {
          return loadShader(id, await fallback.text());
        }
      } catch (_) {
        // Both failed
      }
    }
    console.error(`Failed to load shader from ${url}:`, err);
    return false;
  }
}

/** Switch to a previously loaded shader. */
export function setActiveShader(id) {
  if (!state.initialized || !wasmModule) return;

  const idLen = wasmModule.lengthBytesUTF8(id) + 1;
  const idPtr = wasmModule._malloc(idLen);
  wasmModule.stringToUTF8(id, idPtr, idLen);

  wasmModule.ccall('setActiveShader', null, ['number'], [idPtr]);

  wasmModule._free(idPtr);
  state.activeShader = id;
}

/** Add a ripple at normalized coordinates. */
export function addRipple(x, y) {
  if (!state.initialized || !wasmModule) return;
  wasmModule.ccall('addRipple', null, ['number', 'number'], [x, y]);
}

/** Clear all ripples. */
export function clearRipples() {
  if (!state.initialized || !wasmModule) return;
  wasmModule.ccall('clearRipples', null, [], []);
}

/** Get current FPS. */
export function getFPS() {
  if (!state.initialized || !wasmModule) return 0;
  return wasmModule.ccall('getFPS', 'number', [], []);
}

/** Check if renderer is initialized. */
export function isInitialized() {
  return state.initialized;
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

  wasmModule.ccall(
    'loadImageData',
    null,
    ['number', 'number', 'number'],
    [ptr, width, height]
  );

  wasmModule._free(ptr);
}

/**
 * Upload RGBA pixel data as a video frame.
 * @param {Uint8Array|Uint8ClampedArray} rgbaPixels - RGBA bytes
 * @param {number} width
 * @param {number} height
 */
export function uploadVideoFrame(rgbaPixels, width, height) {
  if (!state.initialized || !wasmModule) return;

  const ptr = wasmModule._malloc(rgbaPixels.length);
  wasmModule.HEAPU8.set(rgbaPixels, ptr);

  wasmModule.ccall(
    'uploadVideoFrame',
    null,
    ['number', 'number', 'number'],
    [ptr, width, height]
  );

  wasmModule._free(ptr);
}

/**
 * Update uniform values
 * @param {Object} uniforms - Object with time, mouseX, mouseY, mouseDown, zoom_params
 */
export function updateUniforms(uniforms) {
  if (!state.initialized || !wasmModule) return;

  // Update local state
  if (uniforms.time !== undefined) state.time = uniforms.time;
  if (uniforms.mouseX !== undefined) state.mouseX = uniforms.mouseX;
  if (uniforms.mouseY !== undefined) state.mouseY = uniforms.mouseY;
  if (uniforms.mouseDown !== undefined) state.mouseDown = uniforms.mouseDown;
  if (uniforms.zoom_params) state.zoomParams = uniforms.zoom_params;

  // Call C++ update (this triggers a render frame)
  wasmModule.ccall('updateUniforms', null, [], []);
}

// For compatibility with older code
const wasmBridge = {
  initWasmRenderer,
  shutdownWasmRenderer,
  loadShader,
  loadShaderFromURL,
  setActiveShader,
  updateUniforms,
  addRipple,
  clearRipples,
  getFPS,
  isInitialized,
  uploadImageData,
  uploadVideoFrame
};

export default wasmBridge;
