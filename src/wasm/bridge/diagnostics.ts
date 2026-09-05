import { INIT_STAGE_NAMES, state, wasmRef } from './state.js';

export interface CppInitDiagnostics {
  stage: number;
  stageName: string;
  message: string;
  adapterSummary: string;
}

export function readCppInitDiagnostics(): CppInitDiagnostics {
  if (!wasmRef.module || typeof wasmRef.module.ccall !== 'function') {
    return { stage: 0, stageName: 'None', message: '', adapterSummary: '' };
  }

  const stage = Number(wasmRef.module.ccall('getLastInitErrorStage', 'number', [], []) ?? 0);
  const message = String(wasmRef.module.ccall('getLastInitErrorMessage', 'string', [], []) ?? '');
  const adapterSummary = String(wasmRef.module.ccall('getAdapterSummary', 'string', [], []) ?? '');

  return {
    stage,
    stageName: INIT_STAGE_NAMES[stage] ?? `Stage${stage}`,
    message,
    adapterSummary,
  };
}

export function formatCppInitFailure(cpp: CppInitDiagnostics = readCppInitDiagnostics()): string {
  if (cpp.message) {
    return `[${cpp.stageName}] ${cpp.message}`;
  }
  if (cpp.stage > 0 && cpp.stage < 8) {
    return `C++ initWasmRenderer failed at stage ${cpp.stageName} (no detailed message)`;
  }
  return 'C++ initWasmRenderer returned 0';
}

export function getDiagnostics() {
  const cpp = readCppInitDiagnostics();
  const initMs = state.initEndTime ? state.initEndTime - state.initStartTime : null;
  return {
    initialized: state.initialized,
    hasModule: wasmRef.module !== null,
    hasCanvas: wasmRef.canvas !== null,
    moduleHasCCall: typeof wasmRef.module?.ccall === 'function',
    canvasResolution: `${state.canvasWidth}x${state.canvasHeight}`,
    loadErrorCount: state.loadErrorCount,
    lastLoadError: state.lastLoadError,
    initTime: initMs === null ? 'pending' : `${Math.round(initMs)}ms`,
    failedStage: cpp.stage,
    failedStageName: cpp.stageName,
    lastInitError: cpp.message,
    adapterInfo: cpp.adapterSummary,
  };
}
