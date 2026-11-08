import * as cpp from './_generated.js';
import { isBusy, runWhenIdle } from './call.js';
import { state, utf8ByteLength, wasmRef } from './state.js';
import { rewriteWgslStorageFormats } from './wgslFormat.js';
import { expandWgslIncludes, hasWgslInclude } from './wgslInclude.js';
import { withBundledLibraries } from './wgslLibraries.js';

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
 * it just refuses source that still contains a directive. `_prelude.wgsl` comes
 * from the bundled copy (wgslLibraries.ts); other libraries resolve as siblings
 * of the shader URL.
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
    withBundledLibraries(async (name) => {
      const res = await fetch(`${baseUrl}${name}`);
      return res.ok ? res.text() : null;
    }),
    `${id}.wgsl`,
  );
}

/**
 * Opt-in @group(1) sim ring (src/contracts/bind_group1.json) is TypeScript-only
 * under the WASM_BACKEND_POLICY.md feature freeze: pipeline.cpp keeps
 * bindGroupLayoutCount = 1, so a group-1 shader would fail pipeline creation
 * inside emdawn. Refuse it here, before LoadShader, as a logged skip.
 * Kept inline (not imported from src/renderer) because the bridge is emitted
 * module-by-module without bundling.
 */
function declaresBindGroup1(wgslCode: string): boolean {
  const stripped = wgslCode.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
  return /@group\(\s*1\s*\)/.test(stripped);
}

function refuseBindGroup1(id: string, op: 'loadShader' | 'reloadShader'): false {
  const message =
    `Shader ${id} declares @group(1) (sim ring) — WASM backend is group-0 only ` +
    '(feature freeze); skipped. Use the WebGPU (TS) renderer for sim-ring shaders.';
  console.warn(`[WASM] ${op}: ${message}`);
  state.lastLoadError = message;
  state.loadErrorCount++;
  return false;
}

export async function loadShader(id: string, wgslCode: string): Promise<boolean> {
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

  if (declaresBindGroup1(wgslCode)) return refuseBindGroup1(id, 'loadShader');

  const rewritten = rewriteWgslStorageFormats(wgslCode, state.colorFormat);
  const idBuf = writeUtf8(id);
  const codeBuf = writeUtf8(rewritten);
  if (!idBuf || !codeBuf) return false;

  let result = 0;
  try {
    // Suspends in the pipeline error-scope pop; id/code stay allocated until it settles.
    result = await cpp.loadShader(wasmRef.module, idBuf.ptr, codeBuf.ptr);
  } finally {
    idBuf.free();
    codeBuf.free();
  }

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

export async function reloadShader(id: string, wgslCode: string): Promise<boolean> {
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

  if (declaresBindGroup1(wgslCode)) return refuseBindGroup1(id, 'reloadShader');

  const rewritten = rewriteWgslStorageFormats(wgslCode, state.colorFormat);
  const idBuf = writeUtf8(id);
  const codeBuf = writeUtf8(rewritten);
  if (!idBuf || !codeBuf) return false;

  let result = 0;
  try {
    result = await cpp.reloadShader(wasmRef.module, idBuf.ptr, codeBuf.ptr);
  } finally {
    idBuf.free();
    codeBuf.free();
  }

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
    return await loadShader(id, await fetchAndExpand(id, url));
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
    return await reloadShader(id, await fetchAndExpand(id, url));
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[WASM] Failed to fetch shader for reload from ${url}:`, err);
    state.lastLoadError = `Reload fetch failed (${url}): ${message}`;
    state.loadErrorCount++;
    return false;
  }
}

/**
 * C++ setActiveShader is void and skips an id with no pipeline, so slot 0 is
 * read back to see whether it took. While a loadShader is suspended (or queued)
 * it runs after it, in call order, so the id it names exists by then.
 */
export function setActiveShader(id: string): void {
  const module = wasmRef.module;
  if (!state.initialized || !module) return;
  const apply = (): void => {
    if (wasmRef.module !== module) return;
    cpp.setActiveShader(module, id);
    if (!id || cpp.getSlotShaderId(module, 0) === id) state.activeShader = id || null;
  };
  if (isBusy(module)) void runWhenIdle(module, apply);
  else apply();
}

/**
 * Assign a shader to a slot, then read the slot back. The C++ side drops an
 * out-of-range index or a shader with no pipeline; an artifact built before
 * slot_limits.json only has 3 slots. Any drop is warned and recorded in
 * state.droppedSlots so share links never lose a layer silently. While a
 * loadShader is suspended the assignment runs after it (in call order) and this
 * returns true; a drop found then still lands in droppedSlots.
 */
export function setSlotShader(slotIndex: number, shaderId: string): boolean {
  const module = wasmRef.module;
  if (!state.initialized || !module) return false;
  const apply = (): boolean => {
    if (wasmRef.module !== module) return false;
    cpp.setSlotShader(module, slotIndex, shaderId);
    const accepted = !shaderId || cpp.getSlotShaderId(module, slotIndex) === shaderId;
    if (accepted) {
      state.droppedSlots.delete(slotIndex);
    } else {
      state.droppedSlots.add(slotIndex);
      console.warn(
        `[WASM] setSlotShader(${slotIndex}, "${shaderId}") dropped by the module ` +
          '(no valid pipeline, or the artifact has fewer slots than slot_limits.json)',
      );
    }
    return accepted;
  };
  if (!isBusy(module)) return apply();
  void runWhenIdle(module, apply);
  return true;
}

/** Slot indexes whose last setSlotShader the module did not accept. */
export function getDroppedSlots(): ReadonlySet<number> {
  return state.droppedSlots;
}

export function setSlotMode(slotIndex: number, mode: 0 | 1 | 'chained' | 'parallel'): void {
  if (!state.initialized || !wasmRef.module) return;
  cpp.setSlotMode(wasmRef.module, slotIndex, mode === 'parallel' || mode === 1 ? 1 : 0);
}

export function getSlotShaderId(slotIndex: number): string {
  if (!state.initialized || !wasmRef.module) return '';
  return cpp.getSlotShaderId(wasmRef.module, slotIndex);
}

export function getSlotEnabled(slotIndex: number): boolean {
  if (!state.initialized || !wasmRef.module) return false;
  return cpp.getSlotEnabled(wasmRef.module, slotIndex) !== 0;
}

export function getSlotMode(slotIndex: number): number {
  if (!state.initialized || !wasmRef.module) return 0;
  return cpp.getSlotMode(wasmRef.module, slotIndex);
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
