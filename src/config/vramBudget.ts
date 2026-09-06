/**
 * Session VRAM budget after GPUOutOfMemoryError (#1204).
 * WASM bridge copies cannot import this file — keep the sessionStorage keys
 * in sync with src/wasm/bridge/init.ts.
 *
 * Default working size is 1024. 2048 is an upgrade only (allowsFullWorkingSize).
 * Do not derive maxTextureDimension2D from maxBufferSize — that stays 8192.
 */

import type { AdapterGpuType } from './formatPolicy';

export const HISTORY_OOM_CAP_KEY = 'px_history_oom_cap';
export const WASM_BLOCK_AFTER_OOM_KEY = 'px_webgpu_oom_block_wasm';

export const HISTORY_SAFE_WORKING_SIZE = 1024;
export const HISTORY_FULL_WORKING_SIZE = 2048;
/** WebGPU base maxBufferSize is 256 MiB; require 1 GiB before attempting 2048. */
export const MIN_MAX_BUFFER_SIZE_FOR_FULL = 1073741824;

/** Pascal / GTX 10-series still OOM at 2048²×8 float despite a large maxBufferSize. */
export const PASCAL_ADAPTER_BLOCKLIST =
  /pascal|gtx\s*10[0-9]{2}|gt\s*10[0-9]{2}|mx\s*1[0-9]{2}/i;

export interface FullWorkingSizeGate {
  maxBufferSize?: number;
  adapterGpuType?: AdapterGpuType;
  adapterSummary?: string;
  isFallbackAdapter?: boolean;
}

function readStorage(key: string): string | null {
  try {
    if (typeof sessionStorage === 'undefined') return null;
    return sessionStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeStorage(key: string, value: string): void {
  try {
    if (typeof sessionStorage === 'undefined') return;
    sessionStorage.setItem(key, value);
  } catch {
    /* private mode / SSR */
  }
}

/** Default and post-OOM working cap is 1024. 2048 is never returned here. */
export function getHistoryWorkingSizeCap(): number {
  return HISTORY_SAFE_WORKING_SIZE;
}

export function persistHistoryOomCap(size: number = HISTORY_SAFE_WORKING_SIZE): void {
  writeStorage(HISTORY_OOM_CAP_KEY, String(size));
  writeStorage(WASM_BLOCK_AFTER_OOM_KEY, '1');
}

export function isWasmBlockedAfterOom(): boolean {
  return readStorage(WASM_BLOCK_AFTER_OOM_KEY) === '1';
}

export function hasHistoryOomCapThisTab(): boolean {
  const raw = readStorage(HISTORY_OOM_CAP_KEY);
  return raw === String(HISTORY_SAFE_WORKING_SIZE);
}

export function allowsFullWorkingSize(gate: FullWorkingSizeGate): boolean {
  if (isWasmBlockedAfterOom() || hasHistoryOomCapThisTab()) return false;
  if (gate.isFallbackAdapter) return false;
  if (gate.adapterGpuType !== 'discrete') return false;
  if ((gate.maxBufferSize ?? 0) < MIN_MAX_BUFFER_SIZE_FOR_FULL) return false;
  const hay = gate.adapterSummary ?? '';
  if (PASCAL_ADAPTER_BLOCKLIST.test(hay)) return false;
  return true;
}

export function clampWorkingSize(size: number, cap = getHistoryWorkingSizeCap()): number {
  return Math.min(size, cap);
}

export function isGpuOutOfMemoryError(err: unknown): boolean {
  if (!err) return false;
  if (typeof GPUOutOfMemoryError !== 'undefined' && err instanceof GPUOutOfMemoryError) {
    return true;
  }
  const name = (err as { name?: string }).name;
  const msg = err instanceof Error ? err.message : String(err);
  return name === 'GPUOutOfMemoryError' || /out of memory|GPUOutOfMemory/i.test(msg);
}
