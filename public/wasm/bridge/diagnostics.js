// src/wasm/bridge/diagnostics.js
// Init diagnostics and bridge health reporting.

import { INIT_STAGE_NAMES, state, wasmRef } from './state.js';

/**
 * Read structured init-failure diagnostics exported from C++ (main.cpp).
 * Safe to call before or after init — returns empty defaults when unavailable.
 */
export function readCppInitDiagnostics() {
  if (!wasmRef.module || typeof wasmRef.module.ccall !== 'function') {
    return { stage: 0, stageName: 'None', message: '', adapterSummary: '' };
  }

  const stage = wasmRef.module.ccall('getLastInitErrorStage', 'number', [], []) ?? 0;
  const message = wasmRef.module.ccall('getLastInitErrorMessage', 'string', [], []) ?? '';
  const adapterSummary = wasmRef.module.ccall('getAdapterSummary', 'string', [], []) ?? '';

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
export function formatCppInitFailure(cpp = readCppInitDiagnostics()) {
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
    activeShader: state.activeShader,
    canvasWidth: state.canvasWidth,
    canvasHeight: state.canvasHeight,
    hasWasmModule: wasmRef.module !== null,
    hasCanvas: wasmRef.canvas !== null,
    loadErrorCount: state.loadErrorCount,
    lastLoadError: state.lastLoadError,
    initDurationMs: state.initEndTime ? state.initEndTime - state.initStartTime : null,
    lastInitStage: cpp.stage,
    lastInitStageName: cpp.stageName,
    lastInitErrorMessage: cpp.message || null,
    adapterSummary: cpp.adapterSummary || null,
  };
}
