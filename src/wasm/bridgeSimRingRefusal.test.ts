/**
 * WASM feature freeze (WASM_BACKEND_POLICY.md): the C++ pipeline is group-0
 * only, so the bridge must refuse @group(1) sim-ring WGSL before LoadShader —
 * a logged skip, never an emdawn abort.
 */

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

function mockModule(): EmscriptenModule & { ccall: jest.Mock } {
  return {
    ccall: jest.fn(() => 1),
    _malloc: jest.fn(() => 16),
    _free: jest.fn(),
    getValue: jest.fn(() => 0),
    lengthBytesUTF8: (s: string) => s.length,
    stringToUTF8: jest.fn(),
    HEAPU8: new Uint8Array(1),
    HEAPF32: new Float32Array(1),
  };
}

describe('WASM bridge — group-1 refusal', () => {
  const prev = { initialized: state.initialized, module: wasmRef.module };
  let warn: jest.SpyInstance;

  beforeEach(() => {
    state.initialized = true;
    state.lastLoadError = null;
    wasmRef.module = mockModule();
    warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    jest.spyOn(console, 'log').mockImplementation(() => {});
  });

  afterEach(() => {
    state.initialized = prev.initialized;
    wasmRef.module = prev.module;
    jest.restoreAllMocks();
  });

  it.each([
    ['loadShader', loadShader],
    ['reloadShader', reloadShader],
  ])('%s skips @group(1) WGSL without calling into the module', (op, fn) => {
    const module = wasmRef.module as ReturnType<typeof mockModule>;
    const errorsBefore = state.loadErrorCount;
    expect(fn('dla-walkers', DLA_WALKERS)).toBe(false);
    expect(module.ccall).not.toHaveBeenCalled();
    expect(state.lastLoadError).toMatch(/@group\(1\)/);
    expect(state.loadErrorCount).toBe(errorsBefore + 1);
    expect(warn).toHaveBeenCalledWith(expect.stringContaining(`[WASM] ${op}:`));
  });

  it('refuses @group(1) that arrives alongside an expanded prelude include', async () => {
    const module = wasmRef.module as ReturnType<typeof mockModule>;
    const wgsl = await expandShaderSource(
      '#include "_prelude.wgsl"\n@group(1) @binding(2) var<uniform> simParams: vec4<u32>;\n' +
        '@compute @workgroup_size(64, 1, 1) fn main() {}',
      'zz-ring.wgsl',
    );
    expect(loadShader('zz-ring', wgsl)).toBe(false);
    expect(module.ccall).not.toHaveBeenCalled();
    expect(state.lastLoadError).toMatch(/@group\(1\)/);
  });

  it('still loads group-0 shaders (a commented @group(1) does not opt in)', () => {
    const module = wasmRef.module as ReturnType<typeof mockModule>;
    const wgsl = '// @group(1) is TS-only\n@compute @workgroup_size(16, 16, 1) fn main() {}';
    expect(loadShader('plain', wgsl)).toBe(true);
    expect(module.ccall).toHaveBeenCalledWith('loadShader', 'number', ['number', 'number'], expect.any(Array));
  });
});
