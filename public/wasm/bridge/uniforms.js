// src/wasm/bridge/uniforms.js
// Uniforms, slot params, input source, audio, depth, and render triggers.

import { state, wasmRef } from './state.js';

const SOURCE_MAP = {
  none: 0,
  image: 1,
  video: 2,
  webcam: 3,
  generative: 4,
  live: 5,
};

/**
 * Set the four zoom parameters for a specific slot.
 * @param {number} slotIndex - Slot index (0, 1, or 2)
 * @param {number} p1
 * @param {number} p2
 * @param {number} p3
 * @param {number} p4
 */
export function setSlotParams(slotIndex, p1, p2, p3, p4) {
  if (!state.initialized || !wasmRef.module) return;
  if (slotIndex >= 0 && slotIndex < state.slotParams.length) {
    state.slotParams[slotIndex] = [p1, p2, p3, p4];
  }
  wasmRef.module.ccall(
    'setSlotParams',
    null,
    ['number', 'number', 'number', 'number', 'number'],
    [slotIndex, p1, p2, p3, p4]
  );
}

/**
 * Partial update for slot parameters — merges non-undefined entries into slotParams cache.
 * @param {number} slotIndex
 * @param {Partial<Record<'p1'|'p2'|'p3'|'p4', number>>} params
 */
export function updateSlotParams(slotIndex, params) {
  if (!params || typeof params !== 'object') return;
  const current = state.slotParams[slotIndex] ?? [0.5, 0.5, 0.5, 0.5];
  const p1 = params.p1 ?? current[0];
  const p2 = params.p2 ?? current[1];
  const p3 = params.p3 ?? current[2];
  const p4 = params.p4 ?? current[3];
  setSlotParams(slotIndex, p1, p2, p3, p4);
}

/**
 * Update global uniforms and trigger a multi-slot render.
 * @param {number} time - Animation time in seconds
 * @param {number} [mouseX=0.5] - Mouse X (0..1)
 * @param {number} [mouseY=0.5] - Mouse Y (0..1)
 * @param {boolean} [mouseDown=false] - Mouse button pressed state
 * @param {number} [zoomP1=0.5] - Backward-compatible global zoom param 1
 * @param {number} [zoomP2=0.5] - Backward-compatible global zoom param 2
 * @param {number} [zoomP3=0.5] - Backward-compatible global zoom param 3
 * @param {number} [zoomP4=0.5] - Backward-compatible global zoom param 4
 * @returns {boolean} Success status
 */
export function updateUniforms(
  time,
  mouseX    = 0.5,
  mouseY    = 0.5,
  mouseDown = false,
  zoomP1    = 0.5,
  zoomP2    = 0.5,
  zoomP3    = 0.5,
  zoomP4    = 0.5
) {
  if (!state.initialized || !wasmRef.module) {
    return false;
  }

  state.time = time;
  state.mouseX = mouseX;
  state.mouseY = mouseY;
  state.mouseDown = mouseDown;
  state.zoomParams = [zoomP1, zoomP2, zoomP3, zoomP4];

  const result = wasmRef.module.ccall(
    'updateUniforms',
    'number',
    ['number', 'number', 'number', 'number', 'number', 'number', 'number', 'number'],
    [time, mouseX, mouseY, mouseDown ? 1 : 0, zoomP1, zoomP2, zoomP3, zoomP4]
  );

  return Boolean(result);
}

/**
 * Update mouse position
 * @param {number} x - Normalized X coordinate (0..1)
 * @param {number} y - Normalized Y coordinate (0..1)
 * @param {boolean} down - Mouse button state
 */
export function updateMousePos(x, y, down = false) {
  if (!state.initialized || !wasmRef.module) return;
  state.mouseX = x;
  state.mouseY = y;
  state.mouseDown = down;
  wasmRef.module.ccall(
    'updateMousePos',
    null,
    ['number', 'number', 'number'],
    [x, y, down ? 1 : 0]
  );
}

/**
 * Upload audio frequency data to C++ audio texture
 * @param {Uint8Array|Float32Array|number[]} audioData - Audio samples (256 bytes)
 */
export function updateAudioData(audioData) {
  if (!state.initialized || !wasmRef.module) return;

  const len = 256;
  const ptr = wasmRef.module._malloc(len);
  const heap = wasmRef.module.HEAPU8;

  if (audioData instanceof Uint8Array) {
    heap.set(audioData.subarray(0, len), ptr);
  } else if (Array.isArray(audioData) || audioData instanceof Float32Array) {
    for (let i = 0; i < len; i++) {
      const val = audioData[i] ?? 0;
      heap[ptr + i] = typeof val === 'number'
        ? Math.min(255, Math.max(0, Math.floor(val <= 1.0 ? val * 255 : val)))
        : 0;
    }
  }

  wasmRef.module.ccall('updateAudioData', null, ['number', 'number'], [ptr, len]);
  wasmRef.module._free(ptr);
}

/**
 * Upload 4-bin audio energy (bass, mid, treble, energy).
 * @param {number} bass
 * @param {number} mid
 * @param {number} treble
 * @param {number} energy
 */
export function updateAudioFrequencyBins(bass, mid, treble, energy) {
  if (!state.initialized || !wasmRef.module) return;
  wasmRef.module.ccall(
    'updateAudioFrequencyBins',
    null,
    ['number', 'number', 'number', 'number'],
    [bass, mid, treble, energy]
  );
}

/**
 * Upload depth map texture data to C++ (256x256 R8 or R32F).
 * @param {Uint8Array|Float32Array} depthData - Depth values
 * @param {number} width - Depth map width (default 256)
 * @param {number} height - Depth map height (default 256)
 */
export function updateDepthMap(depthData, width = 256, height = 256) {
  if (!state.initialized || !wasmRef.module) return;

  const bytes = depthData.byteLength;
  const ptr = wasmRef.module._malloc(bytes);
  const heap = wasmRef.module.HEAPU8;
  heap.set(new Uint8Array(depthData.buffer, depthData.byteOffset, bytes), ptr);

  wasmRef.module.ccall(
    'updateDepthMap',
    null,
    ['number', 'number', 'number', 'number'],
    [ptr, bytes, width, height]
  );
  wasmRef.module._free(ptr);
}

/**
 * Set the primary input texture mode for slot 0/1 binding.
 * Accepts string identifiers ('none', 'image', 'video', 'webcam', 'generative', 'live') or integer codes.
 * @param {number|string} source
 */
export function setInputSource(source) {
  const sourceInt = typeof source === 'string'
    ? (SOURCE_MAP[source.toLowerCase()] ?? 0)
    : (typeof source === 'number' ? source : 0);

  if (!state.initialized || !wasmRef.module) {
    state.pendingInputSource = source;
    state.inputSource = sourceInt;
    return;
  }
  state.inputSource = sourceInt;
  wasmRef.module.ccall('setInputSource', null, ['number'], [sourceInt]);
}

/**
 * Add an interactive ripple to the GPU ripple buffer
 * @param {number} x - Normalized X (0..1)
 * @param {number} y - Normalized Y (0..1)
 * @param {number} [amplitude=1.0] - Initial wave amplitude
 * @param {number} [wavelength=0.05] - Wave width
 */
export function addRipple(x, y, amplitude = 1.0, wavelength = 0.05) {
  if (!state.initialized || !wasmRef.module) return;
  wasmRef.module.ccall(
    'addRipple',
    null,
    ['number', 'number', 'number', 'number'],
    [x, y, amplitude, wavelength]
  );
}

/**
 * Clear all active ripples
 */
export function clearRipples() {
  if (!state.initialized || !wasmRef.module) return;
  wasmRef.module.ccall('clearRipples', null, [], []);
}

/**
 * Get current frame rate measured by C++ renderer
 * @returns {number} Frames per second
 */
export function getFPS() {
  if (!state.initialized || !wasmRef.module) return 0;
  return wasmRef.module.ccall('getFPS', 'number', [], []) ?? 0;
}

/**
 * Query whether C++ device supports @workgroup_size(16,16) or deep compute caps.
 * @returns {boolean}
 */
export function getSupportsDeepWorkgroup() {
  if (!state.initialized || !wasmRef.module) return true;
  return Boolean(
    wasmRef.module.ccall('getSupportsDeepWorkgroup', 'number', [], [])
  );
}

/**
 * Get configured WASM color format tier (0=rgba32float, 1=rgba16float).
 * @returns {number}
 */
export function getColorFormat() {
  return state.colorFormat;
}

/**
 * Set WASM color format tier (0=rgba32float, 1=rgba16float).
 * @param {number} format
 */
export function setColorFormat(format) {
  state.colorFormat = format === 1 ? 1 : 0;
}

/**
 * Get GPU pass timing measurements from C++ timing query set.
 * Returns empty object if timestamps are unsupported on the adapter.
 * @returns {{ computeMs?: number, renderMs?: number, totalMs?: number }}
 */
export function getGPUTimings() {
  if (!state.initialized || !wasmRef.module) return {};
  try {
    const raw = wasmRef.module.ccall('getGPUTimings', 'string', [], []);
    if (!raw) return {};
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

/**
 * Query adapter summary string from C++ (device.cpp).
 * @returns {string}
 */
export function getAdapterSummary() {
  if (!wasmRef.module || typeof wasmRef.module.ccall !== 'function') return '';
  return wasmRef.module.ccall('getAdapterSummary', 'string', [], []) ?? '';
}

/**
 * Query last init error stage code (0..8) from C++.
 * @returns {number}
 */
export function getLastInitErrorStage() {
  if (!wasmRef.module || typeof wasmRef.module.ccall !== 'function') return 0;
  return wasmRef.module.ccall('getLastInitErrorStage', 'number', [], []) ?? 0;
}

/**
 * Query last init error message string from C++.
 * @returns {string}
 */
export function getLastInitErrorMessage() {
  if (!wasmRef.module || typeof wasmRef.module.ccall !== 'function') return '';
  return wasmRef.module.ccall('getLastInitErrorMessage', 'string', [], []) ?? '';
}
