/**
 * WebGPUTiming.ts
 *
 * GPU timestamp query setup and timing readback for the WebGPU renderer.
 * Mirrors wasm_renderer/timing.cpp.
 */

import { GPUTimings } from '../Renderer';

export type GpuTimingsState = {
  parallelTime: number;
  chainedTime: number;
  totalTime: number;
};

export interface WebGPUTimestampQueries {
  supportsTimestampQuery: boolean;
  querySet: GPUQuerySet | null;
  queryBuffer: GPUBuffer | null;
}

export function createTimestampQueries(device: GPUDevice): WebGPUTimestampQueries {
  const supportsTimestampQuery = device.features.has('timestamp-query');
  let querySet: GPUQuerySet | null = null;
  let queryBuffer: GPUBuffer | null = null;

  if (supportsTimestampQuery) {
    try {
      querySet = device.createQuerySet({
        type: 'timestamp',
        count: 8,
      });
      queryBuffer = device.createBuffer({
        size: 8 * 8,
        usage: GPUBufferUsage.QUERY_RESOLVE | GPUBufferUsage.COPY_SRC,
      });
      console.log('[WebGPU] Timestamp queries enabled for GPU profiling');
    } catch (e) {
      console.warn('[WebGPU] Timestamp query creation failed:', e);
      return { supportsTimestampQuery: false, querySet: null, queryBuffer: null };
    }
  }

  return { supportsTimestampQuery, querySet, queryBuffer };
}

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
