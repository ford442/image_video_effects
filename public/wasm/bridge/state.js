// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

function utf8ByteLength(module, str) {
  if (typeof module.lengthBytesUTF8 === "function") {
    return module.lengthBytesUTF8(str) + 1;
  }
  return new TextEncoder().encode(str).length + 1;
}
const wasmRef = {
  module: null,
  canvas: null,
  canvasIdCounter: 0
};
const state = {
  initialized: false,
  activeShader: null,
  canvasWidth: 0,
  canvasHeight: 0,
  time: 0,
  mouseX: 0.5,
  mouseY: 0.5,
  mouseDown: false,
  zoomParams: [0.5, 0.5, 0.5, 0.5],
  slotParams: [
    [0.5, 0.5, 0.5, 0.5],
    [0.5, 0.5, 0.5, 0.5],
    [0.5, 0.5, 0.5, 0.5]
  ],
  ripples: [],
  inputSource: 1,
  pendingInputSource: null,
  loadErrorCount: 0,
  lastLoadError: null,
  initStartTime: 0,
  initEndTime: 0,
  colorFormat: 0,
  /** Slot indexes whose last setSlotShader the module did not accept. */
  droppedSlots: /* @__PURE__ */ new Set(),
  /** MAX_SHADER_SLOTS compiled into the loaded artifact; null = older binary without the export. */
  maxShaderSlots: null
};
function isCppRendererReady() {
  const mod = wasmRef.module;
  if (!state.initialized || !mod) return false;
  try {
    return Number(mod.ccall("isRendererInitialized", "number", [], [])) === 1;
  } catch {
    return false;
  }
}
function readCanvasCopySrc() {
  const mod = wasmRef.module;
  if (!mod || typeof mod._getCanvasCopySrcSupported !== "function") return null;
  if (!isCppRendererReady()) return null;
  return mod._getCanvasCopySrcSupported() === 1;
}
const INIT_STAGE_NAMES = {
  0: "None",
  1: "Instance",
  2: "Adapter",
  3: "Device",
  4: "Surface",
  5: "Resources",
  6: "BindGroups",
  7: "Pipeline",
  8: "Ready"
};
export {
  INIT_STAGE_NAMES,
  isCppRendererReady,
  readCanvasCopySrc,
  state,
  utf8ByteLength,
  wasmRef
};
