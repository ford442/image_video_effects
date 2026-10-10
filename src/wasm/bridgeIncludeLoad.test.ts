/**
 * The WASM load path expands `#include` before LoadShader. `_prelude.wgsl` must
 * come from the bundled copy: hosts that serve catalog shaders (the storage API,
 * an app deploy without public/shaders) do not serve the `_` libraries.
 */

import { loadShaderFromURL } from './bridge/shader';
import { state, wasmRef, EmscriptenModule } from './bridge/state';

function mockModule(): EmscriptenModule & { ccall: jest.Mock; stringToUTF8: jest.Mock } {
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

const SHADER_URL = 'https://storage.example/shaders/zz-includes.wgsl';

describe('WASM bridge — #include on the URL load path', () => {
  const prev = { initialized: state.initialized, module: wasmRef.module };
  const originalFetch = global.fetch;
  let fetched: string[];

  function serve(files: Record<string, string>) {
    fetched = [];
    global.fetch = jest.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      fetched.push(url);
      return url in files
        ? new Response(files[url], { status: 200 })
        : new Response('not found', { status: 404, statusText: 'Not Found' });
    }) as typeof fetch;
  }

  beforeEach(() => {
    state.initialized = true;
    state.lastLoadError = null;
    wasmRef.module = mockModule();
    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    state.initialized = prev.initialized;
    wasmRef.module = prev.module;
    global.fetch = originalFetch;
    jest.restoreAllMocks();
  });

  it('loads a prelude shader when the host has no _prelude.wgsl', async () => {
    serve({ [SHADER_URL]: '#include "_prelude.wgsl"\n@compute @workgroup_size(16, 16, 1) fn main() {}' });
    const module = wasmRef.module as ReturnType<typeof mockModule>;

    await expect(loadShaderFromURL('zz-includes', SHADER_URL)).resolves.toBe(true);

    expect(fetched).toEqual([SHADER_URL]);
    expect(module.ccall).toHaveBeenCalledWith('loadShader', 'number', ['number', 'number'], expect.any(Array));
    const sources = module.stringToUTF8.mock.calls.map((call) => String(call[0]));
    const code = sources.find((s) => s.includes('fn main()'));
    expect(code).toContain('@group(0) @binding(3) var<uniform> u: Uniforms;');
    expect(code).not.toMatch(/^#include/m);
  });

  it('still fetches other libraries next to the shader, and fails when one is missing', async () => {
    serve({ [SHADER_URL]: '#include "_lib.wgsl"\nfn main() {}' });
    const module = wasmRef.module as ReturnType<typeof mockModule>;

    await expect(loadShaderFromURL('zz-includes', SHADER_URL)).resolves.toBe(false);

    expect(fetched).toContain('https://storage.example/shaders/_lib.wgsl');
    expect(module.ccall).not.toHaveBeenCalled();
    expect(state.lastLoadError).toMatch(/file not found/);
  });
});
