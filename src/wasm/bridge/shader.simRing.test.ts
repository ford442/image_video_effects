/**
 * bind_group1.json: the WASM renderer binds group 0 only (#1080 freeze), so a
 * @group(1) shader must be refused before it reaches the module — never an
 * invalid pipeline, never an abort.
 */

// The bridge imports its siblings as './x.js' (browser ESM); CRA's Jest cannot map
// those to .ts on its own, so point each one at the real module.
jest.mock('./state.js', () => jest.requireActual('./state'), { virtual: true });
jest.mock('./wgslFormat.js', () => jest.requireActual('./wgslFormat'), { virtual: true });
jest.mock('./wgslInclude.js', () => jest.requireActual('./wgslInclude'), { virtual: true });

/* eslint-disable import/first */
import { declaresSimRing, loadShader, reloadShader } from './shader';
import { state, wasmRef } from './state';
/* eslint-enable import/first */

const RING_WGSL = `
@group(0) @binding(0) var u_sampler: sampler;
@group(1) @binding(0) var<storage, read_write> simState: array<vec4<f32>>;
@compute @workgroup_size(64, 1, 1) fn main() {}
`;

describe('WASM bridge sim-ring guard', () => {
  const ccall = jest.fn(() => 1);

  beforeEach(() => {
    ccall.mockClear();
    state.initialized = true;
    state.lastLoadError = null;
    wasmRef.module = {
      ccall,
      _malloc: jest.fn(() => 1),
      _free: jest.fn(),
      stringToUTF8: jest.fn(),
      lengthBytesUTF8: jest.fn(() => 8),
    } as unknown as typeof wasmRef.module;
  });

  afterEach(() => {
    state.initialized = false;
    wasmRef.module = null;
  });

  it('matches the renderer-side detector (comments ignored)', () => {
    expect(declaresSimRing(RING_WGSL)).toBe(true);
    expect(declaresSimRing('// @group(1) @binding(0)\n@group(0) @binding(0) var s: sampler;')).toBe(false);
  });

  it('refuses group-1 shaders in loadShader and reloadShader without calling the module', () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    expect(loadShader('dla-walkers', RING_WGSL)).toBe(false);
    expect(reloadShader('dla-walkers', RING_WGSL)).toBe(false);
    warn.mockRestore();

    expect(ccall).not.toHaveBeenCalled();
    expect(state.lastLoadError).toMatch(/@group\(1\).*skipped on the WASM renderer/);
  });
});
