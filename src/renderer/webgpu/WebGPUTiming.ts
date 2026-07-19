/**
 * WebGPUTiming.ts
 *
 * GPU timestamp query setup and timing readback for the WebGPU renderer.
 * Mirrors wasm_renderer/timing.cpp.
 */

import { GPUTimings } from '../Renderer';
import { createTimestampQueries, WebGPUTimestampQueries } from './WebGPUResourceManager';

export type GpuTimingsState = {
  parallelTime: number;
  chainedTime: number;
  totalTime: number;
};

export function setupTimestampQueries(device: GPUDevice): WebGPUTimestampQueries {
  return createTimestampQueries(device);
}

export function buildGPUTimings(
  gpuTimings: GpuTimingsState,
  supportsTimestampQuery: boolean,
): GPUTimings {
  return {
    ...gpuTimings,
    available: supportsTimestampQuery,
    timingSource: supportsTimestampQuery ? 'gpu-timestamp' : 'wall-clock',
  };
}
