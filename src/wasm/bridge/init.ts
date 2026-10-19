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

/**
 * Bridge backstop for C++ Initialize(). The ASYNCIFY init ccall returns as soon as
 * CreateDevice() suspends in wgpuInstanceWaitAny, so the bridge polls C++ instead
 * of trusting that return value. C++ times its own adapter/device waits out
 * (device.cpp: 4 × 3 s + 5 s = 17 s); this only fires if C++ is still suspended.
 */
export const CPP_INIT_TIMEOUT_MS = 20_000;
const CPP_INIT_POLL_MS = 50;
/** How long an abandoned (timed-out) init is watched before it is left to leak. */
const REAP_POLL_MS = 500;
const REAP_MAX_MS = 5 * 60_000;

type CppInitOutcome = 'ready' | 'failed' | 'pending';

/**
 * Plain getters only (no ASYNCIFY), so they are safe while Initialize() is
 * suspended. Never call shutdown / anything that touches the instance until this
 * is no longer 'pending': destroying the instance mid-WaitAny crashes the tab.
 */
function readCppInitOutcome(mod: EmscriptenModule): CppInitOutcome {
  try {
    if (Number(mod.ccall('isRendererInitialized', 'number', [], [])) === 1) return 'ready';
    const stage = Number(mod.ccall('getLastInitErrorStage', 'number', [], []) ?? 0);
    // 0 = None (still running), 8 = Ready; anything else is a stage C++ failed at
    // after running its own Shutdown().
    return stage > 0 && stage < 8 ? 'failed' : 'pending';
  } catch {
    return 'pending';
  }
}

function waitForCppInit(
  mod: EmscriptenModule,
  timeoutMs = CPP_INIT_TIMEOUT_MS,
): Promise<CppInitOutcome | 'timeout'> {
  const deadline = performance.now() + timeoutMs;
  return new Promise((resolve) => {
    const poll = () => {
      const outcome = readCppInitOutcome(mod);
      if (outcome !== 'pending') resolve(outcome);
      else if (performance.now() >= deadline) resolve('timeout');
      else setTimeout(poll, CPP_INIT_POLL_MS);
    };
    poll();
  });
}

/**
 * Shut a timed-out init down the way a failed init is: once C++ settles (ready, or
 * failed after its own Shutdown()), release the renderer. A WaitAny that never
 * returns leaks this one module rather than destroying the instance under it.
 */
function reapAbandonedInit(mod: EmscriptenModule): void {
  const deadline = performance.now() + REAP_MAX_MS;
  const poll = () => {
    if (readCppInitOutcome(mod) !== 'pending') {
      try {
        mod.ccall('shutdownWasmRenderer', null, [], []);
        console.log('[WASM] Abandoned init settled; C++ renderer shut down');
      } catch (err) {
        console.error('[WASM] Abandoned init shutdown error:', err);
      }
      return;
    }
    if (performance.now() >= deadline) {
      console.warn('[WASM] Abandoned init never settled; leaking that module (instance not destroyed)');
      return;
    }
    setTimeout(poll, REAP_POLL_MS);
  };
  setTimeout(poll, REAP_POLL_MS);
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
    // { async: true } waits out WaitAny. The poll is the backstop if that
    // promise never settles (C++ still suspended past CPP_INIT_TIMEOUT_MS).
    const raced = await Promise.race([
      callSuspending(
        mod,
        'initWasmRenderer',
        'number',
        ['number', 'number', 'string'],
        [state.canvasWidth, state.canvasHeight, selector],
      ).then((value) => ({ tag: 'call' as const, value })),
      waitForCppInit(mod).then((outcome) => ({ tag: 'poll' as const, outcome })),
    ]);
    if (raced.tag === 'poll' && raced.outcome === 'timeout') {
      state.initTimedOut = true;
      state.lastLoadError =
        `C++ Initialize() still pending after ${CPP_INIT_TIMEOUT_MS / 1000} s (suspended in WaitAny)`;
      state.loadErrorCount++;
      state.initEndTime = performance.now();
      console.error(`[WASM] ❌ ${state.lastLoadError}; abandoning this module`);
      wasmRef.module = null;
      wasmRef.canvas = null;
      reapAbandonedInit(mod);
      return false;
    }
    if (raced.tag === 'poll') {
      ok = raced.outcome === 'ready' ? 1 : 0;
    } else {
      ok = Number(raced.value);
      const settled = readCppInitOutcome(mod);
      if (settled === 'failed') ok = 0;
      else if (settled === 'ready') ok = 1;
    }
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

  state.maxShaderSlots = typeof mod._getMaxShaderSlots === 'function'
    ? mod._getMaxShaderSlots()
    : null;
  console.log(`[WASM] maxShaderSlots=${state.maxShaderSlots ?? 'unknown (artifact predates export)'}`);

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

