/**
 * UniformBuffer.ts
 *
 * Type-safe uniform buffer management for WebGPU compute shaders.
 * Handles all uniform data writes with proper alignment and offset management.
 */

// ── Constants ───────────────────────────────────────────────────────────────

const MAX_RIPPLES = 50;
const UNIFORM_FLOATS = 12 + MAX_RIPPLES * 4; // 212 floats = 848 bytes

/** Byte offsets for each uniform field (align 16) */
export const UNIFORM_OFFSETS = {
  // config: vec4<f32> @ offset 0
  config_time: 0,
  config_rippleCount: 4,
  config_resW: 8,
  config_resH: 12,

  // zoom_config: vec4<f32> @ offset 16
  zoom_time: 16,
  zoom_mouseX: 20,
  zoom_mouseY: 24,
  zoom_mouseDown: 28,

  // zoom_params: vec4<f32> @ offset 32
  params_x: 32,
  params_y: 36,
  params_z: 40,
  params_w: 44,

  // ripples: array<vec4<f32>, 50> @ offset 48
  ripples_start: 48,
  ripple_stride: 16, // each ripple is vec4<f32>
} as const;

/** Ripple data structure */
export interface Ripple {
  x: number;
  y: number;
  startTime: number;
}

/** Type-safe view over the uniform Float32Array */
export interface UniformBufferView {
  /** Sets the config vec4: [time, rippleCount, resW, resH] */
  setConfig(time: number, rippleCount: number, resW: number, resH: number): void;

  /** Sets the zoom_config vec4: [time, mouseX, mouseY, mouseDown] */
  setZoomConfig(time: number, mouseX: number, mouseY: number, mouseDown: number): void;

  /** Sets the zoom_params vec4: [p1, p2, p3, p4] */
  setZoomParams(p1: number, p2: number, p3: number, p4: number): void;

  /** Sets a ripple at the given index */
  setRipple(index: number, x: number, y: number, startTime: number): void;

  /** Clears a ripple slot */
  clearRipple(index: number): void;

  /** Gets the underlying Float32Array for GPU upload */
  readonly data: Float32Array;
}

/** Creates a type-safe view over a uniform buffer */
export function createUniformBufferView(): UniformBufferView {
  const data = new Float32Array(UNIFORM_FLOATS);

  return {
    setConfig(time, rippleCount, resW, resH) {
      const o = UNIFORM_OFFSETS.config_time / 4;
      data[o] = time;
      data[o + 1] = rippleCount;
      data[o + 2] = resW;
      data[o + 3] = resH;
    },

    setZoomConfig(time, mouseX, mouseY, mouseDown) {
      const o = UNIFORM_OFFSETS.zoom_time / 4;
      data[o] = time;
      data[o + 1] = mouseX;
      data[o + 2] = mouseY;
      data[o + 3] = mouseDown;
    },

    setZoomParams(p1, p2, p3, p4) {
      const o = UNIFORM_OFFSETS.params_x / 4;
      data[o] = p1;
      data[o + 1] = p2;
      data[o + 2] = p3;
      data[o + 3] = p4;
    },

    setRipple(index, x, y, startTime) {
      if (index < 0 || index >= MAX_RIPPLES) return;
      const o = (UNIFORM_OFFSETS.ripples_start + index * UNIFORM_OFFSETS.ripple_stride) / 4;
      data[o] = x;
      data[o + 1] = y;
      data[o + 2] = startTime;
      data[o + 3] = 0; // padding
    },

    clearRipple(index) {
      if (index < 0 || index >= MAX_RIPPLES) return;
      const o = (UNIFORM_OFFSETS.ripples_start + index * UNIFORM_OFFSETS.ripple_stride) / 4;
      data[o] = data[o + 1] = data[o + 2] = data[o + 3] = 0;
    },

    get data() {
      return data;
    },
  };
}

export { UNIFORM_FLOATS, MAX_RIPPLES };
