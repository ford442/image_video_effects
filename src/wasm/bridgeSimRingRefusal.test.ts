/**
 * WASM feature freeze (WASM_BACKEND_POLICY.md): the C++ pipeline is group-0
 * only, so the bridge must refuse @group(1) sim-ring WGSL before LoadShader —
 * a logged skip, never an emdawn abort.
 */

import type { Mock, MockInstance } from 'vitest';
import { loadShader, reloadShader } from './bridge/shader';
import { state, wasmRef, EmscriptenModule } from './bridge/state';
import { expandShaderSource, readExpandedShader } from '../test-utils/shaderSource';

// loadShader receives source that loadShaderFromURL already expanded, so the
// fixture is expanded too (dla-walkers may get its group-0 header from _prelude.wgsl).
let DLA_WALKERS = '';

beforeAll(async () => {
  const wgsl = await readExpandedShader('dla-walkers');
  if (wgsl === null) throw new Error('public/shaders/dla-walkers.wgsl is missing');
  DLA_WALKERS = wgsl;
});

function mockModule(): EmscriptenModule & { ccall: Mock } {
  return {
    ccall: vi.fn(() => 1),
    _malloc: vi.fn(() => 16),
    _free: vi.fn(),
    getValue: vi.fn(() => 0),
    lengthBytesUTF8: (s: string) => s.length,
    stringToUTF8: vi.fn(),
    HEAPU8: new Uint8Array(1),
    HEAPF32: new Float32Array(1),
  };
}

describe('WASM bridge — group-1 refusal', () => {
  const prev = { initialized: state.initialized, module: wasmRef.module };
  let warn: MockInstance;

  beforeEach(() => {
    state.initialized = true;
    state.lastLoadError = null;
    wasmRef.module = mockModule();
    warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.spyOn(console, 'log').mockImplementation(() => {});
  });

  afterEach(() => {
    state.initialized = prev.initialized;
    wasmRef.module = prev.module;
    vi.restoreAllMocks();
  });

  it.each([
    ['loadShader', loadShader],
    ['reloadShader', reloadShader],
  ])('%s skips @group(1) WGSL without calling into the module', async (op, fn) => {
    const module = wasmRef.module as ReturnType<typeof mockModule>;
    const errorsBefore = state.loadErrorCount;
    expect(await fn('dla-walkers', DLA_WALKERS)).toBe(false);
    expect(module.ccall).not.toHaveBeenCalled();
    expect(state.lastLoadError).toMatch(/@group\(1\)/);
    expect(state.loadErrorCount).toBe(errorsBefore + 1);
    expect(warn).toHaveBeenCalledWith(expect.stringContaining(`[WASM] ${op}:`));
  });

  // The flagships' catalog urls point at their first entry. They declare binding 3 (simHash) or
  // the base ring; either way the bridge skips them before LoadShader, with the include-expanded source.
  it.each(['murmuration-flock', 'photon-bins-march'])('skips the %s flagship entry without calling into the module', async (id) => {
    const module = wasmRef.module as ReturnType<typeof mockModule>;
    const wgsl = await readExpandedShader(id);
    if (wgsl === null) throw new Error(`public/shaders/${id}.wgsl is missing`);
    const errorsBefore = state.loadErrorCount;
    expect(await loadShader(id, wgsl)).toBe(false);
    expect(await reloadShader(id, wgsl)).toBe(false);
    expect(module.ccall).not.toHaveBeenCalled();
    expect(state.lastLoadError).toMatch(/@group\(1\)/);
    expect(state.loadErrorCount).toBe(errorsBefore + 2);
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('[WASM] loadShader:'));
  });

  it('refuses @group(1) that arrives alongside an expanded prelude include', async () => {
    const module = wasmRef.module as ReturnType<typeof mockModule>;
    const wgsl = await expandShaderSource(
      '#include "_prelude.wgsl"\n@group(1) @binding(2) var<uniform> simParams: vec4<u32>;\n' +
        '@compute @workgroup_size(64, 1, 1) fn main() {}',
      'zz-ring.wgsl',
    );
    expect(await loadShader('zz-ring', wgsl)).toBe(false);
    expect(module.ccall).not.toHaveBeenCalled();
    expect(state.lastLoadError).toMatch(/@group\(1\)/);
  });

  it('still loads group-0 shaders (a commented @group(1) does not opt in)', async () => {
    const module = wasmRef.module as ReturnType<typeof mockModule>;
    const wgsl = '// @group(1) is TS-only\n@compute @workgroup_size(16, 16, 1) fn main() {}';
    expect(await loadShader('plain', wgsl)).toBe(true);
    expect(module.ccall).toHaveBeenCalledWith('loadShader', 'number', ['number', 'number'], expect.any(Array), expect.any(Object));
  });
});
