// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

import * as cpp from "./_generated.js";
import { isBusy, runWhenIdle } from "./call.js";
import { state, utf8ByteLength, wasmRef } from "./state.js";
import { analyzeShaderBindings, parseWorkgroupSize, shaderUsageBits } from "./wgslAnalysis.js";
import { rewriteWgslStorageFormats } from "./wgslFormat.js";
import { expandWgslIncludes, hasWgslInclude } from "./wgslInclude.js";
import { withBundledLibraries } from "./wgslLibraries.js";
function writeUtf8(module, text) {
  const len = utf8ByteLength(module, text);
  const ptr = module._malloc(len);
  module.stringToUTF8(text, ptr, len);
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
function prepareShader(module, wgslCode) {
  const format = cpp.getColorFormat(module) === 1 ? 1 : 0;
  const code = rewriteWgslStorageFormats(wgslCode, format);
  const workgroup = parseWorkgroupSize(code);
  return { format, code, workgroup, usage: shaderUsageBits(analyzeShaderBindings(code)) };
}
function refuseBeforeCompile(id, wgslCode, op) {
  if (hasWgslInclude(wgslCode)) {
    const message = `Shader ${id} still contains an unexpanded #include \u2014 expand before ${op}()`;
    console.error(`[WASM] ${message}`);
    state.lastLoadError = message;
    state.loadErrorCount++;
    return true;
  }
  if (declaresBindGroup1(wgslCode)) {
    refuseBindGroup1(id, op);
    return true;
  }
  return false;
}
async function compileShader(op, id, wgslCode) {
  const module = wasmRef.module;
  if (!state.initialized || !module) {
    console.error("[WASM] Renderer not initialized");
    return "refused";
  }
  if (refuseBeforeCompile(id, wgslCode, op)) return "refused";
  for (let attempt = 0; ; attempt++) {
    const { format, code, workgroup, usage } = prepareShader(module, wgslCode);
    const idBuf = writeUtf8(module, id);
    const codeBuf = writeUtf8(module, code);
    let ok = false;
    try {
      ok = await cpp[op](module, idBuf.ptr, codeBuf.ptr, workgroup.x, workgroup.y, usage) === 1;
    } catch (err) {
      console.error(`[WASM] ${op}(${id}) threw:`, err);
      return "failed";
    } finally {
      idBuf.free();
      codeBuf.free();
    }
    if (ok) return "ok";
    if (attempt > 0 || wasmRef.module !== module || cpp.getColorFormat(module) === format) return "failed";
  }
}
async function loadShader(id, wgslCode) {
  const outcome = await compileShader("loadShader", id, wgslCode);
  if (outcome === "ok") {
    state.activeShader = id;
    console.log(`[WASM] Loaded shader: ${id}`);
    return true;
  }
  if (outcome === "failed") {
    console.error(`[WASM] Failed to load shader: ${id}`);
    state.lastLoadError = `Failed to compile/load shader: ${id}`;
    state.loadErrorCount++;
  }
  return false;
}
async function reloadShader(id, wgslCode) {
  const outcome = await compileShader("reloadShader", id, wgslCode);
  if (outcome === "ok") {
    console.log(`[WASM] Hot-reloaded shader: ${id}`);
    return true;
  }
  if (outcome === "failed") {
    console.error(`[WASM] Hot-reload failed for: ${id} (previous pipeline kept)`);
    state.lastLoadError = `Hot-reload failed: ${id}`;
    state.loadErrorCount++;
  }
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
  setSlotShader
};
