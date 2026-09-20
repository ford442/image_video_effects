import { callSuspending } from './call.js';
import { formatCppInitFailure, readCppInitDiagnostics } from './diagnostics.js';
import { state, wasmRef } from './state.js';
import type { EmscriptenModule, PixelocityWasmFactory, WasmArtifactKind } from './state.js';

const SOURCE_MAP: Record<string, number> = {
  none: 0,
  image: 1,
  video: 2,
  webcam: 3,
  generative: 4,
  live: 5,
};

export async function initWasmRenderer(canvasElement: HTMLCanvasElement): Promise<boolean> {
  if (state.initialized) {
    console.warn('[WASM] Renderer already initialized');
    return true;
  }

  wasmRef.canvas = canvasElement;
  // Keep key in sync with src/config/vramBudget.ts HISTORY_OOM_CAP_KEY (#1204).
  // Default working size is 1024; never pass 2048 as the first WASM committed resource.
  const sizeFallback = 1024;
  let cap = sizeFallback;
  try {
    if (typeof sessionStorage !== 'undefined' && sessionStorage.getItem('px_history_oom_cap') === '1024') {
      cap = 1024;
    }
  } catch {
    /* private mode */
  }
  state.canvasWidth = Math.min(wasmRef.canvas.width || sizeFallback, cap);
  state.canvasHeight = Math.min(wasmRef.canvas.height || sizeFallback, cap);
  state.initStartTime = performance.now();

  const base = window.location.pathname.startsWith('/image_video_effects/')
    ? '/image_video_effects/wasm/'
    : '/wasm/';
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
    state.lastLoadError = 'Canvas missing after module load';
    state.loadErrorCount++;
    state.initEndTime = performance.now();
    return false;
  }

  const canvasId = ensureWasmCanvasId(canvas);
  const selector = '#' + canvasId;
  // C++ signature: initWasmRenderer(int width, int height, const char* canvasSelector)
  // Passing selector first made the UTF-8 heap pointer the "width" (~79984) and
  // maxTextureDimension2D CheckLimit treated that pointer as need → false INSUFFICIENT.
  console.log(`[WASM] Calling initWasmRenderer( ${state.canvasWidth} , ${state.canvasHeight} , ${selector} )`);

  let ok = 0;
  try {
    // Suspends in WaitAny (adapter/device/error scopes) under both builds.
    ok = Number(
      await callSuspending(
        mod,
        'initWasmRenderer',
        'number',
        ['number', 'number', 'string'],
        [state.canvasWidth, state.canvasHeight, selector],
      ),
    );
  } catch (callErr: unknown) {
    console.error('[WASM] ccall initWasmRenderer threw:', callErr);
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
    console.error(`[WASM] ❌ initWasmRenderer failed: ${failMsg}`);
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
  console.log(`[WASM] ✅ Initialization complete in ${elapsed} ms (${state.wasmArtifact ?? 'preloaded'} build)`);

  const cppFmt = Number(mod.ccall('getColorFormat', 'number', [], []) ?? 0);
  const pending = state.colorFormat;
  if (pending !== 0 && pending !== cppFmt) {
    await callSuspending(mod, 'setColorFormat', null, ['number'], [pending]);
  }
  const applied = Number(mod.ccall('getColorFormat', 'number', [], []) ?? cppFmt);
  state.colorFormat = applied === 1 ? 1 : 0;
  console.log(
    `[WASM] colorFormat=${state.colorFormat === 1 ? 'rgba16float' : 'rgba32float'}`,
  );

  promoteWasmCanvasVisible(canvas);

  if (state.pendingInputSource !== null) {
    const src = state.pendingInputSource;
    state.pendingInputSource = null;
    const sourceInt = typeof src === 'string' ? (SOURCE_MAP[src] ?? 0) : src;
    mod.ccall('setInputSource', null, ['number'], [sourceInt]);
    state.inputSource = sourceInt;
  }

  return true;
}

/**
 * Emscripten JS glue per build. Must match wasm_compile_flags.json
 * jspi.jsOutputName / jsOutputName (verify:wasm-invariants). Both glue files
 * register the same `PixelocityWASM` factory.
 */
export const WASM_ARTIFACT_JS: Record<WasmArtifactKind, string> = {
  jspi: 'pixelocity_wasm_jspi.js',
  asyncify: 'pixelocity_wasm.js',
};

/** JSPI (WebAssembly.Suspending + promising) is available in this engine. */
export function supportsJspi(): boolean {
  const wa = (globalThis as { WebAssembly?: Record<string, unknown> }).WebAssembly;
  return typeof wa?.Suspending === 'function' && typeof wa?.promising === 'function';
}

/** Builds to try in order. ASYNCIFY is always last — never JSPI-only. */
export function wasmArtifactOrder(): WasmArtifactKind[] {
  return supportsJspi() ? ['jspi', 'asyncify'] : ['asyncify'];
}

function loadScript(src: string): Promise<boolean> {
  return new Promise((resolve) => {
    const script = document.createElement('script');
    script.src = src;
    script.onload = () => resolve(true);
    script.onerror = () => resolve(false);
    document.head.appendChild(script);
  });
}

/**
 * Load + instantiate the first build that works. A factory already on window
 * (earlier init in this tab, or a test) is reused as-is.
 */
async function instantiateWasmModule(base: string): Promise<EmscriptenModule | null> {
  const locateFile = (path: string) => base + path;

  if (typeof window.PixelocityWASM === 'function') {
    try {
      return await window.PixelocityWASM({ locateFile });
    } catch (err: unknown) {
      console.error('[WASM] Module instantiation failed:', err);
      state.lastLoadError = err instanceof Error ? err.message : String(err);
      return null;
    }
  }

  for (const kind of wasmArtifactOrder()) {
    const src = base + WASM_ARTIFACT_JS[kind];
    console.log(`[WASM] Loading ${kind} build from: ${src}`);
    if (!(await loadScript(src))) {
      console.error(`[WASM] Failed to load script: ${src}`);
      state.lastLoadError = `Failed to load script: ${src}`;
      continue;
    }
    // Re-read: the script we just loaded registers it (TS narrowed it to undefined above).
    const factory = window.PixelocityWASM as PixelocityWasmFactory | undefined;
    if (typeof factory !== 'function') {
      console.error('[WASM] PixelocityWASM factory function not found');
      state.lastLoadError = 'Factory PixelocityWASM missing';
      continue;
    }
    try {
      const mod = await factory({ locateFile });
      state.wasmArtifact = kind;
      return mod;
    } catch (err: unknown) {
      console.error(`[WASM] ${kind} module instantiation failed:`, err);
      state.lastLoadError = err instanceof Error ? err.message : String(err);
      // Let the next build's glue register a fresh factory.
      delete window.PixelocityWASM;
    }
  }
  return null;
}

export function shutdownWasmRenderer(): void {
  if (!state.initialized || !wasmRef.module) {
    return;
  }

  try {
    wasmRef.module.ccall('shutdownWasmRenderer', null, [], []);
  } catch (err) {
    console.error('[WASM] Shutdown error:', err);
  }

  state.initialized = false;
  state.activeShader = null;
  state.droppedSlots.clear();
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
