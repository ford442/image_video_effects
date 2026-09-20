import { state, utf8ByteLength, wasmRef } from './state.js';
import { rewriteWgslStorageFormats } from './wgslFormat.js';
import { expandWgslIncludes, hasWgslInclude } from './wgslInclude.js';

export interface SlotState {
  shaderId: string | null;
  enabled: boolean;
  mode: 'chained' | 'parallel';
}

function writeUtf8(id: string): { ptr: number; free: () => void } | null {
  const module = wasmRef.module;
  if (!module) return null;
  const len = utf8ByteLength(module, id);
  const ptr = module._malloc(len);
  module.stringToUTF8(id, ptr, len);
  return { ptr, free: () => module._free(ptr) };
}

/**
 * Fetches a shader and expands its `#include` directives.
 *
 * This is the only place WGSL crosses into the WASM module, so it is also the
 * only place that needs an include expander — the C++ side never parses one,
 * it just refuses source that still contains a directive. Libraries resolve as
 * siblings of the shader URL.
 */
async function fetchAndExpand(id: string, url: string): Promise<string> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`HTTP error ${response.status}: ${response.statusText}`);
  }
  const wgslCode = await response.text();
  if (!hasWgslInclude(wgslCode)) return wgslCode;

  const baseUrl = url.slice(0, url.lastIndexOf('/') + 1);
  return expandWgslIncludes(
    wgslCode,
    async (name) => {
      const res = await fetch(`${baseUrl}${name}`);
      return res.ok ? res.text() : null;
    },
    `${id}.wgsl`,
  );
}

export function loadShader(id: string, wgslCode: string): boolean {
  if (!state.initialized || !wasmRef.module) {
    console.error('[WASM] Renderer not initialized');
    return false;
  }

  // Expansion needs to fetch, so it cannot happen here. Callers come through
  // loadShaderFromURL; anything else must expand before calling.
  if (hasWgslInclude(wgslCode)) {
    const message = `Shader ${id} still contains an unexpanded #include — expand before loadShader()`;
    console.error(`[WASM] ${message}`);
    state.lastLoadError = message;
    state.loadErrorCount++;
    return false;
  }

  const rewritten = rewriteWgslStorageFormats(wgslCode, state.colorFormat);
  const idBuf = writeUtf8(id);
  const codeBuf = writeUtf8(rewritten);
  if (!idBuf || !codeBuf) return false;

  const result = Number(
    wasmRef.module.ccall('loadShader', 'number', ['number', 'number'], [idBuf.ptr, codeBuf.ptr]),
  );

  idBuf.free();
  codeBuf.free();

  if (result) {
    state.activeShader = id;
    console.log(`[WASM] Loaded shader: ${id}`);
    return true;
  }
  console.error(`[WASM] Failed to load shader: ${id}`);
  state.lastLoadError = `Failed to compile/load shader: ${id}`;
  state.loadErrorCount++;
  return false;
}

export function reloadShader(id: string, wgslCode: string): boolean {
  if (!state.initialized || !wasmRef.module) {
    console.error('[WASM] Renderer not initialized');
    return false;
  }

  if (hasWgslInclude(wgslCode)) {
    const message = `Shader ${id} still contains an unexpanded #include — expand before reloadShader()`;
    console.error(`[WASM] ${message}`);
    state.lastLoadError = message;
    state.loadErrorCount++;
    return false;
  }

  const rewritten = rewriteWgslStorageFormats(wgslCode, state.colorFormat);
  const idBuf = writeUtf8(id);
  const codeBuf = writeUtf8(rewritten);
  if (!idBuf || !codeBuf) return false;

  const result = Number(
    wasmRef.module.ccall('reloadShader', 'number', ['number', 'number'], [idBuf.ptr, codeBuf.ptr]),
  );

  idBuf.free();
  codeBuf.free();

  if (result) {
    console.log(`[WASM] Hot-reloaded shader: ${id}`);
    return true;
  }
  console.error(`[WASM] Hot-reload failed for: ${id}`);
  state.lastLoadError = `Hot-reload failed: ${id}`;
  state.loadErrorCount++;
  return false;
}

export async function loadShaderFromURL(id: string, url: string): Promise<boolean> {
  try {
    return loadShader(id, await fetchAndExpand(id, url));
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[WASM] Failed to fetch shader from ${url}:`, err);
    state.lastLoadError = `Fetch failed (${url}): ${message}`;
    state.loadErrorCount++;
    return false;
  }
}

export async function reloadShaderFromURL(id: string, url: string): Promise<boolean> {
  try {
    return reloadShader(id, await fetchAndExpand(id, url));
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[WASM] Failed to fetch shader for reload from ${url}:`, err);
    state.lastLoadError = `Reload fetch failed (${url}): ${message}`;
    state.loadErrorCount++;
    return false;
  }
}

export function setActiveShader(id: string): void {
  if (!state.initialized || !wasmRef.module) {
    return;
  }

  const result = Number(wasmRef.module.ccall('setActiveShader', 'number', ['string'], [id]));
  if (result) {
    state.activeShader = id;
  }
}

export function setSlotShader(slotIndex: number, shaderId: string): void {
  if (!state.initialized || !wasmRef.module) return;
  wasmRef.module.ccall('setSlotShader', 'number', ['number', 'string'], [slotIndex, shaderId]);
}

export function setSlotMode(slotIndex: number, mode: 0 | 1 | 'chained' | 'parallel'): void {
  if (!state.initialized || !wasmRef.module) return;
  const modeInt = mode === 'parallel' || mode === 1 ? 1 : 0;
  wasmRef.module.ccall('setSlotMode', null, ['number', 'number'], [slotIndex, modeInt]);
}

export function getSlotShaderId(slotIndex: number): string {
  if (!state.initialized || !wasmRef.module) return '';
  return String(wasmRef.module.ccall('getSlotShaderId', 'string', ['number'], [slotIndex]) ?? '');
}

export function getSlotEnabled(slotIndex: number): boolean {
  if (!state.initialized || !wasmRef.module) return false;
  return Boolean(wasmRef.module.ccall('getSlotEnabled', 'number', ['number'], [slotIndex]));
}

export function getSlotMode(slotIndex: number): number {
  if (!state.initialized || !wasmRef.module) return 0;
  return Number(wasmRef.module.ccall('getSlotMode', 'number', ['number'], [slotIndex]) ?? 0);
}

export function getSlotState(slotIndex: number): SlotState {
  const shaderId = getSlotShaderId(slotIndex);
  const modeInt = getSlotMode(slotIndex);
  return {
    shaderId: shaderId.length > 0 ? shaderId : null,
    enabled: getSlotEnabled(slotIndex),
    mode: modeInt === 1 ? 'parallel' : 'chained',
  };
}
