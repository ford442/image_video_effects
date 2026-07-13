// Uniforms, slot params, input source, audio, depth, and render triggers.

/**
 * Set the four zoom parameters for a specific slot.
 * @param {number} slotIndex - Slot index (0, 1, or 2)
 * @param {number} p1
 * @param {number} p2
 * @param {number} p3
 * @param {number} p4
 */
export function setSlotParams(slotIndex, p1, p2, p3, p4) {
  if (!state.initialized || !wasmModule) return;
  if (slotIndex >= 0 && slotIndex < state.slotParams.length) {
    state.slotParams[slotIndex] = [p1, p2, p3, p4];
  }
  wasmModule.ccall(
    'setSlotParams',
    null,
    ['number', 'number', 'number', 'number', 'number'],
    [slotIndex, p1, p2, p3, p4]
  );
}

/**
 * Merge partial zoom-param updates (aggregate form from UI sliders).
 * Only defined keys are applied; others retain their current slot values.
 */
export function updateSlotParams(slotIndex, params = {}) {
  if (slotIndex < 0 || slotIndex >= state.slotParams.length) return;
  const cur = state.slotParams[slotIndex];
  const p1 = params.zoomParam1 ?? cur[0];
  const p2 = params.zoomParam2 ?? cur[1];
  const p3 = params.zoomParam3 ?? cur[2];
  const p4 = params.zoomParam4 ?? cur[3];
  setSlotParams(slotIndex, p1, p2, p3, p4);
}

/**
 * Set the execution mode for a slot.
 * @param {number} slotIndex - Slot index (0, 1, or 2)
 * @param {number|string} mode - 0 or 'chained' for chained mode; 1 or 'parallel' for parallel mode
 */
export function setSlotMode(slotIndex, mode) {
  if (!state.initialized || !wasmModule) return;
  const modeInt = (mode === 'parallel' || mode === 1) ? 1 : 0;
  wasmModule.ccall('setSlotMode', null, ['number', 'number'], [slotIndex, modeInt]);
}

/**
 * Update uniform values and trigger a render frame.
 * @param {Object} uniforms - Uniform values
 */
export function updateUniforms(uniforms = {}) {
  if (!state.initialized || !wasmModule) return;

  if (uniforms.time !== undefined) state.time = uniforms.time;
  if (uniforms.mouseX !== undefined) state.mouseX = uniforms.mouseX;
  if (uniforms.mouseY !== undefined) state.mouseY = uniforms.mouseY;
  if (uniforms.mouseDown !== undefined) state.mouseDown = uniforms.mouseDown;
  if (uniforms.zoom_params) state.zoomParams = uniforms.zoom_params;

  // Push current time to C++ so time-based animations advance.
  wasmModule.ccall('setTime', null, ['number'], [state.time]);

  // Push global zoom params (per-slot params must be set via setSlotParams).
  wasmModule.ccall(
    'setZoomParams',
    null,
    ['number', 'number', 'number', 'number'],
    state.zoomParams
  );

  // Push mouse state.
  wasmModule.ccall('updateMousePos', null, ['number', 'number'], [state.mouseX, state.mouseY]);
  wasmModule.ccall('setMouseDown', null, ['number'], [state.mouseDown ? 1 : 0]);

  // Trigger one render frame.
  wasmModule.ccall('updateUniforms', null, [], []);
}

/**
 * Update mouse position (normalized 0-1 coordinates).
 * @param {number} x
 * @param {number} y
 */
export function updateMousePos(x, y) {
  if (!state.initialized || !wasmModule) return;
  state.mouseX = x;
  state.mouseY = y;
  wasmModule.ccall('updateMousePos', null, ['number', 'number'], [x, y]);
}

/**
 * Update audio frequency bands (0-1 normalized).
 * @param {number} bass
 * @param {number} mid
 * @param {number} treble
 */
export function updateAudioData(bass, mid, treble) {
  if (!state.initialized || !wasmModule) return;
  wasmModule.ccall('updateAudioData', null, ['number', 'number', 'number'], [bass, mid, treble]);
}

/** Max FFT bins written to extraBuffer[5..132] (matches TS WebGPURenderer). */
const AUDIO_FFT_BINS = 128;

/**
 * Upload normalised FFT magnitude bins for audio-reactive shaders.
 * @param {Float32Array} bins - Values in [0, 1], up to 128 bins
 */
export function updateAudioFrequencyBins(bins) {
  if (!state.initialized || !wasmModule || !bins) return;
  const count = Math.min(bins.length, AUDIO_FFT_BINS);
  const byteLen = count * 4;
  const ptr = wasmModule._malloc(byteLen);
  wasmModule.HEAPF32.set(bins.subarray(0, count), ptr >> 2);
  try {
    wasmModule.ccall('updateAudioFrequencyBins', null, ['number', 'number'], [ptr, count]);
  } finally {
    wasmModule._free(ptr);
  }
}

export function getSupportsDeepWorkgroup() {
  if (!state.initialized || !wasmModule) return false;
  return wasmModule.ccall('getSupportsDeepWorkgroup', 'number', [], []) === 1;
}

export function getSlotState(slotIndex) {
  if (!state.initialized || !wasmModule) {
    return { shaderId: null, enabled: false, mode: 'chained' };
  }
  const id = wasmModule.ccall('getSlotShaderId', 'string', ['number'], [slotIndex]) || '';
  const enabled = wasmModule.ccall('getSlotEnabled', 'number', ['number'], [slotIndex]) === 1;
  const modeInt = wasmModule.ccall('getSlotMode', 'number', ['number'], [slotIndex]);
  return {
    shaderId: id.length > 0 ? id : null,
    enabled,
    mode: modeInt === 1 ? 'parallel' : 'chained',
  };
}

/** Render timings from the last frame (GPU timestamp queries when supported). */
export function getGPUTimings() {
  if (!state.initialized || !wasmModule) {
    return { parallelTime: 0, chainedTime: 0, totalTime: 0, available: false, timingSource: 'unavailable' };
  }
  const ptr = wasmModule._malloc(16);
  try {
    wasmModule.ccall('getGPUTimings', null, ['number', 'number', 'number', 'number'], [
      ptr, ptr + 4, ptr + 8, ptr + 12,
    ]);
    const parallelTime = wasmModule.getValue(ptr, 'float');
    const chainedTime = wasmModule.getValue(ptr + 4, 'float');
    const totalTime = wasmModule.getValue(ptr + 8, 'float');
    const available = wasmModule.getValue(ptr + 12, 'i32') === 1;
    const timingSource = available
      ? 'gpu-timestamp'
      : (totalTime > 0 || parallelTime > 0 || chainedTime > 0 ? 'wall-clock' : 'unavailable');
    return { parallelTime, chainedTime, totalTime, available, timingSource };
  } finally {
    wasmModule._free(ptr);
  }
}

/**
 * Upload a depth map (Float32Array, one float per pixel, row-major) from the
 * AI depth estimation model.
 * @param {Float32Array} float32Data - Depth values (0=far, 1=near)
 * @param {number} width
 * @param {number} height
 */
export function updateDepthMap(float32Data, width, height) {
  if (!state.initialized || !wasmModule) return;

  const byteLen = float32Data.length * 4;
  const ptr = wasmModule._malloc(byteLen);
  wasmModule.HEAPF32.set(float32Data, ptr >> 2);
  try {
    wasmModule.ccall(
      'updateDepthMap',
      null,
      ['number', 'number', 'number'],
      [ptr, width, height]
    );
  } finally {
    wasmModule._free(ptr);
  }
}

/**
 * Set the active input source.
 * @param {number|string} source
 *   0 or 'none'       - no input (black placeholder)
 *   1 or 'image'      - static image (uploadImageData / loadImage)
 *   2 or 'video'      - video file or HLS live stream
 *   3 or 'webcam'     - webcam capture (same upload path as video)
 *   4 or 'generative' - procedural, readTexture cleared to black
 *   5 or 'live'       - HLS live stream (same frame upload path as video)
 */
export function setInputSource(source) {
  if (!state.initialized || !wasmModule) {
    if (typeof source === 'string') state.pendingInputSource = source;
    return;
  }
  const sourceMap = { none: 0, image: 1, video: 2, webcam: 3, generative: 4, live: 5 };
  const sourceInt = typeof source === 'string'
    ? (sourceMap[source] ?? 0)
    : source;
  state.inputSource = sourceInt;
  wasmModule.ccall('setInputSource', null, ['number'], [sourceInt]);
}

/**
 * Add a ripple effect at the given position
 * @param {number} x - Normalized X position (0-1)
 * @param {number} y - Normalized Y position (0-1)
 */
export function addRipple(x, y) {
  if (!state.initialized || !wasmModule) return;

  wasmModule.ccall('addRipple', null, ['number', 'number'], [x, y]);
  state.ripples.push({ x, y, time: state.time });
}

/**
 * Clear all ripples
 */
export function clearRipples() {
  if (!state.initialized || !wasmModule) return;

  wasmModule.ccall('clearRipples', null, [], []);
  state.ripples = [];
}

/**
 * Get current FPS
 * @returns {number} Frames per second
 */
export function getFPS() {
  if (!state.initialized || !wasmModule) return 0;

  return wasmModule.ccall('getFPS', 'number', [], []);
}

/**
 * Resize the rendering canvas and recreate all size-dependent GPU resources.
 * Call this whenever the display canvas dimensions change.
 * @param {number} newWidth  - New canvas width in pixels
 * @param {number} newHeight - New canvas height in pixels
 */
export function resizeCanvas(newWidth, newHeight) {
  if (!state.initialized || !wasmModule) return;
  if (newWidth <= 0 || newHeight <= 0) return;
  state.canvasWidth  = newWidth;
  state.canvasHeight = newHeight;
  wasmModule.ccall('resizeCanvas', null, ['number', 'number'], [newWidth, newHeight]);
}
