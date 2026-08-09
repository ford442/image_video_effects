// src/wasm/bridge/init.js
// WASM module load and renderer lifecycle.

import { formatCppInitFailure, readCppInitDiagnostics } from './diagnostics.js';
import { state, wasmRef } from './state.js';

/**
 * Initialize the WASM renderer
 * @param {HTMLCanvasElement} canvasElement - The canvas to render to
 * @returns {Promise<boolean>} Success status
 */
export async function initWasmRenderer(canvasElement) {
  if (state.initialized) {
    console.warn('[WASM] Renderer already initialized');
    return true;
  }

  wasmRef.canvas = canvasElement;
  state.canvasWidth = wasmRef.canvas.width || 2048;
  state.canvasHeight = wasmRef.canvas.height || 2048;
  state.initStartTime = performance.now();

  return new Promise((resolve) => {
    const pathname = window.location.pathname;
    const isUnderSubpath = pathname.startsWith('/image_video_effects/');
    const wasmJsPath = isUnderSubpath
      ? '/image_video_effects/wasm/pixelocity_wasm.js'
      : '/wasm/pixelocity_wasm.js';

    console.log(`[WASM] Loading from: ${wasmJsPath}`);
    console.log(`[WASM] Canvas size: ${state.canvasWidth}x${state.canvasHeight}`);

    let handled = false;
    const handleLoad = () => {
      if (handled) return;
      handled = true;

      if (typeof window.PixelocityWASM !== 'function') {
        console.error('[WASM] PixelocityWASM factory function not found');
        state.lastLoadError = 'Factory PixelocityWASM missing';
        state.loadErrorCount++;
        resolve(false);
        return;
      }

      console.log('[WASM] Creating module from factory...');

      const wasmLocatePath = isUnderSubpath
        ? '/image_video_effects/wasm/'
        : '/wasm/';

      window.PixelocityWASM({
        locateFile: (path) => wasmLocatePath + path,
      }).then((mod) => {
        wasmRef.module = mod;

        let canvasId = wasmRef.canvas.id;
        if (!canvasId) {
          wasmRef.canvasIdCounter++;
          canvasId = 'pixelocity-wasm-canvas-' + wasmRef.canvasIdCounter;
          wasmRef.canvas.id = canvasId;
        }

        const selector = '#' + canvasId;
        console.log(`[WASM] Calling initWasmRenderer( ${state.canvasWidth} , ${state.canvasHeight} )`);

        let ok = 0;
        try {
          ok = wasmRef.module.ccall(
            'initWasmRenderer',
            'number',
            ['string', 'number', 'number'],
            [selector, state.canvasWidth, state.canvasHeight]
          );
        } catch (callErr) {
          console.error('[WASM] ccall initWasmRenderer threw:', callErr);
          const cppDiag = readCppInitDiagnostics();
          const detail = formatCppInitFailure(cppDiag);
          state.lastLoadError = `ccall exception: ${callErr.message || callErr} (${detail})`;
          state.loadErrorCount++;
          state.initEndTime = performance.now();
          resolve(false);
          return;
        }

        if (ok) {
          state.initialized = true;
          state.initEndTime = performance.now();
          const elapsed = state.initEndTime - state.initStartTime;
          console.log(`[WASM] ✅ Initialization complete in ${elapsed} ms`);

          if (state.pendingInputSource !== null) {
            const src = state.pendingInputSource;
            state.pendingInputSource = null;
            const sourceMap = { none: 0, image: 1, video: 2, webcam: 3, generative: 4, live: 5 };
            const sourceInt = typeof src === 'string'
              ? (sourceMap[src] ?? 0)
              : src;
            wasmRef.module.ccall('setInputSource', null, ['number'], [sourceInt]);
            state.inputSource = sourceInt;
          }

          resolve(true);
        } else {
          const cppDiag = readCppInitDiagnostics();
          const failMsg = formatCppInitFailure(cppDiag);
          console.error(`[WASM] ❌ initWasmRenderer failed: ${failMsg}`);
          if (cppDiag.adapterSummary) {
            console.error(`[WASM] GPU Adapter: ${cppDiag.adapterSummary}`);
          }
          state.lastLoadError = failMsg;
          state.loadErrorCount++;
          state.initEndTime = performance.now();
          resolve(false);
        }
      }).catch((err) => {
        console.error('[WASM] Module instantiation failed:', err);
        state.lastLoadError = err.message || String(err);
        state.loadErrorCount++;
        state.initEndTime = performance.now();
        resolve(false);
      });
    };

    const script = document.createElement('script');
    script.src = wasmJsPath;
    script.onload = handleLoad;
    script.onerror = () => {
      if (handled) return;
      handled = true;
      console.error(`[WASM] Failed to load script: ${wasmJsPath}`);
      state.lastLoadError = `Failed to load script: ${wasmJsPath}`;
      state.loadErrorCount++;
      state.initEndTime = performance.now();
      resolve(false);
    };

    document.head.appendChild(script);

    // In mock environments (e.g. Jest/JSDOM tests) where PixelocityWASM is pre-attached to window,
    // trigger handler via microtask to prevent jsdom async script queue delays.
    if (typeof window.PixelocityWASM === 'function') {
      queueMicrotask(handleLoad);
    }
  });
}

/**
 * Shutdown the WASM renderer and free GPU resources
 */
export function shutdownWasmRenderer() {
  if (!state.initialized || !wasmRef.module) {
    return;
  }

  try {
    wasmRef.module.ccall('shutdownWasmRenderer', null, [], []);
  } catch (err) {
    console.error('[WASM] Shutdown error:', err);
  }

  state.initialized = false;
  state.activeShader = null;
  wasmRef.module = null;
  wasmRef.canvas = null;
  console.log('[WASM] Shutdown complete');
}

/**
 * Check if the renderer is initialized
 * @returns {boolean} Initialized status
 */
export function isInitialized() {
  return state.initialized;
}
