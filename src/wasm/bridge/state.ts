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
};

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
