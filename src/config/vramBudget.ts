/**
 * Session VRAM budget after GPUOutOfMemoryError (#1204).
 * WASM bridge copies cannot import this file — keep the sessionStorage keys
 * in sync with src/wasm/bridge/init.ts.
 */

export const HISTORY_OOM_CAP_KEY = 'px_history_oom_cap';
export const WASM_BLOCK_AFTER_OOM_KEY = 'px_webgpu_oom_block_wasm';

export const HISTORY_SAFE_WORKING_SIZE = 1024;
export const HISTORY_FULL_WORKING_SIZE = 2048;

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

/** 1024 after a historyTex OOM this tab; otherwise 2048 may still be attempted. */
export function getHistoryWorkingSizeCap(): number {
  const raw = readStorage(HISTORY_OOM_CAP_KEY);
  const n = raw ? parseInt(raw, 10) : NaN;
  return n === HISTORY_SAFE_WORKING_SIZE ? HISTORY_SAFE_WORKING_SIZE : HISTORY_FULL_WORKING_SIZE;
}

export function persistHistoryOomCap(size: number = HISTORY_SAFE_WORKING_SIZE): void {
  writeStorage(HISTORY_OOM_CAP_KEY, String(size));
  writeStorage(WASM_BLOCK_AFTER_OOM_KEY, '1');
}

export function isWasmBlockedAfterOom(): boolean {
  return readStorage(WASM_BLOCK_AFTER_OOM_KEY) === '1';
}

export function clampWorkingSize(size: number, cap = getHistoryWorkingSizeCap()): number {
  return Math.min(size, cap);
}
