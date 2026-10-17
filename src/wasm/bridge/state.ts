import * as cpp from './_generated.js';

/**
 * Emscripten runtime surface the bridge uses (wasm_exports.json
 * exportedRuntimeMethods + the heap). Exports are never called through this
 * type: every call goes through the generated wrappers in _generated.ts, whose
 * signatures come from the contract and are diffed against the --emit-tsd
 * output (public/wasm/pixelocity_wasm.d.ts) by verify:wasm-bridge-sync.
 */
export interface EmscriptenModule {
  ccall(
    ident: string,
    returnType: string | null,
    argTypes: string[],
    args: unknown[],
    opts?: { async?: boolean },
  ): unknown;
  _malloc(size: number): number;
  _free(ptr: number): void;
  getValue(ptr: number, type: string): number;
  lengthBytesUTF8(str: string): number;
  stringToUTF8(str: string, ptr: number, maxBytes: number): void;
  UTF8ToString?(ptr: number): string;
  HEAPU8: Uint8Array;
  HEAPF32: Float32Array;
  /** Hand-off slot read (and cleared) by the C++ JS_CopyExternalImageToTexture EM_JS. */
  pixelocityPendingImage?: unknown;
  /** Set by awaitSubmittedWorkDone(); called from the C++ work-done callback. */
  __pxWorkDone?: (ok: number) => void;
}

export type PixelocityWasmFactory = (opts: {
  locateFile: (path: string) => string;
}) => Promise<EmscriptenModule>;

declare global {
  interface Window {
    PixelocityWASM?: PixelocityWasmFactory;
  }
}

/**
 * Bytes for `str` plus its NUL. lengthBytesUTF8 is an exported runtime method
 * (wasm_exports.json). Never feature-test an unexported one with `typeof`: under
 * ASSERTIONS (the debug profile) Emscripten's stub getter aborts the module.
 */
export function utf8ByteLength(module: EmscriptenModule, str: string): number {
  return module.lengthBytesUTF8(str) + 1;
}

export const wasmRef: {
  module: EmscriptenModule | null;
  canvas: HTMLCanvasElement | null;
  canvasIdCounter: number;
} = {
  module: null,
  canvas: null,
  canvasIdCounter: 0,
};

export const state = {
  initialized: false,
  activeShader: null as string | null,
  canvasWidth: 0,
  canvasHeight: 0,
  time: 0,
  mouseX: 0.5,
  mouseY: 0.5,
  mouseDown: false,
  zoomParams: [0.5, 0.5, 0.5, 0.5] as [number, number, number, number],
  slotParams: [
    [0.5, 0.5, 0.5, 0.5],
    [0.5, 0.5, 0.5, 0.5],
    [0.5, 0.5, 0.5, 0.5],
  ] as [number, number, number, number][],
  ripples: [] as unknown[],
  inputSource: 1 as number | string,
  pendingInputSource: null as number | string | null,
  loadErrorCount: 0,
  lastLoadError: null as string | null,
  initStartTime: 0,
  initEndTime: 0,
  colorFormat: 0 as 0 | 1,
  /** Slot indexes whose last setSlotShader the module did not accept. */
  droppedSlots: new Set<number>(),
  /** MAX_SHADER_SLOTS compiled into the loaded artifact; null = older binary without the export. */
  maxShaderSlots: null as number | null,
  /**
   * The last init gave up while C++ was still suspended in WaitAny (bridge backstop,
   * init.ts CPP_INIT_TIMEOUT_MS). That module was abandoned to the reaper, so the
   * C++ stage is unreadable; diagnostics report failedStageName 'Timeout'.
   */
  initTimedOut: false,
};

/**
 * C++ finished Initialize() (device + surface). Anything C++ decides during
 * init (the canvas COPY_SRC probe) is only meaningful once this is true.
 */
export function isCppRendererReady(): boolean {
  const mod = wasmRef.module;
  if (!state.initialized || !mod) return false;
  try {
    return cpp.isRendererInitialized(mod) === 1;
  } catch {
    return false;
  }
}

/**
 * Live C++ canvas COPY_SRC probe result (canvas_configure.json optIn.copySrc):
 * null while C++ init is still running or when the artifact predates the export.
 */
export function readCanvasCopySrc(): boolean | null {
  const mod = wasmRef.module;
  if (!mod || !isCppRendererReady()) return null;
  const supported = cpp.getCanvasCopySrcSupported(mod);
  return supported === null ? null : supported === 1;
}

export const INIT_STAGE_NAMES: Record<number, string> = {
  0: 'None',
  1: 'Instance',
  2: 'Adapter',
  3: 'Device',
  4: 'Surface',
  5: 'Resources',
  6: 'BindGroups',
  7: 'Pipeline',
  8: 'Ready',
};
