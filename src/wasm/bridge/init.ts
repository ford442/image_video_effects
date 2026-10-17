import * as cpp from './_generated.js';
import { formatCppInitFailure, readCppInitDiagnostics } from './diagnostics.js';
import { state, wasmRef, type EmscriptenModule } from './state.js';

const SOURCE_MAP: Record<string, number> = {
  none: 0,
  image: 1,
  video: 2,
  webcam: 3,
  generative: 4,
  live: 5,
};

/**
 * Bridge backstop for C++ Initialize(). initWasmRenderer is an async export:
 * the generated wrapper ccalls it with { async: true }, so its promise settles
 * only when Initialize() really returns. C++ times its own adapter/device waits
 * out (device.cpp: 4 × 3 s + 5 s = 17 s); this only fires if C++ is still
 * suspended after that.
 */
export const CPP_INIT_TIMEOUT_MS = 20_000;

type CppInitOutcome = 'ready' | 'failed' | 'timeout';

function awaitCppInit(call: Promise<number>, timeoutMs = CPP_INIT_TIMEOUT_MS): Promise<CppInitOutcome> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => resolve('timeout'), timeoutMs);
    call.then(
      (ok) => {
        clearTimeout(timer);
        resolve(ok === 1 ? 'ready' : 'failed');
      },
      (err: unknown) => {
        clearTimeout(timer);
        reject(err);
      },
    );
  });
}

/**
 * A timed-out init is shut down the way a failed one is, once its Initialize()
 * call finally returns. One that never returns leaks this module rather than
 * destroying the instance under a suspended WaitAny (that crashes the tab).
 */
function reapAbandonedInit(mod: EmscriptenModule, call: Promise<number>): void {
  call.then(
    () => {
      try {
        cpp.shutdownWasmRenderer(mod);
        console.log('[WASM] Abandoned init settled; C++ renderer shut down');
      } catch (err) {
        console.error('[WASM] Abandoned init shutdown error:', err);
      }
    },
    (err: unknown) => console.error('[WASM] Abandoned init rejected:', err),
  );
}

/**
 * `?wasm_debug=1` loads the debug profile (npm run wasm:build:debug;
 * wasm_compile_flags.json profiles.debug): Emscripten ASSERTIONS=2, DWARF and a
 * source map. Same factory name, so nothing else changes. Not deployed.
 */
export function wasmArtifactName(search = typeof window === 'undefined' ? '' : window.location.search): string {
  return new URLSearchParams(search).get('wasm_debug') === '1' ? 'pixelocity_wasm.debug.js' : 'pixelocity_wasm.js';
}

export async function initWasmRenderer(canvasElement: HTMLCanvasElement): Promise<boolean> {
  if (state.initialized) {
    console.warn('[WASM] Renderer already initialized');
    return true;
  }
  state.initTimedOut = false;

  wasmRef.canvas = canvasElement;
  // Never pass more than HISTORY_SAFE_WORKING_SIZE (src/config/vramBudget.ts, 1024) as the
  // first WASM committed resource (#1204). The cap is unconditional, so the OOM-cap
  // sessionStorage flag cannot raise or lower it and is not read here.
  const sizeCap = 1024;
  state.canvasWidth = Math.min(wasmRef.canvas.width || sizeCap, sizeCap);
  state.canvasHeight = Math.min(wasmRef.canvas.height || sizeCap, sizeCap);
  state.initStartTime = performance.now();

  return new Promise((resolve) => {
    const pathname = window.location.pathname;
    const isUnderSubpath = pathname.startsWith('/image_video_effects/');
    const artifact = wasmArtifactName();
    const wasmJsPath = (isUnderSubpath ? '/image_video_effects/wasm/' : '/wasm/') + artifact;
    console.log(`[WASM] Loading from: ${wasmJsPath}`);
    console.log(`[WASM] Canvas size: ${state.canvasWidth}x${state.canvasHeight}`);

    let handled = false;
    const handleLoad = () => {
      if (handled) return;
      handled = true;

      if (typeof window.PixelocityWASM !== 'function') {
        console.error('[WASM] PixelocityWASM factory function not found');
        state.lastLoadError = 'Factory PixelocityWASM missing';
        state.loadErrorCount++;
        resolve(false);
        return;
      }

      console.log('[WASM] Creating module from factory...');

      const wasmLocatePath = isUnderSubpath
        ? '/image_video_effects/wasm/'
        : '/wasm/';

      window.PixelocityWASM({
        locateFile: (path) => wasmLocatePath + path,
      }).then((mod) => {
        wasmRef.module = mod;

        const canvas = wasmRef.canvas;
        if (!canvas) {
          state.lastLoadError = 'Canvas missing after module load';
          state.loadErrorCount++;
          state.initEndTime = performance.now();
          resolve(false);
          return;
        }

        const canvasId = ensureWasmCanvasId(canvas);

        const selector = '#' + canvasId;
        // C++ signature: initWasmRenderer(int width, int height, const char* canvasSelector)
        // Passing selector first made the UTF-8 heap pointer the "width" (~79984) and
        // maxTextureDimension2D CheckLimit treated that pointer as need → false INSUFFICIENT.
        console.log(`[WASM] Calling initWasmRenderer( ${state.canvasWidth} , ${state.canvasHeight} , ${selector} )`);

        let initCall: Promise<number>;
        try {
          initCall = cpp.initWasmRenderer(mod, state.canvasWidth, state.canvasHeight, selector);
        } catch (callErr: unknown) {
          initCall = Promise.reject(callErr);
        }

        return awaitCppInit(initCall).catch((callErr: unknown) => {
          console.error('[WASM] initWasmRenderer threw:', callErr);
          const detail = formatCppInitFailure(readCppInitDiagnostics());
          const message = callErr instanceof Error ? callErr.message : String(callErr);
          state.lastLoadError = `ccall exception: ${message} (${detail})`;
          return 'threw' as const;
        }).then((outcome) => {
          if (outcome === 'threw') {
            state.loadErrorCount++;
            state.initEndTime = performance.now();
            resolve(false);
            return;
          }

          if (outcome === 'timeout') {
            state.initTimedOut = true;
            state.lastLoadError =
              `C++ Initialize() still pending after ${CPP_INIT_TIMEOUT_MS / 1000} s (suspended in WaitAny)`;
            state.loadErrorCount++;
            state.initEndTime = performance.now();
            console.error(`[WASM] ❌ ${state.lastLoadError}; abandoning this module`);
            // Drop every bridge path into the suspended module; only the reaper keeps it.
            wasmRef.module = null;
            wasmRef.canvas = null;
            reapAbandonedInit(mod, initCall);
            resolve(false);
            return;
          }

          if (outcome === 'ready' && cpp.isRendererInitialized(mod) === 1) {
            state.initialized = true;
            state.initEndTime = performance.now();
            const elapsed = state.initEndTime - state.initStartTime;
            console.log(`[WASM] ✅ Initialization complete in ${elapsed} ms`);

            // setColorFormat is async (RecreateTextures can suspend): finish it
            // before reporting ready, so the first loadShader sees the final format.
            const cppFmt = cpp.getColorFormat(mod);
            const pending = state.colorFormat;
            const formatApplied =
              pending !== 0 && pending !== cppFmt
                ? cpp.setColorFormat(mod, pending).catch((err: unknown) => {
                    console.error('[WASM] setColorFormat after init failed:', err);
                  })
                : Promise.resolve();
            return formatApplied.then(() => {
              state.colorFormat = cpp.getColorFormat(mod) === 1 ? 1 : 0;
              console.log(
                `[WASM] colorFormat=${state.colorFormat === 1 ? 'rgba16float' : 'rgba32float'}`,
              );

              // Compile-time constant. The canvas COPY_SRC probe is read live via
              // readCanvasCopySrc().
              state.maxShaderSlots = cpp.getMaxShaderSlots(mod);
              console.log(`[WASM] maxShaderSlots=${state.maxShaderSlots ?? 'unknown (artifact predates export)'}`);

              promoteWasmCanvasVisible(canvas);

              if (state.pendingInputSource !== null) {
                const src = state.pendingInputSource;
                state.pendingInputSource = null;
                const sourceInt = typeof src === 'string' ? (SOURCE_MAP[src] ?? 0) : src;
                cpp.setInputSource(mod, sourceInt);
                state.inputSource = sourceInt;
              }

              resolve(true);
            });
          } else {
            const cppDiag = readCppInitDiagnostics();
            const failMsg = formatCppInitFailure(cppDiag);
            console.error(`[WASM] ❌ initWasmRenderer failed: ${failMsg}`);
            if (cppDiag.adapterSummary) {
              console.error(`[WASM] GPU Adapter: ${cppDiag.adapterSummary}`);
            }
            state.lastLoadError = failMsg;
            state.loadErrorCount++;
            state.initEndTime = performance.now();
            resolve(false);
          }
        });
      }).catch((err: unknown) => {
        console.error('[WASM] Module instantiation failed:', err);
        state.lastLoadError = err instanceof Error ? err.message : String(err);
        state.loadErrorCount++;
        state.initEndTime = performance.now();
        resolve(false);
      });
    };

    const script = document.createElement('script');
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

    if (typeof window.PixelocityWASM === 'function') {
      queueMicrotask(handleLoad);
    }
  });
}

export function shutdownWasmRenderer(): void {
  if (!state.initialized || !wasmRef.module) {
    return;
  }

  try {
    // Queued behind any suspended call: destroying the instance mid-WaitAny crashes the tab.
    cpp.shutdownWasmRenderer(wasmRef.module);
  } catch (err) {
    console.error('[WASM] Shutdown error:', err);
  }

  state.initialized = false;
  state.activeShader = null;
  state.droppedSlots.clear();
  state.maxShaderSlots = null;
  wasmRef.module = null;
  wasmRef.canvas = null;
  console.log('[WASM] Shutdown complete');
}

export function isInitialized(): boolean {
  return state.initialized;
}

/** Stable CSS id so C++ `JS_CreateSurfaceFromCanvas` and the visible node agree. */
export function ensureWasmCanvasId(canvas: HTMLCanvasElement): string {
  if (/^pixelocity-wasm-canvas-\d+$/.test(canvas.id)) return canvas.id;
  wasmRef.canvasIdCounter += 1;
  canvas.id = 'pixelocity-wasm-canvas-' + wasmRef.canvasIdCounter;
  return canvas.id;
}

/**
 * Present target after exclusive JS→WASM device switch (#1206).
 * Keep `#pixelocity-wasm-canvas-N` on-screen and notify React refs.
 */
export function promoteWasmCanvasVisible(canvas: HTMLCanvasElement): HTMLCanvasElement {
  const id = ensureWasmCanvasId(canvas);
  const tagged = (document.getElementById(id) as HTMLCanvasElement | null) ?? canvas;
  tagged.style.display = 'block';
  tagged.style.visibility = 'visible';
  tagged.style.opacity = '1';
  if (!tagged.style.zIndex || tagged.style.zIndex === 'auto') {
    tagged.style.zIndex = '1';
  }
  wasmRef.canvas = tagged;
  console.log(
    `[WASM] Visible present canvas: #${tagged.id} ${tagged.width}×${tagged.height}`,
  );
  try {
    window.dispatchEvent(
      new CustomEvent('pixelocity-canvas-replaced', { detail: tagged }),
    );
  } catch {
    /* non-browser / tests */
  }
  return tagged;
}

export function getPresentCanvas(): HTMLCanvasElement | null {
  return wasmRef.canvas;
}

export function getPresentCanvasId(): string {
  const tagged = wasmRef.canvas;
  if (tagged?.id && /^pixelocity-wasm-canvas-\d+$/.test(tagged.id)) return tagged.id;
  if (typeof document === 'undefined') return tagged?.id ?? '';
  const found = document.querySelector<HTMLCanvasElement>('[id^="pixelocity-wasm-canvas-"]');
  return found?.id ?? tagged?.id ?? '';
}

