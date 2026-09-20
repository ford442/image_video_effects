/**
 * ShaderValidator must be able to fail a bad shader with WebGPU entirely absent.
 *
 * The real public/wasm/naga_wasm.wasm is instantiated here — this is an end-to-end
 * check of the committed artifact, not a stub. The ABI is re-implemented inline
 * rather than imported from public/wasm/naga_wasm.js because that file is ESM and
 * jest runs these tests as CommonJS; the loader itself is covered by
 * scripts/verify-naga-wasm.test.mjs.
 */
import React from 'react';
import fs from 'fs';
import path from 'path';
import { TextEncoder as NodeTextEncoder, TextDecoder as NodeTextDecoder } from 'util';

// jsdom ships neither; browsers and Node both have them natively.
if (typeof global.TextEncoder === 'undefined') {
  (global as any).TextEncoder = NodeTextEncoder;
  (global as any).TextDecoder = NodeTextDecoder;
}

import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import ShaderValidator from './ShaderValidator';
import { clearAdoptedRendererDevice } from '../utils/adoptedGpuDevice';

const WASM_PATH = path.join(__dirname, '../../public/wasm/naga_wasm.wasm');

const VALID_WGSL = `
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(1.0, 0.0, 0.0, 1.0));
}
`;

// `let x: i32 = 1.5;` — a type error naga reports with a line and column.
const BROKEN_WGSL = '@compute @workgroup_size(1,1,1)\nfn main() { let x: i32 = 1.5; }';

async function realValidator() {
  const { instance } = await WebAssembly.instantiate(fs.readFileSync(WASM_PATH), {});
  const w = instance.exports as any;
  const heap = () => new Uint8Array(w.memory.buffer);
  return {
    validate(wgsl: string) {
      const bytes = new TextEncoder().encode(wgsl);
      const ptr = w.wgsl_alloc(bytes.length);
      try {
        heap().set(bytes, ptr);
        w.wgsl_validate(ptr, bytes.length);
        const p = w.wgsl_result_ptr();
        const len = w.wgsl_result_len();
        return JSON.parse(new TextDecoder().decode(heap().slice(p, p + len)));
      } finally {
        w.wgsl_free(ptr, bytes.length);
      }
    },
  };
}

// A plain function, not jest.fn(): CRA's jest config sets resetMocks, which
// would strip a jest.fn implementation between tests and hand back undefined.
jest.mock('../utils/nagaWasm', () => {
  const actual = jest.requireActual('../utils/nagaWasm');
  return {
    ...actual,
    loadNagaValidator: () => (global as any).__nagaValidatorPromise,
  };
});

/**
 * runValidation sleeps 20 ms between shaders, so asserting mid-run leaves timers
 * pending and jest reports a leaked worker. Wait for the run to actually finish.
 */
async function settle() {
  await waitFor(() => {
    expect(screen.queryByText(/Validating\.\.\./)).not.toBeInTheDocument();
  });
}

describe('ShaderValidator GPU-less validation', () => {
  const requestAdapter = jest.fn();
  const requestDevice = jest.fn();

  beforeAll(() => {
    (global as any).__nagaValidatorPromise = realValidator();
  });

  beforeEach(() => {
    clearAdoptedRendererDevice();
    delete (window as any).webgpuProbe;

    // No adopted device, and navigator.gpu present only to prove it is untouched.
    const nav = navigator as unknown as { gpu?: unknown };
    nav.gpu = { requestAdapter, requestDevice };

    global.fetch = jest.fn().mockImplementation(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes('/shader-lists/image.json')) {
        return {
          ok: true,
          status: 200,
          json: async () => [
            { id: 'zz-good', name: 'Good Shader', url: 'shaders/zz-good.wgsl' },
            { id: 'zz-broken', name: 'Broken Shader', url: 'shaders/zz-broken.wgsl' },
          ],
        } as Response;
      }
      if (url.includes('/shader-lists/')) {
        return { ok: true, status: 200, json: async () => [] } as Response;
      }
      if (url.includes('zz-broken')) {
        return { ok: true, status: 200, text: async () => BROKEN_WGSL } as Response;
      }
      return { ok: true, status: 200, text: async () => VALID_WGSL } as Response;
    });
  });

  afterEach(() => {
    clearAdoptedRendererDevice();
    jest.clearAllMocks();
  });

  it('fails a broken shader and passes a good one with no GPUDevice at all', async () => {
    render(<ShaderValidator />);
    fireEvent.click(screen.getByText(/Run Full Validation/));

    await waitFor(() => {
      expect(screen.getByText(/Broken Shader/)).toBeInTheDocument();
    });

    // The naga diagnostic, rendered the same way GPU errors are.
    await waitFor(() => {
      expect(screen.getByText(/expected to be `i32`/)).toBeInTheDocument();
    });

    // Never reached for the adapter: validation is entirely GPU-less.
    expect(requestAdapter).not.toHaveBeenCalled();
    expect(requestDevice).not.toHaveBeenCalled();

    await settle();
  });

  it('scores exactly one pass and one failure', async () => {
    const { container } = render(<ShaderValidator />);
    fireEvent.click(screen.getByText(/Run Full Validation/));

    // Both assertions inside one waitFor: the summary updates after every
    // shader, so checking them separately can read a partial tally.
    await waitFor(() => {
      expect(container.textContent).toMatch(/✅ 1 passed/);
      expect(container.textContent).toMatch(/❌ 1 errors/);
    });
    expect(requestAdapter).not.toHaveBeenCalled();

    await settle();
  });
});
