// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

import * as cpp from "./_generated.js";
import { isBusy, isSuspended, runWhenIdle } from "./call.js";
import { state, wasmRef } from "./state.js";
const SOURCE_MAP = {
  none: 0,
  image: 1,
  video: 2,
  webcam: 3,
  generative: 4,
  live: 5
};
function setSlotParams(slotIndex, p1, p2, p3, p4) {
  if (!state.initialized || !wasmRef.module) return;
  if (slotIndex >= 0) {
    state.slotParams[slotIndex] = [p1, p2, p3, p4];
  }
  if (slotIndex === 0) {
    state.zoomParams = [p1, p2, p3, p4];
  }
  cpp.setSlotParams(wasmRef.module, slotIndex, p1, p2, p3, p4);
}
function updateSlotParams(slotIndex, params) {
  if (!params || typeof params !== "object") return;
  const current = state.slotParams[slotIndex] ?? [0.5, 0.5, 0.5, 0.5];
  const p1 = params.p1 ?? params.zoomParam1 ?? current[0];
  const p2 = params.p2 ?? params.zoomParam2 ?? current[1];
  const p3 = params.p3 ?? params.zoomParam3 ?? current[2];
  const p4 = params.p4 ?? params.zoomParam4 ?? current[3];
  setSlotParams(slotIndex, p1, p2, p3, p4);
}
function applyUniformState(time, mouseX, mouseY, mouseDown, zoomP1, zoomP2, zoomP3, zoomP4) {
  const mod = wasmRef.module;
  if (!state.initialized || !mod) {
    return false;
  }
  state.time = time;
  state.mouseX = mouseX;
  state.mouseY = mouseY;
  state.mouseDown = mouseDown;
  state.zoomParams = [zoomP1, zoomP2, zoomP3, zoomP4];
  cpp.setTime(mod, time);
  cpp.updateMousePos(mod, mouseX, mouseY);
  cpp.setMouseDown(mod, mouseDown ? 1 : 0);
  cpp.setZoomParams(mod, zoomP1, zoomP2, zoomP3, zoomP4);
  const rendered = !isSuspended(mod);
  cpp.updateUniforms(mod);
  return rendered;
}
function updateUniforms(timeOrUniforms, mouseX = 0.5, mouseY = 0.5, mouseDown = false, zoomP1 = 0.5, zoomP2 = 0.5, zoomP3 = 0.5, zoomP4 = 0.5) {
  if (typeof timeOrUniforms === "object" && timeOrUniforms !== null) {
    const u = timeOrUniforms;
    const zp = u.zoom_params ?? state.zoomParams;
    return applyUniformState(
      u.time ?? state.time,
      u.mouseX ?? state.mouseX,
      u.mouseY ?? state.mouseY,
      u.mouseDown ?? state.mouseDown,
      zp[0],
      zp[1],
      zp[2],
      zp[3]
    );
  }
  return applyUniformState(timeOrUniforms, mouseX, mouseY, mouseDown, zoomP1, zoomP2, zoomP3, zoomP4);
}
function updateMousePos(x, y, down) {
  if (!state.initialized || !wasmRef.module) return;
  state.mouseX = x;
  state.mouseY = y;
  cpp.updateMousePos(wasmRef.module, x, y);
  if (down !== void 0) {
    state.mouseDown = down;
    cpp.setMouseDown(wasmRef.module, down ? 1 : 0);
  }
}
function updateAudioData(bassOrData, mid, treble) {
  if (!state.initialized || !wasmRef.module) return;
  if (typeof bassOrData === "number") {
    cpp.updateAudioData(wasmRef.module, bassOrData, mid ?? 0, treble ?? 0);
    return;
  }
  const bass = Number(bassOrData[0] ?? 0);
  const midVal = Number(bassOrData[1] ?? 0);
  const trebleVal = Number(bassOrData[2] ?? 0);
  cpp.updateAudioData(wasmRef.module, bass, midVal, trebleVal);
}
function updateAudioFrequencyBins(binsOrBass, mid, treble, energy) {
  if (!state.initialized || !wasmRef.module) return;
  if (typeof binsOrBass === "number") {
    updateAudioFrequencyBins(new Float32Array([binsOrBass, mid ?? 0, treble ?? 0, energy ?? 0]));
    return;
  }
  const count = binsOrBass.length;
  const bytes = count * 4;
  const ptr = wasmRef.module._malloc(bytes);
  wasmRef.module.HEAPF32.set(binsOrBass, ptr / 4);
  cpp.updateAudioFrequencyBins(wasmRef.module, ptr, count);
  wasmRef.module._free(ptr);
}
function updateDepthMap(depthData, width = 256, height = 256) {
  const module = wasmRef.module;
  if (!state.initialized || !module) return;
  const view = depthData instanceof Float32Array ? depthData : new Float32Array(depthData.buffer, depthData.byteOffset, depthData.byteLength / 4);
  const busy = isBusy(module);
  const floats = busy ? view.slice() : view;
  const upload = () => {
    if (!state.initialized || wasmRef.module !== module) return;
    const ptr = module._malloc(floats.byteLength);
    module.HEAPF32.set(floats, ptr / 4);
    try {
      cpp.updateDepthMap(module, ptr, width, height);
    } finally {
      module._free(ptr);
    }
  };
  if (!busy) upload();
  else runWhenIdle(module, upload).catch((err) => console.error("[WASM] deferred depth upload failed:", err));
}
function setInputSource(source) {
  const sourceInt = typeof source === "string" ? SOURCE_MAP[source.toLowerCase()] ?? 0 : typeof source === "number" ? source : 0;
  if (!state.initialized || !wasmRef.module) {
    state.pendingInputSource = source;
    state.inputSource = sourceInt;
    return;
  }
  state.inputSource = sourceInt;
  cpp.setInputSource(wasmRef.module, sourceInt);
}
function addRipple(x, y, _amplitude = 1, _wavelength = 0.05) {
  if (!state.initialized || !wasmRef.module) return;
  cpp.addRipple(wasmRef.module, x, y);
}
function clearRipples() {
  if (!state.initialized || !wasmRef.module) return;
  cpp.clearRipples(wasmRef.module);
}
function getFPS() {
  if (!state.initialized || !wasmRef.module) return 0;
  return cpp.getFPS(wasmRef.module);
}
function getSupportsDeepWorkgroup() {
  if (!state.initialized || !wasmRef.module) return true;
  return cpp.getSupportsDeepWorkgroup(wasmRef.module) !== 0;
}
function getColorFormat() {
  if (state.initialized && wasmRef.module) {
    state.colorFormat = cpp.getColorFormat(wasmRef.module) === 1 ? 1 : 0;
  }
  return state.colorFormat;
}
async function setColorFormat(format) {
  state.colorFormat = format === 1 ? 1 : 0;
  if (state.initialized && wasmRef.module) {
    await cpp.setColorFormat(wasmRef.module, state.colorFormat);
  }
}
function unavailableGPUTimings() {
  return {
    parallelTime: 0,
    chainedTime: 0,
    totalTime: 0,
    available: false,
    timingSource: "unavailable"
  };
}
function getGPUTimings() {
  if (!state.initialized || !wasmRef.module) return unavailableGPUTimings();
  const m = wasmRef.module;
  if (typeof m._malloc !== "function" || typeof m.getValue !== "function" || typeof m.ccall !== "function") {
    return unavailableGPUTimings();
  }
  const ptr = m._malloc(16);
  if (!ptr) return unavailableGPUTimings();
  try {
    cpp.getGPUTimings(m, ptr, ptr + 4, ptr + 8, ptr + 12);
    const parallelTime = m.getValue(ptr, "float");
    const chainedTime = m.getValue(ptr + 4, "float");
    const totalTime = m.getValue(ptr + 8, "float");
    const available = m.getValue(ptr + 12, "i32") !== 0;
    return {
      parallelTime,
      chainedTime,
      totalTime,
      available,
      timingSource: available ? "gpu-timestamp" : "wall-clock"
    };
  } catch {
    return unavailableGPUTimings();
  } finally {
    if (typeof m._free === "function") m._free(ptr);
  }
}
function getAdapterSummary() {
  if (!wasmRef.module || typeof wasmRef.module.ccall !== "function") return "";
  return cpp.getAdapterSummary(wasmRef.module);
}
function getLastInitErrorStage() {
  if (!wasmRef.module || typeof wasmRef.module.ccall !== "function") return 0;
  return cpp.getLastInitErrorStage(wasmRef.module);
}
function getLastInitErrorMessage() {
  if (!wasmRef.module || typeof wasmRef.module.ccall !== "function") return "";
  return cpp.getLastInitErrorMessage(wasmRef.module);
}
export {
  addRipple,
  clearRipples,
  getAdapterSummary,
  getColorFormat,
  getFPS,
  getGPUTimings,
  getLastInitErrorMessage,
  getLastInitErrorStage,
  getSupportsDeepWorkgroup,
  setColorFormat,
  setInputSource,
  setSlotParams,
  updateAudioData,
  updateAudioFrequencyBins,
  updateDepthMap,
  updateMousePos,
  updateSlotParams,
  updateUniforms
};
