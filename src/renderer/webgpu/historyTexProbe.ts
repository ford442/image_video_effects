/**
 * Probe-allocate historyTex before the full working pool (#1204).
 * Pascal + Chrome D3D12 runs out of committed heap on 2048² × 8 × rgba16/32float.
 */

import type { InternalColorFormat } from '../../config/formatPolicy';
import {
  getHistoryWorkingSizeCap,
  HISTORY_FULL_WORKING_SIZE,
  HISTORY_SAFE_WORKING_SIZE,
  persistHistoryOomCap,
} from '../../config/vramBudget';
import { HISTORY_DEPTH } from './webgpuConstants';

export interface HistoryProbeRung {
  size: number;
  layers: number;
}

/** Ladder: never retry 2048 after any OOM this session. */
export const HISTORY_PROBE_RUNGS: readonly HistoryProbeRung[] = [
  { size: HISTORY_FULL_WORKING_SIZE, layers: HISTORY_DEPTH },
  { size: HISTORY_SAFE_WORKING_SIZE, layers: HISTORY_DEPTH },
  { size: HISTORY_SAFE_WORKING_SIZE, layers: 4 },
  { size: HISTORY_SAFE_WORKING_SIZE, layers: 1 },
];

export interface HistoryProbeResult {
  ok: boolean;
  workingSize: number;
  layers: number;
  deviceLost: boolean;
  oom: boolean;
}

function historyUsage(): GPUTextureUsageFlags {
  return (
    GPUTextureUsage.TEXTURE_BINDING |
    GPUTextureUsage.STORAGE_BINDING |
    GPUTextureUsage.COPY_DST |
    GPUTextureUsage.COPY_SRC
  );
}

function isOutOfMemoryError(err: unknown): boolean {
  if (!err) return false;
  if (typeof GPUOutOfMemoryError !== 'undefined' && err instanceof GPUOutOfMemoryError) {
    return true;
  }
  const name = (err as { name?: string }).name;
  const msg = err instanceof Error ? err.message : String(err);
  return name === 'GPUOutOfMemoryError' || /out of memory|GPUOutOfMemory/i.test(msg);
}

export function rungsForRequest(requestedWorkingSize: number, cap: number): HistoryProbeRung[] {
  const limit = Math.min(requestedWorkingSize, cap);
  return HISTORY_PROBE_RUNGS.filter((rung) => rung.size <= limit);
}

async function deviceAlreadyLost(device: GPUDevice): Promise<boolean> {
  const lost = device.lost as Promise<GPUDeviceLostInfo> & { then?: unknown };
  if (!lost || typeof lost.then !== 'function') return false;
  let settled = false;
  lost.then(() => {
    settled = true;
  });
  await Promise.resolve();
  return settled;
}

async function tryHistoryAlloc(
  device: GPUDevice,
  size: number,
  layers: number,
  format: InternalColorFormat,
): Promise<{ oom: boolean; lost: boolean }> {
  if (await deviceAlreadyLost(device)) {
    return { oom: true, lost: true };
  }

  const hasScopes =
    typeof device.pushErrorScope === 'function' && typeof device.popErrorScope === 'function';
  if (hasScopes) {
    device.pushErrorScope('out-of-memory');
  }

  let tex: GPUTexture | undefined;
  try {
    tex = device.createTexture({
      label: 'historyTex-probe',
      size: { width: size, height: size, depthOrArrayLayers: layers },
      format,
      usage: historyUsage(),
    });
  } catch (err) {
    if (hasScopes) {
      try {
        await device.popErrorScope();
      } catch {
        /* ignore */
      }
    }
    persistHistoryOomCap(HISTORY_SAFE_WORKING_SIZE);
    const lost = await deviceAlreadyLost(device);
    return { oom: isOutOfMemoryError(err) || true, lost };
  }

  let oom = false;
  if (hasScopes) {
    try {
      const scoped = await device.popErrorScope();
      if (scoped) oom = true;
    } catch (err) {
      oom = isOutOfMemoryError(err) || true;
    }
  }

  try {
    tex.destroy();
  } catch {
    /* invalid texture after OOM */
  }

  const lost = await deviceAlreadyLost(device);
  if (oom || lost) {
    persistHistoryOomCap(HISTORY_SAFE_WORKING_SIZE);
  }
  return { oom, lost };
}

/**
 * Find the largest historyTex (size × layers) that fits.
 * Destroys each probe texture. Caller then allocates the real pool at the result.
 */
export async function probeHistoryTex(
  device: GPUDevice,
  requestedWorkingSize: number,
  format: InternalColorFormat,
): Promise<HistoryProbeResult> {
  const cap = getHistoryWorkingSizeCap();
  const rungs = rungsForRequest(requestedWorkingSize, cap);
  if (rungs.length === 0) {
    return {
      ok: false,
      workingSize: HISTORY_SAFE_WORKING_SIZE,
      layers: 1,
      deviceLost: false,
      oom: true,
    };
  }

  for (const rung of rungs) {
    const { oom, lost } = await tryHistoryAlloc(device, rung.size, rung.layers, format);
    if (lost) {
      return {
        ok: false,
        workingSize: HISTORY_SAFE_WORKING_SIZE,
        layers: rung.layers,
        deviceLost: true,
        oom: true,
      };
    }
    if (!oom) {
      console.log(
        `[WebGPU] historyTex probe OK ${rung.size}²×${rung.layers} (${format})`,
      );
      return {
        ok: true,
        workingSize: rung.size,
        layers: rung.layers,
        deviceLost: false,
        oom: false,
      };
    }
    console.warn(
      `[WebGPU] historyTex probe OOM at ${rung.size}²×${rung.layers} — dropping (do not retry 2048)`,
    );
  }

  return {
    ok: false,
    workingSize: HISTORY_SAFE_WORKING_SIZE,
    layers: 1,
    deviceLost: false,
    oom: true,
  };
}
