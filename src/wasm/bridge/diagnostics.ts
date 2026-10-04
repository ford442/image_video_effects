import { INIT_STAGE_NAMES, readCanvasCopySrc, state, wasmRef } from './state.js';

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
    /** C++ canvas COPY_SRC probe; null while C++ init runs or when the artifact predates it. */
    canvasCopySrc: readCanvasCopySrc(),
    /** MAX_SHADER_SLOTS in the loaded artifact; null when it predates the export. */
    maxShaderSlots: state.maxShaderSlots,
  };
}

// ─── Measurement exports (#1314 D) ──────────────────────────────────────────
// Plain getters on the C++ side (no ASYNCIFY). Every reader tolerates an
// artifact built before the exports existed and malformed JSON.

/** Per-pass GPU timing in the shared PassTiming shape (src/renderer/passTimings.ts). */
export interface WasmPassTiming {
  /** `${slot}:${label}`; slot is '-' for the legacy single-shader pass. */
  key: string;
  label: string;
  kind: 'compute';
  slot?: number;
  shaderId?: string;
  entry?: string;
  scale: number;
  /** Smoothed (EMA) GPU milliseconds per frame. */
  gpuMs: number;
  iterations: number;
}

/** Uncaptured WebGPU errors and device-lost messages held by the C++ ring. */
export interface WasmErrorRing {
  /** Messages pushed since the module loaded (clearErrorRing does not reset it). */
  count: number;
  /** Most recent held message, or ''. */
  last: string;
  /** Up to 16 most recent held messages, oldest first. */
  recent: string[];
}

type CStringExport = '_getPassTimingsJson' | '_getLastError' | '_getErrorRingJson';

/** UTF8ToString of a const char* export; null when the module or export is missing. */
function readCStringExport(name: CStringExport): string | null {
  const mod = wasmRef.module;
  const fn = mod?.[name];
  if (!mod || typeof fn !== 'function' || typeof mod.UTF8ToString !== 'function') return null;
  try {
    return mod.UTF8ToString(fn());
  } catch {
    return null;
  }
}

function parseJson(json: string | null): unknown {
  if (!json) return null;
  try {
    return JSON.parse(json);
  } catch {
    return null;
  }
}

/** Parse getPassTimingsJson output; drops entries without a label or a finite, non-negative gpuMs. */
export function parsePassTimingsJson(json: string | null): WasmPassTiming[] {
  const raw = parseJson(json);
  if (!Array.isArray(raw)) return [];
  const passes: WasmPassTiming[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const r = item as Record<string, unknown>;
    const label = typeof r.label === 'string' ? r.label : '';
    const gpuMs = typeof r.gpuMs === 'number' ? r.gpuMs : Number.NaN;
    if (!label || !Number.isFinite(gpuMs) || gpuMs < 0) continue;
    const slot = typeof r.slot === 'number' && Number.isInteger(r.slot) && r.slot >= 0 ? r.slot : undefined;
    const shaderId = typeof r.shaderId === 'string' && r.shaderId ? r.shaderId : undefined;
    const iterations =
      typeof r.iterations === 'number' && Number.isInteger(r.iterations) && r.iterations > 0 ? r.iterations : 1;
    passes.push({
      key: `${slot ?? '-'}:${label}`,
      label,
      kind: 'compute',
      slot,
      shaderId,
      entry: label,
      scale: 1,
      gpuMs,
      iterations,
    });
  }
  return passes;
}

/** Parse getErrorRingJson ({count, messages}) plus getLastError into one summary. */
export function parseErrorRingJson(json: string | null, last: string | null = null): WasmErrorRing {
  const raw = parseJson(json) as { count?: unknown; messages?: unknown } | null;
  const recent = Array.isArray(raw?.messages)
    ? raw.messages.filter((m): m is string => typeof m === 'string')
    : [];
  const rawCount = typeof raw?.count === 'number' && Number.isFinite(raw.count) ? raw.count : 0;
  return {
    count: Math.max(rawCount, recent.length),
    last: last ?? recent[recent.length - 1] ?? '',
    recent,
  };
}

/** Smoothed per-pass C++ GPU timings; [] until timestamps resolve or on artifacts without the export. */
export function readPassTimings(): WasmPassTiming[] {
  return parsePassTimingsJson(readCStringExport('_getPassTimingsJson'));
}

/** C++ uncaptured-error ring; empty on artifacts without the export. Readable before init / after shutdown. */
export function readErrorRing(): WasmErrorRing {
  return parseErrorRingJson(readCStringExport('_getErrorRingJson'), readCStringExport('_getLastError'));
}

/** Drop the held error messages (the count keeps counting). False when the artifact lacks the export. */
export function clearErrorRing(): boolean {
  const fn = wasmRef.module?._clearErrorRing;
  if (typeof fn !== 'function') return false;
  try {
    fn();
    return true;
  } catch {
    return false;
  }
}
