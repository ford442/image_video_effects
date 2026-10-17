import * as cpp from './_generated.js';
import { isBusy, runWhenIdle } from './call.js';
import { state, wasmRef } from './state.js';

export type GPUTimings = {
  parallelTime: number;
  chainedTime: number;
  totalTime: number;
  available: boolean;
  timingSource: 'gpu-timestamp' | 'wall-clock' | 'unavailable';
};

export type SlotZoomParamsUpdate = {
  zoomParam1?: number;
  zoomParam2?: number;
  zoomParam3?: number;
  zoomParam4?: number;
};

const SOURCE_MAP: Record<string, number> = {
  none: 0,
  image: 1,
  video: 2,
  webcam: 3,
  generative: 4,
  live: 5,
};

export type UniformsUpdate = {
  time?: number;
  mouseX?: number;
  mouseY?: number;
  mouseDown?: boolean;
  zoom_params?: [number, number, number, number];
};

export function setSlotParams(slotIndex: number, p1: number, p2: number, p3: number, p4: number): void {
  if (!state.initialized || !wasmRef.module) return;
  if (slotIndex >= 0) {
    state.slotParams[slotIndex] = [p1, p2, p3, p4];
  }
  // The legacy single-shader path (no enabled slots) reads the global
  // zoom_params, which the per-frame updateUniforms pushes from state.
  if (slotIndex === 0) {
    state.zoomParams = [p1, p2, p3, p4];
  }
  cpp.setSlotParams(wasmRef.module, slotIndex, p1, p2, p3, p4);
}

export function updateSlotParams(slotIndex: number, params: SlotZoomParamsUpdate & { p1?: number; p2?: number; p3?: number; p4?: number }): void {
  if (!params || typeof params !== 'object') return;
  const current = state.slotParams[slotIndex] ?? [0.5, 0.5, 0.5, 0.5];
  const p1 = params.p1 ?? params.zoomParam1 ?? current[0];
  const p2 = params.p2 ?? params.zoomParam2 ?? current[1];
  const p3 = params.p3 ?? params.zoomParam3 ?? current[2];
  const p4 = params.p4 ?? params.zoomParam4 ?? current[3];
  setSlotParams(slotIndex, p1, p2, p3, p4);
}

function applyUniformState(
  time: number,
  mouseX: number,
  mouseY: number,
  mouseDown: boolean,
  zoomP1: number,
  zoomP2: number,
  zoomP3: number,
  zoomP4: number,
): boolean {
  if (!state.initialized || !wasmRef.module) {
    return false;
  }

  state.time = time;
  state.mouseX = mouseX;
  state.mouseY = mouseY;
  state.mouseDown = mouseDown;
  state.zoomParams = [zoomP1, zoomP2, zoomP3, zoomP4];

  const mod = wasmRef.module;
  cpp.setTime(mod, time);
  cpp.updateMousePos(mod, mouseX, mouseY);
  cpp.setMouseDown(mod, mouseDown ? 1 : 0);
  cpp.setZoomParams(mod, zoomP1, zoomP2, zoomP3, zoomP4);
  // Render() is skipped while a resize / format change / shader compile is
  // suspended: size-dependent textures may be null until it returns.
  cpp.updateUniforms(mod);
  return true;
}

export function updateUniforms(
  timeOrUniforms: number | UniformsUpdate,
  mouseX = 0.5,
  mouseY = 0.5,
  mouseDown = false,
  zoomP1 = 0.5,
  zoomP2 = 0.5,
  zoomP3 = 0.5,
  zoomP4 = 0.5,
): boolean {
  if (typeof timeOrUniforms === 'object' && timeOrUniforms !== null) {
    const u = timeOrUniforms;
    const zp = u.zoom_params ?? state.zoomParams;
    return applyUniformState(
      u.time ?? state.time,
      u.mouseX ?? state.mouseX,
      u.mouseY ?? state.mouseY,
      u.mouseDown ?? state.mouseDown,
      zp[0],
      zp[1],
      zp[2],
      zp[3],
    );
  }
  return applyUniformState(timeOrUniforms, mouseX, mouseY, mouseDown, zoomP1, zoomP2, zoomP3, zoomP4);
}

export function updateMousePos(x: number, y: number, down?: boolean): void {
  if (!state.initialized || !wasmRef.module) return;
  state.mouseX = x;
  state.mouseY = y;
  cpp.updateMousePos(wasmRef.module, x, y);
  if (down !== undefined) {
    state.mouseDown = down;
    cpp.setMouseDown(wasmRef.module, down ? 1 : 0);
  }
}

export function updateAudioData(
  bassOrData: number | Uint8Array | Float32Array | number[],
  mid?: number,
  treble?: number,
): void {
  if (!state.initialized || !wasmRef.module) return;
  if (typeof bassOrData === 'number') {
    cpp.updateAudioData(wasmRef.module, bassOrData, mid ?? 0, treble ?? 0);
    return;
  }
  cpp.updateAudioData(
    wasmRef.module,
    Number(bassOrData[0] ?? 0),
    Number(bassOrData[1] ?? 0),
    Number(bassOrData[2] ?? 0),
  );
}

export function updateAudioFrequencyBins(
  binsOrBass: Float32Array | number,
  mid?: number,
  treble?: number,
  energy?: number,
): void {
  if (!state.initialized || !wasmRef.module) return;
  if (typeof binsOrBass === 'number') {
    updateAudioFrequencyBins(new Float32Array([binsOrBass, mid ?? 0, treble ?? 0, energy ?? 0]));
    return;
  }
  const mod = wasmRef.module;
  const count = binsOrBass.length;
  const ptr = mod._malloc(count * 4);
  try {
    mod.HEAPF32.set(binsOrBass, ptr / 4);
    cpp.updateAudioFrequencyBins(mod, ptr, count);
  } finally {
    mod._free(ptr);
  }
}

export function updateDepthMap(depthData: Float32Array | Uint8Array, width = 256, height = 256): void {
  const mod = wasmRef.module;
  if (!state.initialized || !mod) return;
  const floats = depthData instanceof Float32Array
    ? depthData
    : new Float32Array(depthData.buffer, depthData.byteOffset, depthData.byteLength / 4);
  const upload = (data: Float32Array) => {
    if (wasmRef.module !== mod) return;
    const ptr = mod._malloc(data.byteLength);
    try {
      mod.HEAPF32.set(data, ptr / 4);
      cpp.updateDepthMap(mod, ptr, width, height);
    } finally {
      mod._free(ptr);
    }
  };
  // A depth map is not re-sent every frame: run it after a suspended resize
  // instead of letting the `skip` export drop it. The copy outlives the caller.
  if (isBusy(mod)) void runWhenIdle(mod, () => upload(floats.slice()));
  else upload(floats);
}

export function setInputSource(
  source: number | 'none' | 'image' | 'video' | 'webcam' | 'generative' | 'live' | string,
): void {
  const sourceInt = typeof source === 'string'
    ? (SOURCE_MAP[source.toLowerCase()] ?? 0)
    : (typeof source === 'number' ? source : 0);

  if (!state.initialized || !wasmRef.module) {
    state.pendingInputSource = source;
    state.inputSource = sourceInt;
    return;
  }
  state.inputSource = sourceInt;
  cpp.setInputSource(wasmRef.module, sourceInt);
}

export function addRipple(x: number, y: number, _amplitude = 1.0, _wavelength = 0.05): void {
  if (!state.initialized || !wasmRef.module) return;
  cpp.addRipple(wasmRef.module, x, y);
}

export function clearRipples(): void {
  if (!state.initialized || !wasmRef.module) return;
  cpp.clearRipples(wasmRef.module);
}

export function getFPS(): number {
  if (!state.initialized || !wasmRef.module) return 0;
  return cpp.getFPS(wasmRef.module);
}

export function getSupportsDeepWorkgroup(): boolean {
  if (!state.initialized || !wasmRef.module) return true;
  return cpp.getSupportsDeepWorkgroup(wasmRef.module) !== 0;
}

export function getColorFormat(): 0 | 1 {
  if (state.initialized && wasmRef.module) {
    state.colorFormat = cpp.getColorFormat(wasmRef.module) === 1 ? 1 : 0;
  }
  return state.colorFormat;
}

/**
 * Async export (RecreateTextures can suspend). Resolves once C++ has switched,
 * or fell back to rgba32float when the rgba16float probe failed; state then
 * holds what C++ actually uses.
 */
export async function setColorFormat(format: 0 | 1 | number): Promise<void> {
  state.colorFormat = format === 1 ? 1 : 0;
  const mod = wasmRef.module;
  if (!state.initialized || !mod) return;
  try {
    await cpp.setColorFormat(mod, state.colorFormat);
  } catch (err) {
    console.error('[WASM] setColorFormat failed:', err);
  }
  if (wasmRef.module === mod) state.colorFormat = cpp.getColorFormat(mod) === 1 ? 1 : 0;
}

function unavailableGPUTimings(): GPUTimings {
  return {
    parallelTime: 0,
    chainedTime: 0,
    totalTime: 0,
    available: false,
    timingSource: 'unavailable',
  };
}

export function getGPUTimings(): GPUTimings {
  if (!state.initialized || !wasmRef.module) return unavailableGPUTimings();
  const m = wasmRef.module;
  if (typeof m._malloc !== 'function' || typeof m.getValue !== 'function' || typeof m.ccall !== 'function') {
    return unavailableGPUTimings();
  }

  const ptr = m._malloc(16);
  if (!ptr) return unavailableGPUTimings();

  try {
    cpp.getGPUTimings(m, ptr, ptr + 4, ptr + 8, ptr + 12);
    const parallelTime = m.getValue(ptr, 'float');
    const chainedTime = m.getValue(ptr + 4, 'float');
    const totalTime = m.getValue(ptr + 8, 'float');
    const available = m.getValue(ptr + 12, 'i32') !== 0;
    return {
      parallelTime,
      chainedTime,
      totalTime,
      available,
      timingSource: available ? 'gpu-timestamp' : 'wall-clock',
    };
  } catch {
    return unavailableGPUTimings();
  } finally {
    if (typeof m._free === 'function') m._free(ptr);
  }
}

export function getAdapterSummary(): string {
  if (!wasmRef.module || typeof wasmRef.module.ccall !== 'function') return '';
  return cpp.getAdapterSummary(wasmRef.module);
}

export function getLastInitErrorStage(): number {
  if (!wasmRef.module || typeof wasmRef.module.ccall !== 'function') return 0;
  return cpp.getLastInitErrorStage(wasmRef.module);
}

export function getLastInitErrorMessage(): string {
  if (!wasmRef.module || typeof wasmRef.module.ccall !== 'function') return '';
  return cpp.getLastInitErrorMessage(wasmRef.module);
}
