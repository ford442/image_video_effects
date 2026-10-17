// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

import * as cpp from "./_generated.js";
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
const CPP_INIT_TIMEOUT_MS = 2e4;
function awaitCppInit(call, timeoutMs = CPP_INIT_TIMEOUT_MS) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => resolve("timeout"), timeoutMs);
    call.then(
      (ok) => {
        clearTimeout(timer);
        resolve(ok === 1 ? "ready" : "failed");
      },
      (err) => {
        clearTimeout(timer);
        reject(err);
      }
    );
  });
}
function reapAbandonedInit(mod, call) {
  call.then(
    () => {
      try {
        cpp.shutdownWasmRenderer(mod);
        console.log("[WASM] Abandoned init settled; C++ renderer shut down");
      } catch (err) {
        console.error("[WASM] Abandoned init shutdown error:", err);
      }
    },
    (err) => console.error("[WASM] Abandoned init rejected:", err)
  );
}
function wasmArtifactName(search = typeof window === "undefined" ? "" : window.location.search) {
  return new URLSearchParams(search).get("wasm_debug") === "1" ? "pixelocity_wasm.debug.js" : "pixelocity_wasm.js";
}
async function initWasmRenderer(canvasElement) {
  if (state.initialized) {
    console.warn("[WASM] Renderer already initialized");
    return true;
  }
  state.initTimedOut = false;
  wasmRef.canvas = canvasElement;
  const sizeCap = 1024;
  state.canvasWidth = Math.min(wasmRef.canvas.width || sizeCap, sizeCap);
  state.canvasHeight = Math.min(wasmRef.canvas.height || sizeCap, sizeCap);
  state.initStartTime = performance.now();
  return new Promise((resolve) => {
    const pathname = window.location.pathname;
    const isUnderSubpath = pathname.startsWith("/image_video_effects/");
    const artifact = wasmArtifactName();
    const wasmJsPath = (isUnderSubpath ? "/image_video_effects/wasm/" : "/wasm/") + artifact;
    console.log(`[WASM] Loading from: ${wasmJsPath}`);
    console.log(`[WASM] Canvas size: ${state.canvasWidth}x${state.canvasHeight}`);
    let handled = false;
    const handleLoad = () => {
      if (handled) return;
      handled = true;
      if (typeof window.PixelocityWASM !== "function") {
        console.error("[WASM] PixelocityWASM factory function not found");
        state.lastLoadError = "Factory PixelocityWASM missing";
        state.loadErrorCount++;
        resolve(false);
        return;
      }
      console.log("[WASM] Creating module from factory...");
      const wasmLocatePath = isUnderSubpath ? "/image_video_effects/wasm/" : "/wasm/";
      window.PixelocityWASM({
        locateFile: (path) => wasmLocatePath + path
      }).then((mod) => {
        wasmRef.module = mod;
        const canvas = wasmRef.canvas;
        if (!canvas) {
          state.lastLoadError = "Canvas missing after module load";
          state.loadErrorCount++;
          state.initEndTime = performance.now();
          resolve(false);
          return;
        }
        const canvasId = ensureWasmCanvasId(canvas);
        const selector = "#" + canvasId;
        console.log(`[WASM] Calling initWasmRenderer( ${state.canvasWidth} , ${state.canvasHeight} , ${selector} )`);
        let initCall;
        try {
          initCall = cpp.initWasmRenderer(mod, state.canvasWidth, state.canvasHeight, selector);
        } catch (callErr) {
          initCall = Promise.reject(callErr);
        }
        return awaitCppInit(initCall).catch((callErr) => {
          console.error("[WASM] initWasmRenderer threw:", callErr);
          const detail = formatCppInitFailure(readCppInitDiagnostics());
          const message = callErr instanceof Error ? callErr.message : String(callErr);
          state.lastLoadError = `ccall exception: ${message} (${detail})`;
          return "threw";
        }).then((outcome) => {
          if (outcome === "threw") {
            state.loadErrorCount++;
            state.initEndTime = performance.now();
            resolve(false);
            return;
          }
          if (outcome === "timeout") {
            state.initTimedOut = true;
            state.lastLoadError = `C++ Initialize() still pending after ${CPP_INIT_TIMEOUT_MS / 1e3} s (suspended in WaitAny)`;
            state.loadErrorCount++;
            state.initEndTime = performance.now();
            console.error(`[WASM] \u274C ${state.lastLoadError}; abandoning this module`);
            wasmRef.module = null;
            wasmRef.canvas = null;
            reapAbandonedInit(mod, initCall);
            resolve(false);
            return;
          }
          if (outcome === "ready" && cpp.isRendererInitialized(mod) === 1) {
            state.initialized = true;
            state.initEndTime = performance.now();
            const elapsed = state.initEndTime - state.initStartTime;
            console.log(`[WASM] \u2705 Initialization complete in ${elapsed} ms`);
            const cppFmt = cpp.getColorFormat(mod);
            const pending = state.colorFormat;
            const formatApplied = pending !== 0 && pending !== cppFmt ? cpp.setColorFormat(mod, pending).catch((err) => {
              console.error("[WASM] setColorFormat after init failed:", err);
            }) : Promise.resolve();
            return formatApplied.then(() => {
              state.colorFormat = cpp.getColorFormat(mod) === 1 ? 1 : 0;
              console.log(
                `[WASM] colorFormat=${state.colorFormat === 1 ? "rgba16float" : "rgba32float"}`
              );
              state.maxShaderSlots = cpp.getMaxShaderSlots(mod);
              console.log(`[WASM] maxShaderSlots=${state.maxShaderSlots ?? "unknown (artifact predates export)"}`);
              promoteWasmCanvasVisible(canvas);
              if (state.pendingInputSource !== null) {
                const src = state.pendingInputSource;
                state.pendingInputSource = null;
                const sourceInt = typeof src === "string" ? SOURCE_MAP[src] ?? 0 : src;
                cpp.setInputSource(mod, sourceInt);
                state.inputSource = sourceInt;
              }
              resolve(true);
            });
          } else {
            const cppDiag = readCppInitDiagnostics();
            const failMsg = formatCppInitFailure(cppDiag);
            console.error(`[WASM] \u274C initWasmRenderer failed: ${failMsg}`);
            if (cppDiag.adapterSummary) {
              console.error(`[WASM] GPU Adapter: ${cppDiag.adapterSummary}`);
            }
            state.lastLoadError = failMsg;
            state.loadErrorCount++;
            state.initEndTime = performance.now();
            resolve(false);
          }
        });
      }).catch((err) => {
        console.error("[WASM] Module instantiation failed:", err);
        state.lastLoadError = err instanceof Error ? err.message : String(err);
        state.loadErrorCount++;
        state.initEndTime = performance.now();
        resolve(false);
      });
    };
    const script = document.createElement("script");
    script.src = wasmJsPath;
    script.onload = handleLoad;
    script.onerror = () => {
      if (handled) return;
      handled = true;
      console.error(`[WASM] Failed to load script: ${wasmJsPath}`);
      state.lastLoadError = `Failed to load script: ${wasmJsPath}`;
      state.loadErrorCount++;
      state.initEndTime = performance.now();
      resolve(false);
    };
    document.head.appendChild(script);
    if (typeof window.PixelocityWASM === "function") {
      queueMicrotask(handleLoad);
    }
  });
}
function shutdownWasmRenderer() {
  if (!state.initialized || !wasmRef.module) {
    return;
  }
  try {
    cpp.shutdownWasmRenderer(wasmRef.module);
  } catch (err) {
    console.error("[WASM] Shutdown error:", err);
  }
  state.initialized = false;
  state.activeShader = null;
  state.droppedSlots.clear();
  state.maxShaderSlots = null;
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
  CPP_INIT_TIMEOUT_MS,
  ensureWasmCanvasId,
  getPresentCanvas,
  getPresentCanvasId,
  initWasmRenderer,
  isInitialized,
  promoteWasmCanvasVisible,
  shutdownWasmRenderer,
  wasmArtifactName
};
