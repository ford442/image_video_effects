import * as cpp from './_generated.js';
import { isBusy, runWhenIdle } from './call.js';
import { state, utf8ByteLength, wasmRef, type EmscriptenModule } from './state.js';
import { analyzeShaderBindings, parseWorkgroupSize, shaderUsageBits } from './wgslAnalysis.js';
import { rewriteWgslStorageFormats } from './wgslFormat.js';
import { expandWgslIncludes, hasWgslInclude } from './wgslInclude.js';
import { withBundledLibraries } from './wgslLibraries.js';

export interface SlotState {
  shaderId: string | null;
  enabled: boolean;
  mode: 'chained' | 'parallel';
}

function writeUtf8(module: EmscriptenModule, text: string): { ptr: number; free: () => void } {
  const len = utf8ByteLength(module, text);
  const ptr = module._malloc(len);
  module.stringToUTF8(text, ptr, len);
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

/**
 * Everything C++ needs to build the pipeline, from the one TS analysis
 * (wgslAnalysis.ts): storage formats rewritten to the format C++ allocated,
 * the `main` dispatch size and the bindingUsage bits.
 */
function prepareShader(module: EmscriptenModule, wgslCode: string) {
  const format = cpp.getColorFormat(module) === 1 ? 1 : 0;
  const code = rewriteWgslStorageFormats(wgslCode, format);
  const workgroup = parseWorkgroupSize(code);
  return { format, code, workgroup, usage: shaderUsageBits(analyzeShaderBindings(code)) };
}

/** Refusals that need no module: an unexpanded #include or a @group(1) shader. */
function refuseBeforeCompile(id: string, wgslCode: string, op: 'loadShader' | 'reloadShader'): boolean {
  // Expansion needs to fetch, so it cannot happen here. Callers come through
  // load/reloadShaderFromURL; anything else must expand before calling.
  if (hasWgslInclude(wgslCode)) {
    const message = `Shader ${id} still contains an unexpanded #include — expand before ${op}()`;
    console.error(`[WASM] ${message}`);
    state.lastLoadError = message;
    state.loadErrorCount++;
    return true;
  }
  if (declaresBindGroup1(wgslCode)) {
    refuseBindGroup1(id, op);
    return true;
  }
  return false;
}

/**
 * loadShader / reloadShader are async exports (the pipeline error-scope pop
 * suspends in WaitAny). id and code stay allocated until C++ returns: it reads
 * them after the suspend. 'refused' was already logged and counted.
 */
async function compileShader(
  op: 'loadShader' | 'reloadShader',
  id: string,
  wgslCode: string,
): Promise<'ok' | 'refused' | 'failed'> {
  const module = wasmRef.module;
  if (!state.initialized || !module) {
    console.error('[WASM] Renderer not initialized');
    return 'refused';
  }
  if (refuseBeforeCompile(id, wgslCode, op)) return 'refused';

  // A queued setColorFormat can run between prepare and compile; the pipeline
  // then fails layout validation, so prepare once more for the new format.
  for (let attempt = 0; ; attempt++) {
    const { format, code, workgroup, usage } = prepareShader(module, wgslCode);
    const idBuf = writeUtf8(module, id);
    const codeBuf = writeUtf8(module, code);
    let ok = false;
    try {
      ok = (await cpp[op](module, idBuf.ptr, codeBuf.ptr, workgroup.x, workgroup.y, usage)) === 1;
    } catch (err) {
      console.error(`[WASM] ${op}(${id}) threw:`, err);
      return 'failed';
    } finally {
      idBuf.free();
      codeBuf.free();
    }
    if (ok) return 'ok';
    if (attempt > 0 || wasmRef.module !== module || cpp.getColorFormat(module) === format) return 'failed';
  }
}

export async function loadShader(id: string, wgslCode: string): Promise<boolean> {
  const outcome = await compileShader('loadShader', id, wgslCode);
  if (outcome === 'ok') {
    state.activeShader = id;
    console.log(`[WASM] Loaded shader: ${id}`);
    return true;
  }
  if (outcome === 'failed') {
    console.error(`[WASM] Failed to load shader: ${id}`);
    state.lastLoadError = `Failed to compile/load shader: ${id}`;
    state.loadErrorCount++;
  }
  return false;
}

/** Hot reload. A failed compile keeps the previous pipeline (C++ swaps only on success). */
export async function reloadShader(id: string, wgslCode: string): Promise<boolean> {
  const outcome = await compileShader('reloadShader', id, wgslCode);
  if (outcome === 'ok') {
    console.log(`[WASM] Hot-reloaded shader: ${id}`);
    return true;
  }
  if (outcome === 'failed') {
    console.error(`[WASM] Hot-reload failed for: ${id} (previous pipeline kept)`);
    state.lastLoadError = `Hot-reload failed: ${id}`;
    state.loadErrorCount++;
  }
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
 * C++ setActiveShader is void and skips an id with no pipeline; slot 0 shows
 * whether it took. Queued behind a suspended loadShader, so the id it names
 * exists by the time it runs.
 */
export function setActiveShader(id: string): void {
  const module = wasmRef.module;
  if (!state.initialized || !module) return;
  const apply = () => {
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
