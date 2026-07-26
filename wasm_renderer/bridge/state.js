// Shared renderer state and canvas references (concatenated into wasm_bridge.js).

/** The WASM module instance */
let wasmModule = null;
/** @type {HTMLCanvasElement|null} */
let canvas = null;

/** Counter used to assign unique CSS IDs to canvas elements that lack one. */
let _canvasIdCounter = 0;

/** Renderer state */
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
  /** Per-slot zoom params cache for partial updateSlotParams merges */
  slotParams: [
    [0.5, 0.5, 0.5, 0.5],
    [0.5, 0.5, 0.5, 0.5],
    [0.5, 0.5, 0.5, 0.5],
  ],
  ripples: [],
  inputSource: 1,
  pendingInputSource: null,
  // Diagnostic tracking
  loadErrorCount: 0,
  lastLoadError: null,
  initStartTime: 0,
  initEndTime: 0,
  /** 0=rgba32float, 1=rgba16float — see docs/FORMAT_TIERS.md */
  colorFormat: 0,
};

/** Maps WebGPURenderer::InitStage (C++) to a readable name. */
const INIT_STAGE_NAMES = {
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
