// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

import { INIT_STAGE_NAMES, readCanvasCopySrc, state, wasmRef } from "./state.js";
function readCppInitDiagnostics() {
  if (!wasmRef.module || typeof wasmRef.module.ccall !== "function") {
    return { stage: 0, stageName: "None", message: "", adapterSummary: "" };
  }
  const stage = Number(wasmRef.module.ccall("getLastInitErrorStage", "number", [], []) ?? 0);
  const message = String(wasmRef.module.ccall("getLastInitErrorMessage", "string", [], []) ?? "");
  const adapterSummary = String(wasmRef.module.ccall("getAdapterSummary", "string", [], []) ?? "");
  return {
    stage,
    stageName: INIT_STAGE_NAMES[stage] ?? `Stage${stage}`,
    message,
    adapterSummary
  };
}
function formatCppInitFailure(cpp = readCppInitDiagnostics()) {
  if (cpp.message) {
    return `[${cpp.stageName}] ${cpp.message}`;
  }
  if (cpp.stage > 0 && cpp.stage < 8) {
    return `C++ initWasmRenderer failed at stage ${cpp.stageName} (no detailed message)`;
  }
  return "C++ initWasmRenderer returned 0";
}
function getDiagnostics() {
  const cpp = readCppInitDiagnostics();
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
    failedStage: cpp.stage,
    failedStageName: cpp.stageName,
    lastInitError: cpp.message,
    adapterInfo: cpp.adapterSummary,
    /** C++ canvas COPY_SRC probe; null while C++ init runs or when the artifact predates it. */
    canvasCopySrc: readCanvasCopySrc(),
    /** MAX_SHADER_SLOTS in the loaded artifact; null when it predates the export. */
    maxShaderSlots: state.maxShaderSlots
  };
}
function readCStringExport(name) {
  const mod = wasmRef.module;
  const fn = mod?.[name];
  if (!mod || typeof fn !== "function" || typeof mod.UTF8ToString !== "function") return null;
  try {
    return mod.UTF8ToString(fn());
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
  return parsePassTimingsJson(readCStringExport("_getPassTimingsJson"));
}
function readErrorRing() {
  return parseErrorRingJson(readCStringExport("_getErrorRingJson"), readCStringExport("_getLastError"));
}
function clearErrorRing() {
  const fn = wasmRef.module?._clearErrorRing;
  if (typeof fn !== "function") return false;
  try {
    fn();
    return true;
  } catch {
    return false;
  }
}
export {
  clearErrorRing,
  formatCppInitFailure,
  getDiagnostics,
  parseErrorRingJson,
  parsePassTimingsJson,
  readCppInitDiagnostics,
  readErrorRing,
  readPassTimings
};
