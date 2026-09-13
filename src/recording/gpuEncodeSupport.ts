/**
 * gpuEncodeSupport.ts
 *
 * Main-bundle half of Recording 2.0: feature detection, the opt-in toggle, and
 * the lazy loader. The encoder + webm-muxer live in the "gpu-encode" chunk.
 */

import type * as GpuEncoderModule from './gpuEncoder';

export const GPU_ENCODE_STORAGE_KEY = 'pixelocity.recording.gpuEncode';

/** WebCodecs encode + VideoFrame construction are both required. */
export function isGpuEncodeAvailable(): boolean {
  return typeof VideoEncoder !== 'undefined' && typeof VideoFrame !== 'undefined';
}

export function readGpuEncodePreference(): boolean {
  try {
    return window.localStorage.getItem(GPU_ENCODE_STORAGE_KEY) === '1';
  } catch {
    return false;
  }
}

export function writeGpuEncodePreference(enabled: boolean): void {
  try {
    window.localStorage.setItem(GPU_ENCODE_STORAGE_KEY, enabled ? '1' : '0');
  } catch {
    // Private mode / blocked storage: the toggle still works for this session.
  }
}

let modulePromise: Promise<typeof GpuEncoderModule> | null = null;

export function loadGpuEncoder(): Promise<typeof GpuEncoderModule> {
  if (!modulePromise) {
    modulePromise = import(/* webpackChunkName: "gpu-encode" */ './gpuEncoder').catch((err) => {
      modulePromise = null;
      throw err;
    });
  }
  return modulePromise;
}
