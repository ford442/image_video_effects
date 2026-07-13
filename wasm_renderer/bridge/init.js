// WASM module load and renderer lifecycle.

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

  canvas = canvasElement;
  state.canvasWidth = canvas.width || 2048;
  state.canvasHeight = canvas.height || 2048;
  state.initStartTime = performance.now();

  return new Promise((resolve) => {
    const pathname = window.location.pathname;
    const basePath = pathname.endsWith('/')
      ? pathname.slice(0, -1)
      : pathname.replace(/\/[^/]*$/, '');
    const wasmJsPath = basePath + '/wasm/pixelocity_wasm.js';
    const wasmBinaryPath = basePath + '/wasm/pixelocity_wasm.wasm';

    console.log('[WASM] Loading from:', wasmJsPath);
    console.log('[WASM] Canvas size:', `${state.canvasWidth}x${state.canvasHeight}`);

    if (window.PixelocityWASM) {
      initializeModule(window.PixelocityWASM, wasmBinaryPath, resolve);
      return;
    }

    const script = document.createElement('script');
    script.src = wasmJsPath;
    script.async = true;

    script.onload = () => {
      if (!window.PixelocityWASM) {
        const error = 'PixelocityWASM not found on window after script load (stub module?)';
        console.error('[WASM]', error);
        state.lastLoadError = error;
        state.loadErrorCount++;
        resolve(false);
        return;
      }
      initializeModule(window.PixelocityWASM, wasmBinaryPath, resolve);
    };

    script.onerror = (err) => {
      const error = `Failed to load WASM script: ${err}`;
      console.error('[WASM]', error);
      state.lastLoadError = error;
      state.loadErrorCount++;
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
    console.log('[WASM] Creating module from factory...');
    wasmModule = await factory({
      locateFile: (path) => {
        if (path.endsWith('.wasm')) return wasmBinaryPath;
        return path;
      },
      onAbort: (msg) => {
        console.error('[WASM] Module aborted:', msg);
        state.lastLoadError = `Module abort: ${msg}`;
        state.loadErrorCount++;
      }
    });

    if (!wasmModule) {
      const error = 'Module factory returned null';
      console.error('[WASM]', error);
      state.lastLoadError = error;
      state.loadErrorCount++;
      resolve(false);
      return;
    }

    if (typeof wasmModule.ccall !== 'function') {
      const error = 'Module loaded but ccall unavailable — stub build detected (missing Emscripten binaries)';
      console.warn('[WASM]', error);
      state.lastLoadError = error;
      state.loadErrorCount++;
      resolve(false);
      return;
    }

    console.log('[WASM] Calling initWasmRenderer(', state.canvasWidth, ',', state.canvasHeight, ')');
    // Use { async: true } so ccall returns a Promise that resolves after the
    // Asyncify-suspended C++ function completes.  Without this, ccall returns 0
    // immediately when WASM suspends inside wgpuInstanceWaitAny (waiting for the
    // browser WebGPU adapter/device Promise), causing a false "init failed" error.

    // Assign a stable CSS ID to the canvas so C++ can create the WebGPU surface.
    if (!canvas.id) {
      canvas.id = 'pixelocity-wasm-' + (++_canvasIdCounter);
    }
    const canvasSelector = '#' + canvas.id;

    const result = await wasmModule.ccall(
      'initWasmRenderer',
      'number',
      ['number', 'number', 'string'],
      [state.canvasWidth, state.canvasHeight, canvasSelector],
      { async: true }
    );

    state.initEndTime = performance.now();

    if (!result) {
      const cpp = readCppInitDiagnostics();
      const error = formatCppInitFailure(cpp);
      console.error('[WASM]', error);
      if (cpp.adapterSummary) {
        console.error('[WASM] Adapter summary:', cpp.adapterSummary);
      }
      state.lastLoadError = error;
      state.loadErrorCount++;
      resolve(false);
      return;
    }

    state.initialized = true;
    if (state.pendingInputSource != null) {
      setInputSource(state.pendingInputSource);
      state.pendingInputSource = null;
    } else if (state.inputSource !== 1) {
      setInputSource(state.inputSource);
    }
    console.log('[WASM] ✅ Initialization complete in', state.initEndTime - state.initStartTime, 'ms');
    resolve(true);
  } catch (err) {
    const error = `Module initialization exception: ${err instanceof Error ? err.message : String(err)}`;
    console.error('[WASM]', error);
    state.lastLoadError = error;
    state.loadErrorCount++;
    state.initEndTime = performance.now();
    resolve(false);
  }
}

/**
 * Shutdown the WASM renderer
 */
export function shutdownWasmRenderer() {
  if (!state.initialized || !wasmModule) return;

  try {
    wasmModule.ccall('shutdownWasmRenderer', null, [], []);
    console.log('[WASM] Shutdown complete');
  } catch (err) {
    console.error('[WASM] Shutdown error:', err);
  }

  wasmModule = null;
  state.initialized = false;
}
