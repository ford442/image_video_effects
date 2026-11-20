/**
 * offlineRender.ts — types and limits of the offline (stepped-clock) render API (#1401).
 *
 * An offline job takes the TS WebGPU renderer off its vsync-paced loop and renders
 * exactly the frames it is asked for:
 *
 *   beginOfflineRender({ width, height, fps })   stop the rAF loop, step a fresh clock,
 *                                                 resize the render target, reset sim state
 *   renderFrameAt(timeSec, input) → VideoFrame    one frame at exactly `timeSec`, from `input`
 *   endOfflineRender()                            restore the live size, clock and loop
 *
 * Main thread (`?renderer=main`) calls WebGPURenderer directly; the render worker exposes the
 * same three calls as RPCs (worker/protocol.ts). Nothing here imports GPU code, so the page
 * bundle can use the types and validation freely.
 */

/** What the offline target should look like. */
export interface OfflineRenderOptions {
  /** Output (canvas) size in pixels; the encoder receives frames of exactly this size. */
  width: number;
  height: number;
  /** Frames per second of the stepped clock (time of frame n is n / fps). */
  fps: number;
  /**
   * Working-texture scale (0.25–1, default 1). The working size is also bounded by the
   * renderer's working-size cap, as live; the present pass scales up to `width × height`.
   */
  resolutionScale?: number;
}

export interface OfflineRenderInfo {
  /** Canvas (output) size applied. */
  width: number;
  height: number;
  /** Working size the compute passes run at. */
  scaledW: number;
  scaledH: number;
  fps: number;
  /** The device's limit: the largest output dimension an offline job can ask for. */
  maxTextureDimension2D: number;
}

/**
 * The complete input of one offline frame. Unlike the live `FrameInput` (deltas), absent
 * fields take neutral defaults, so a frame never inherits live input: mouse centred and up,
 * silent audio, zero FFT bins. Slot params not listed keep the value the job last set.
 */
export interface FrameInputSnapshot {
  /** Canvas-normalized mouse (0..1, y down). Default [0.5, 0.5]. */
  mouse?: [number, number];
  mouseDown?: boolean;
  /** bass / mid / treble (0..1). Default silence. */
  audio?: [number, number, number];
  /** 128 FFT bins (0..1). Default zeros. */
  bins?: Float32Array;
  /** [slotIndex, p1, p2, p3, p4] per slot to set before the frame. */
  slotParams?: Array<[number, number, number, number, number]>;
  /** The frame's video input (a seek of the source to this frame's time); transferred. */
  videoFrame?: VideoFrame;
  /** Frame duration stamped on the returned VideoFrame (µs); default 1e6 / fps. */
  durationUs?: number;
}

/** Smallest output edge an offline job accepts (the workgroup tile is 8×8). */
export const OFFLINE_MIN_DIMENSION = 16;
export const OFFLINE_MAX_FPS = 240;

/** Throws a RangeError naming the first bad field; returns the normalized options. */
export function validateOfflineRenderOptions(
  options: OfflineRenderOptions,
  maxTextureDimension2D: number,
): Required<OfflineRenderOptions> {
  const { width, height, fps } = options;
  const max = Math.max(OFFLINE_MIN_DIMENSION, Math.floor(maxTextureDimension2D) || 0);
  for (const [name, v] of [['width', width], ['height', height]] as const) {
    if (!Number.isInteger(v) || v < OFFLINE_MIN_DIMENSION || v > max) {
      throw new RangeError(`offline ${name} must be an integer in [${OFFLINE_MIN_DIMENSION}, ${max}] (got ${v})`);
    }
  }
  if (!Number.isFinite(fps) || fps <= 0 || fps > OFFLINE_MAX_FPS) {
    throw new RangeError(`offline fps must be in (0, ${OFFLINE_MAX_FPS}] (got ${fps})`);
  }
  const scale = options.resolutionScale ?? 1;
  const resolutionScale = Number.isFinite(scale) ? Math.min(1, Math.max(0.25, scale)) : 1;
  return { width, height, fps, resolutionScale };
}

/** Timestamp of frame `index` in µs: integer, strictly increasing, no duplicates at any fps. */
export function frameTimestampUs(index: number, fps: number): number {
  return Math.round((index * 1_000_000) / fps);
}

/** Simulation time of frame `index` in seconds. */
export function frameTimeSec(index: number, fps: number): number {
  return index / fps;
}
