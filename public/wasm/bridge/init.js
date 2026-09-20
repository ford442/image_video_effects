// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

import { callSuspending } from "./call.js";
import { formatCppInitFailure, readCppInitDiagnostics } from "./diagnostics.js";
import { state, wasmRef } from "./state.js";
const SOURCE_MAP = {
  none: 0,
  image: 1,
  video: 2,
  webcam: 3,
  generative: 4,
  live: 5
};
async function initWasmRenderer(canvasElement) {
  if (state.initialized) {
    console.warn("[WASM] Renderer already initialized");
    return true;
  }
  wasmRef.canvas = canvasElement;
  const sizeFallback = 1024;
  let cap = sizeFallback;
  try {
    if (typeof sessionStorage !== "undefined" && sessionStorage.getItem("px_history_oom_cap") === "1024") {
      cap = 1024;
    }
  } catch {
  }
  state.canvasWidth = Math.min(wasmRef.canvas.width || sizeFallback, cap);
  state.canvasHeight = Math.min(wasmRef.canvas.height || sizeFallback, cap);
  state.initStartTime = performance.now();
  const base = window.location.pathname.startsWith("/image_video_effects/") ? "/image_video_effects/wasm/" : "/wasm/";
  console.log(`[WASM] Canvas size: ${state.canvasWidth}x${state.canvasHeight}`);
  const mod = await instantiateWasmModule(base);
  if (!mod) {
    state.loadErrorCount++;
    state.initEndTime = performance.now();
    return false;
  }
  wasmRef.module = mod;
  const canvas = wasmRef.canvas;
  if (!canvas) {
    state.lastLoadError = "Canvas missing after module load";
    state.loadErrorCount++;
    state.initEndTime = performance.now();
    return false;
  }
  const canvasId = ensureWasmCanvasId(canvas);
  const selector = "#" + canvasId;
  console.log(`[WASM] Calling initWasmRenderer( ${state.canvasWidth} , ${state.canvasHeight} , ${selector} )`);
  let ok = 0;
  try {
    ok = Number(
      await callSuspending(
        mod,
        "initWasmRenderer",
        "number",
        ["number", "number", "string"],
        [state.canvasWidth, state.canvasHeight, selector]
      )
    );
  } catch (callErr) {
    console.error("[WASM] ccall initWasmRenderer threw:", callErr);
    const cppDiag = readCppInitDiagnostics();
    const detail = formatCppInitFailure(cppDiag);
    const message = callErr instanceof Error ? callErr.message : String(callErr);
    state.lastLoadError = `ccall exception: ${message} (${detail})`;
    state.loadErrorCount++;
    state.initEndTime = performance.now();
    return false;
  }
  if (!ok) {
    const cppDiag = readCppInitDiagnostics();
    const failMsg = formatCppInitFailure(cppDiag);
    console.error(`[WASM] \u274C initWasmRenderer failed: ${failMsg}`);
    if (cppDiag.adapterSummary) {
      console.error(`[WASM] GPU Adapter: ${cppDiag.adapterSummary}`);
    }
    state.lastLoadError = failMsg;
    state.loadErrorCount++;
    state.initEndTime = performance.now();
    return false;
  }
  state.initialized = true;
  state.initEndTime = performance.now();
  const elapsed = state.initEndTime - state.initStartTime;
  console.log(`[WASM] \u2705 Initialization complete in ${elapsed} ms (${state.wasmArtifact ?? "preloaded"} build)`);
  const cppFmt = Number(mod.ccall("getColorFormat", "number", [], []) ?? 0);
  const pending = state.colorFormat;
  if (pending !== 0 && pending !== cppFmt) {
    await callSuspending(mod, "setColorFormat", null, ["number"], [pending]);
  }
  const applied = Number(mod.ccall("getColorFormat", "number", [], []) ?? cppFmt);
  state.colorFormat = applied === 1 ? 1 : 0;
  console.log(
    `[WASM] colorFormat=${state.colorFormat === 1 ? "rgba16float" : "rgba32float"}`
  );
  promoteWasmCanvasVisible(canvas);
  if (state.pendingInputSource !== null) {
    const src = state.pendingInputSource;
    state.pendingInputSource = null;
    const sourceInt = typeof src === "string" ? SOURCE_MAP[src] ?? 0 : src;
    mod.ccall("setInputSource", null, ["number"], [sourceInt]);
    state.inputSource = sourceInt;
  }
  return true;
}
const WASM_ARTIFACT_JS = {
  jspi: "pixelocity_wasm_jspi.js",
  asyncify: "pixelocity_wasm.js"
};
function supportsJspi() {
  const wa = globalThis.WebAssembly;
  return typeof wa?.Suspending === "function" && typeof wa?.promising === "function";
}
function wasmArtifactOrder() {
  return supportsJspi() ? ["jspi", "asyncify"] : ["asyncify"];
}
function loadScript(src) {
  return new Promise((resolve) => {
    const script = document.createElement("script");
    script.src = src;
    script.onload = () => resolve(true);
    script.onerror = () => resolve(false);
    document.head.appendChild(script);
  });
}
async function instantiateWasmModule(base) {
  const locateFile = (path) => base + path;
  if (typeof window.PixelocityWASM === "function") {
    try {
      return await window.PixelocityWASM({ locateFile });
    } catch (err) {
      console.error("[WASM] Module instantiation failed:", err);
      state.lastLoadError = err instanceof Error ? err.message : String(err);
      return null;
    }
  }
  for (const kind of wasmArtifactOrder()) {
    const src = base + WASM_ARTIFACT_JS[kind];
    console.log(`[WASM] Loading ${kind} build from: ${src}`);
    if (!await loadScript(src)) {
      console.error(`[WASM] Failed to load script: ${src}`);
      state.lastLoadError = `Failed to load script: ${src}`;
      continue;
    }
    const factory = window.PixelocityWASM;
    if (typeof factory !== "function") {
      console.error("[WASM] PixelocityWASM factory function not found");
      state.lastLoadError = "Factory PixelocityWASM missing";
      continue;
    }
    try {
      const mod = await factory({ locateFile });
      state.wasmArtifact = kind;
      return mod;
    } catch (err) {
      console.error(`[WASM] ${kind} module instantiation failed:`, err);
      state.lastLoadError = err instanceof Error ? err.message : String(err);
      delete window.PixelocityWASM;
    }
  }
  return null;
}
function shutdownWasmRenderer() {
  if (!state.initialized || !wasmRef.module) {
    return;
  }
  try {
    wasmRef.module.ccall("shutdownWasmRenderer", null, [], []);
  } catch (err) {
    console.error("[WASM] Shutdown error:", err);
  }
  state.initialized = false;
  state.activeShader = null;
  state.droppedSlots.clear();
  wasmRef.module = null;
  wasmRef.canvas = null;
  console.log("[WASM] Shutdown complete");
}
function isInitialized() {
  return state.initialized;
}
function ensureWasmCanvasId(canvas) {
  if (/^pixelocity-wasm-canvas-\d+$/.test(canvas.id)) return canvas.id;
  wasmRef.canvasIdCounter += 1;
  canvas.id = "pixelocity-wasm-canvas-" + wasmRef.canvasIdCounter;
  return canvas.id;
}
function promoteWasmCanvasVisible(canvas) {
  const id = ensureWasmCanvasId(canvas);
  const tagged = document.getElementById(id) ?? canvas;
  tagged.style.display = "block";
  tagged.style.visibility = "visible";
  tagged.style.opacity = "1";
  if (!tagged.style.zIndex || tagged.style.zIndex === "auto") {
    tagged.style.zIndex = "1";
  }
  wasmRef.canvas = tagged;
  console.log(
    `[WASM] Visible present canvas: #${tagged.id} ${tagged.width}\xD7${tagged.height}`
  );
  try {
    window.dispatchEvent(
      new CustomEvent("pixelocity-canvas-replaced", { detail: tagged })
    );
  } catch {
  }
  return tagged;
}
function getPresentCanvas() {
  return wasmRef.canvas;
}
function getPresentCanvasId() {
  const tagged = wasmRef.canvas;
  if (tagged?.id && /^pixelocity-wasm-canvas-\d+$/.test(tagged.id)) return tagged.id;
  if (typeof document === "undefined") return tagged?.id ?? "";
  const found = document.querySelector('[id^="pixelocity-wasm-canvas-"]');
  return found?.id ?? tagged?.id ?? "";
}
export {
  WASM_ARTIFACT_JS,
  ensureWasmCanvasId,
  getPresentCanvas,
  getPresentCanvasId,
  initWasmRenderer,
  isInitialized,
  promoteWasmCanvasVisible,
  shutdownWasmRenderer,
  supportsJspi,
  wasmArtifactOrder
};
