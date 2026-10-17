// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

import * as cpp from "./_generated.js";
import { getSeamDiagnostics, hasExport } from "./call.js";
import { INIT_STAGE_NAMES, readCanvasCopySrc, state, wasmRef } from "./state.js";
function readCppInitDiagnostics() {
  if (!wasmRef.module || typeof wasmRef.module.ccall !== "function") {
    return { stage: 0, stageName: "None", message: "", adapterSummary: "" };
  }
  const mod = wasmRef.module;
  const stage = cpp.getLastInitErrorStage(mod);
  const message = cpp.getLastInitErrorMessage(mod);
  const adapterSummary = cpp.getAdapterSummary(mod);
  return {
    stage,
    stageName: INIT_STAGE_NAMES[stage] ?? `Stage${stage}`,
    message,
    adapterSummary
  };
}
function formatCppInitFailure(cpp2 = readCppInitDiagnostics()) {
  if (cpp2.message) {
    return `[${cpp2.stageName}] ${cpp2.message}`;
  }
  if (cpp2.stage > 0 && cpp2.stage < 8) {
    return `C++ initWasmRenderer failed at stage ${cpp2.stageName} (no detailed message)`;
  }
  return "C++ initWasmRenderer returned 0";
}
function getDiagnostics() {
  const cpp2 = readCppInitDiagnostics();
  const initMs = state.initEndTime ? state.initEndTime - state.initStartTime : null;
  return {
    initialized: state.initialized,
    hasModule: wasmRef.module !== null,
    hasCanvas: wasmRef.canvas !== null,
    moduleHasCCall: typeof wasmRef.module?.ccall === "function",
    canvasResolution: `${state.canvasWidth}x${state.canvasHeight}`,
    loadErrorCount: state.loadErrorCount,
    lastLoadError: state.lastLoadError,
    initTime: initMs === null ? "pending" : `${Math.round(initMs)}ms`,
    failedStage: cpp2.stage,
    failedStageName: state.initTimedOut ? "Timeout" : cpp2.stageName,
    lastInitError: state.initTimedOut ? state.lastLoadError ?? "" : cpp2.message,
    adapterInfo: cpp2.adapterSummary,
    /** C++ canvas COPY_SRC probe; null while C++ init runs or when the artifact predates it. */
    canvasCopySrc: readCanvasCopySrc(),
    /** MAX_SHADER_SLOTS in the loaded artifact; null when it predates the export. */
    maxShaderSlots: state.maxShaderSlots,
    /** Suspended async export, queued calls and sync calls dropped mid-suspend. */
    suspend: getSeamDiagnostics(wasmRef.module)
  };
}
function readCString(read) {
  const mod = wasmRef.module;
  if (!mod) return null;
  try {
    return read(mod);
  } catch {
    return null;
  }
}
function parseJson(json) {
  if (!json) return null;
  try {
    return JSON.parse(json);
  } catch {
    return null;
  }
}
function parsePassTimingsJson(json) {
  const raw = parseJson(json);
  if (!Array.isArray(raw)) return [];
  const passes = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const r = item;
    const label = typeof r.label === "string" ? r.label : "";
    const gpuMs = typeof r.gpuMs === "number" ? r.gpuMs : Number.NaN;
    if (!label || !Number.isFinite(gpuMs) || gpuMs < 0) continue;
    const slot = typeof r.slot === "number" && Number.isInteger(r.slot) && r.slot >= 0 ? r.slot : void 0;
    const shaderId = typeof r.shaderId === "string" && r.shaderId ? r.shaderId : void 0;
    const iterations = typeof r.iterations === "number" && Number.isInteger(r.iterations) && r.iterations > 0 ? r.iterations : 1;
    passes.push({
      key: `${slot ?? "-"}:${label}`,
      label,
      kind: "compute",
      slot,
      shaderId,
      entry: label,
      scale: 1,
      gpuMs,
      iterations
    });
  }
  return passes;
}
function parseErrorRingJson(json, last = null) {
  const raw = parseJson(json);
  const recent = Array.isArray(raw?.messages) ? raw.messages.filter((m) => typeof m === "string") : [];
  const rawCount = typeof raw?.count === "number" && Number.isFinite(raw.count) ? raw.count : 0;
  return {
    count: Math.max(rawCount, recent.length),
    last: last ?? recent[recent.length - 1] ?? "",
    recent
  };
}
function readPassTimings() {
  return parsePassTimingsJson(readCString(cpp.getPassTimingsJson));
}
function readErrorRing() {
  return parseErrorRingJson(readCString(cpp.getErrorRingJson), readCString(cpp.getLastError));
}
function clearErrorRing() {
  const mod = wasmRef.module;
  if (!mod) return false;
  try {
    return cpp.clearErrorRing(mod) !== null;
  } catch {
    return false;
  }
}
function awaitSubmittedWorkDone(timeoutMs = 6e4) {
  const mod = wasmRef.module;
  if (!mod || !hasExport(mod, "requestWorkDoneMark")) return null;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      mod.__pxWorkDone = void 0;
      reject(new Error("WASM onSubmittedWorkDone timed out"));
    }, timeoutMs);
    mod.__pxWorkDone = (ok) => {
      clearTimeout(timer);
      mod.__pxWorkDone = void 0;
      resolve(ok !== 0);
    };
    if (cpp.requestWorkDoneMark(mod) !== 1) {
      clearTimeout(timer);
      mod.__pxWorkDone = void 0;
      resolve(false);
    }
  });
}
export {
  awaitSubmittedWorkDone,
  clearErrorRing,
  formatCppInitFailure,
  getDiagnostics,
  parseErrorRingJson,
  parsePassTimingsJson,
  readCppInitDiagnostics,
  readErrorRing,
  readPassTimings
};
