/** Minimal Emscripten module surface used by the WASM JS glue. */
export interface EmscriptenModule {
  ccall(
    ident: string,
    returnType: string | null,
    argTypes: string[],
    args: unknown[],
  ): unknown;
  _malloc(size: number): number;
  _free(ptr: number): void;
  getValue(ptr: number, type: string): number;
  lengthBytesUTF8?(str: string): number;
  stringToUTF8(str: string, ptr: number, maxBytes: number): void;
  HEAPU8: Uint8Array;
  HEAPF32: Float32Array;
  /** Hand-off slot read (and cleared) by the C++ JS_CopyExternalImageToTexture EM_JS. */
  pixelocityPendingImage?: unknown;
  /** Present only in artifacts built with canvas COPY_SRC parity (older binaries lack them). */
  _getCanvasCopySrcSupported?: () => number;
  _setCanvasCopySrc?: (enabled: number) => number;
  _getMaxShaderSlots?: () => number;
}

export type PixelocityWasmFactory = (opts: {
  locateFile: (path: string) => string;
}) => Promise<EmscriptenModule>;

declare global {
  interface Window {
    PixelocityWASM?: PixelocityWasmFactory;
  }
}

export function utf8ByteLength(module: EmscriptenModule, str: string): number {
  if (typeof module.lengthBytesUTF8 === 'function') {
    return module.lengthBytesUTF8(str) + 1;
  }
  return new TextEncoder().encode(str).length + 1;
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
};

/**
 * C++ finished Initialize() (device + surface). The init ccall can return
 * before that while CreateDevice() is suspended on the adapter/device request,
 * so anything C++ decides during init (the canvas COPY_SRC probe) must be read
 * after this is true.
 */
export function isCppRendererReady(): boolean {
  const mod = wasmRef.module;
  if (!state.initialized || !mod) return false;
  try {
    return Number(mod.ccall('isRendererInitialized', 'number', [], [])) === 1;
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
  if (!mod || typeof mod._getCanvasCopySrcSupported !== 'function') return null;
  if (!isCppRendererReady()) return null;
  return mod._getCanvasCopySrcSupported() === 1;
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
