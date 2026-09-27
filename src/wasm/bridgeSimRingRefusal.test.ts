/**
 * WASM feature freeze (WASM_BACKEND_POLICY.md): the C++ pipeline is group-0
 * only, so the bridge must refuse @group(1) sim-ring WGSL before LoadShader —
 * a logged skip, never an emdawn abort.
 */

import * as fs from 'fs';
import * as path from 'path';
import { loadShader, reloadShader } from './bridge/shader';
import { state, wasmRef, EmscriptenModule } from './bridge/state';

const DLA_WALKERS = fs.readFileSync(
  path.join(__dirname, '../../public/shaders/dla-walkers.wgsl'),
  'utf8',
);

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

  it('still loads group-0 shaders (a commented @group(1) does not opt in)', () => {
    const module = wasmRef.module as ReturnType<typeof mockModule>;
    const wgsl = '// @group(1) is TS-only\n@compute @workgroup_size(16, 16, 1) fn main() {}';
    expect(loadShader('plain', wgsl)).toBe(true);
    expect(module.ccall).toHaveBeenCalledWith('loadShader', 'number', ['number', 'number'], expect.any(Array));
  });
});
