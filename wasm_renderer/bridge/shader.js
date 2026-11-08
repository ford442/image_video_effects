// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

import * as cpp from "./_generated.js";
import { isBusy, runWhenIdle } from "./call.js";
import { state, utf8ByteLength, wasmRef } from "./state.js";
import { analyzeShaderBindings, packUsageBits, resolveWorkgroupSize } from "./wgslAnalysis.js";
import { rewriteWgslStorageFormats } from "./wgslFormat.js";
import { expandWgslIncludes, hasWgslInclude } from "./wgslInclude.js";
import { withBundledLibraries } from "./wgslLibraries.js";
function writeUtf8(id) {
  const module = wasmRef.module;
  if (!module) return null;
  const len = utf8ByteLength(module, id);
  const ptr = module._malloc(len);
  module.stringToUTF8(id, ptr, len);
  return { ptr, free: () => module._free(ptr) };
}
async function fetchAndExpand(id, url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`HTTP error ${response.status}: ${response.statusText}`);
  }
  const wgslCode = await response.text();
  if (!hasWgslInclude(wgslCode)) return wgslCode;
  const baseUrl = url.slice(0, url.lastIndexOf("/") + 1);
  return expandWgslIncludes(
    wgslCode,
    withBundledLibraries(async (name) => {
      const res = await fetch(`${baseUrl}${name}`);
      return res.ok ? res.text() : null;
    }),
    `${id}.wgsl`
  );
}
function declaresBindGroup1(wgslCode) {
  const stripped = wgslCode.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
  return /@group\(\s*1\s*\)/.test(stripped);
}
function refuseBindGroup1(id, op) {
  const message = `Shader ${id} declares @group(1) (sim ring) \u2014 WASM backend is group-0 only (feature freeze); skipped. Use the WebGPU (TS) renderer for sim-ring shaders.`;
  console.warn(`[WASM] ${op}: ${message}`);
  state.lastLoadError = message;
  state.loadErrorCount++;
  return false;
}
function shaderAnalysisArgs(wgslCode) {
  const wg = resolveWorkgroupSize(wgslCode);
  if (!wg.parsed) console.warn(`[WASM] Could not parse workgroup_size, defaulting to ${wg.x}x${wg.y}`);
  return { workgroupX: wg.x, workgroupY: wg.y, usageBits: packUsageBits(analyzeShaderBindings(wgslCode)) };
}
async function loadShader(id, wgslCode) {
  if (!state.initialized || !wasmRef.module) {
    console.error("[WASM] Renderer not initialized");
    return false;
  }
  if (hasWgslInclude(wgslCode)) {
    const message = `Shader ${id} still contains an unexpanded #include \u2014 expand before loadShader()`;
    console.error(`[WASM] ${message}`);
    state.lastLoadError = message;
    state.loadErrorCount++;
    return false;
  }
  if (declaresBindGroup1(wgslCode)) return refuseBindGroup1(id, "loadShader");
  const rewritten = rewriteWgslStorageFormats(wgslCode, state.colorFormat);
  const a = shaderAnalysisArgs(rewritten);
  const idBuf = writeUtf8(id);
  const codeBuf = writeUtf8(rewritten);
  if (!idBuf || !codeBuf) return false;
  let result = 0;
  try {
    result = await cpp.loadShader(wasmRef.module, idBuf.ptr, codeBuf.ptr, a.workgroupX, a.workgroupY, a.usageBits);
  } finally {
    idBuf.free();
    codeBuf.free();
  }
  if (result) {
    state.activeShader = id;
    console.log(`[WASM] Loaded shader: ${id}`);
    return true;
  }
  console.error(`[WASM] Failed to load shader: ${id}`);
  state.lastLoadError = `Failed to compile/load shader: ${id}`;
  state.loadErrorCount++;
  return false;
}
async function reloadShader(id, wgslCode) {
  if (!state.initialized || !wasmRef.module) {
    console.error("[WASM] Renderer not initialized");
    return false;
  }
  if (hasWgslInclude(wgslCode)) {
    const message = `Shader ${id} still contains an unexpanded #include \u2014 expand before reloadShader()`;
    console.error(`[WASM] ${message}`);
    state.lastLoadError = message;
    state.loadErrorCount++;
    return false;
  }
  if (declaresBindGroup1(wgslCode)) return refuseBindGroup1(id, "reloadShader");
  const rewritten = rewriteWgslStorageFormats(wgslCode, state.colorFormat);
  const a = shaderAnalysisArgs(rewritten);
  const idBuf = writeUtf8(id);
  const codeBuf = writeUtf8(rewritten);
  if (!idBuf || !codeBuf) return false;
  let result = 0;
  try {
    result = await cpp.reloadShader(wasmRef.module, idBuf.ptr, codeBuf.ptr, a.workgroupX, a.workgroupY, a.usageBits);
  } finally {
    idBuf.free();
    codeBuf.free();
  }
  if (result) {
    console.log(`[WASM] Hot-reloaded shader: ${id}`);
    return true;
  }
  console.error(`[WASM] Hot-reload failed for: ${id}`);
  state.lastLoadError = `Hot-reload failed: ${id}`;
  state.loadErrorCount++;
  return false;
}
async function loadShaderFromURL(id, url) {
  try {
    return await loadShader(id, await fetchAndExpand(id, url));
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[WASM] Failed to fetch shader from ${url}:`, err);
    state.lastLoadError = `Fetch failed (${url}): ${message}`;
    state.loadErrorCount++;
    return false;
  }
}
async function reloadShaderFromURL(id, url) {
  try {
    return await reloadShader(id, await fetchAndExpand(id, url));
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[WASM] Failed to fetch shader for reload from ${url}:`, err);
    state.lastLoadError = `Reload fetch failed (${url}): ${message}`;
    state.loadErrorCount++;
    return false;
  }
}
function setActiveShader(id) {
  const module = wasmRef.module;
  if (!state.initialized || !module) return;
  const apply = () => {
    if (wasmRef.module !== module) return;
    cpp.setActiveShader(module, id);
    if (!id || cpp.getSlotShaderId(module, 0) === id) state.activeShader = id || null;
  };
  if (isBusy(module)) void runWhenIdle(module, apply);
  else apply();
}
function setSlotShader(slotIndex, shaderId) {
  const module = wasmRef.module;
  if (!state.initialized || !module) return false;
  const apply = () => {
    if (wasmRef.module !== module) return false;
    cpp.setSlotShader(module, slotIndex, shaderId);
    const accepted = !shaderId || cpp.getSlotShaderId(module, slotIndex) === shaderId;
    if (accepted) {
      state.droppedSlots.delete(slotIndex);
    } else {
      state.droppedSlots.add(slotIndex);
      console.warn(
        `[WASM] setSlotShader(${slotIndex}, "${shaderId}") dropped by the module (no valid pipeline, or the artifact has fewer slots than slot_limits.json)`
      );
    }
    return accepted;
  };
  if (!isBusy(module)) return apply();
  void runWhenIdle(module, apply);
  return true;
}
function getDroppedSlots() {
  return state.droppedSlots;
}
function setSlotMode(slotIndex, mode) {
  if (!state.initialized || !wasmRef.module) return;
  cpp.setSlotMode(wasmRef.module, slotIndex, mode === "parallel" || mode === 1 ? 1 : 0);
}
function getSlotShaderId(slotIndex) {
  if (!state.initialized || !wasmRef.module) return "";
  return cpp.getSlotShaderId(wasmRef.module, slotIndex);
}
function getSlotEnabled(slotIndex) {
  if (!state.initialized || !wasmRef.module) return false;
  return cpp.getSlotEnabled(wasmRef.module, slotIndex) !== 0;
}
function getSlotMode(slotIndex) {
  if (!state.initialized || !wasmRef.module) return 0;
  return cpp.getSlotMode(wasmRef.module, slotIndex);
}
function getSlotState(slotIndex) {
  const shaderId = getSlotShaderId(slotIndex);
  const modeInt = getSlotMode(slotIndex);
  return {
    shaderId: shaderId.length > 0 ? shaderId : null,
    enabled: getSlotEnabled(slotIndex),
    mode: modeInt === 1 ? "parallel" : "chained"
  };
}
export {
  getDroppedSlots,
  getSlotEnabled,
  getSlotMode,
  getSlotShaderId,
  getSlotState,
  loadShader,
  loadShaderFromURL,
  reloadShader,
  reloadShaderFromURL,
  setActiveShader,
  setSlotMode,
  setSlotShader,
  shaderAnalysisArgs
};
