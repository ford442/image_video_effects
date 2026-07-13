// Init diagnostics and bridge health reporting.

/**
 * Read structured init-failure diagnostics exported from C++ (main.cpp).
 * Safe to call before or after init — returns empty defaults when unavailable.
 */
function readCppInitDiagnostics() {
  if (!wasmModule || typeof wasmModule.ccall !== 'function') {
    return { stage: 0, stageName: 'None', message: '', adapterSummary: '' };
  }

  const stage = wasmModule.ccall('getLastInitErrorStage', 'number', [], []) ?? 0;
  const message = wasmModule.ccall('getLastInitErrorMessage', 'string', [], []) ?? '';
  const adapterSummary = wasmModule.ccall('getAdapterSummary', 'string', [], []) ?? '';

  return {
    stage,
    stageName: INIT_STAGE_NAMES[stage] ?? `Stage${stage}`,
    message,
    adapterSummary,
  };
}

/**
 * Build a human-readable init failure string from C++ stage + message.
 */
function formatCppInitFailure(cpp = readCppInitDiagnostics()) {
  if (cpp.message) {
    return `[${cpp.stageName}] ${cpp.message}`;
  }
  if (cpp.stage > 0 && cpp.stage < 8) {
    return `C++ initWasmRenderer failed at stage ${cpp.stageName} (no detailed message)`;
  }
  return 'C++ initWasmRenderer returned 0';
}

/**
 * Get diagnostic information about WASM bridge status
 * @returns {Object} Diagnostic data
 */
export function getDiagnostics() {
  const cpp = readCppInitDiagnostics();
  return {
    initialized: state.initialized,
    hasModule: wasmModule !== null,
    hasCanvas: canvas !== null,
    moduleHasCCall: wasmModule ? typeof wasmModule.ccall === 'function' : false,
    canvasResolution: state.canvasWidth > 0 ? `${state.canvasWidth}x${state.canvasHeight}` : 'unset',
    loadErrorCount: state.loadErrorCount,
    lastLoadError: state.lastLoadError,
    initTime: state.initEndTime > 0 ? `${state.initEndTime - state.initStartTime}ms` : 'pending',
    loadPath: canvas ? `${window.location.origin}/wasm/` : 'not available',
    failedStage: cpp.stage,
    failedStageName: cpp.stageName,
    lastInitError: cpp.message,
    adapterInfo: cpp.adapterSummary,
  };
}

/**
 * Human-readable adapter/device/limits summary from C++ CreateDevice().
 * Empty string if the renderer has not attempted initialization yet.
 * @returns {string}
 */
export function getAdapterSummary() {
  if (!wasmModule) return '';
  return wasmModule.ccall('getAdapterSummary', 'string', [], []);
}

/**
 * Which Initialize() stage failed (see InitStage in renderer.h).
 * Returns 8 (Ready) on success, 0 before any init attempt.
 * @returns {number}
 */
export function getLastInitErrorStage() {
  if (!wasmModule) return 0;
  return wasmModule.ccall('getLastInitErrorStage', 'number', [], []);
}

/**
 * Human-readable reason for the last Initialize() failure.
 * @returns {string}
 */
export function getLastInitErrorMessage() {
  if (!wasmModule) return '';
  return wasmModule.ccall('getLastInitErrorMessage', 'string', [], []);
}

/**
 * Check if renderer is initialized.
 * @returns {boolean}
 */
export function isInitialized() {
  return state.initialized;
}
