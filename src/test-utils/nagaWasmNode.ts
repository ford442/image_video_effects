/**
 * The real public/wasm/naga_wasm.wasm, instantiated for jest.
 *
 * The ABI is re-implemented here rather than imported from public/wasm/naga_wasm.js
 * because that file is ESM and jest runs tests as CommonJS; the loader itself is
 * covered by scripts/verify-naga-wasm.test.mjs.
 *
 * Lives outside __tests__/ because CRA would otherwise run it as an empty suite.
 */
import { readFileSync } from 'fs';
import { resolve } from 'path';
import { TextDecoder as NodeTextDecoder, TextEncoder as NodeTextEncoder } from 'util';
import type { NagaGlslConverter, NagaValidator } from '../utils/nagaWasm';

export const NAGA_WASM_PATH = resolve(__dirname, '../../public/wasm/naga_wasm.wasm');

const GLSL_STAGES = { vertex: 0, fragment: 1, compute: 2 } as const;

export async function loadRealNaga(): Promise<NagaValidator & NagaGlslConverter> {
  const { instance } = await WebAssembly.instantiate(readFileSync(NAGA_WASM_PATH), {});
  const w = instance.exports as any;
  // jsdom ships neither TextEncoder nor TextDecoder.
  const encoder = new NodeTextEncoder();
  const decoder = new NodeTextDecoder();
  const heap = () => new Uint8Array(w.memory.buffer);

  const run = (source: string, call: (ptr: number, len: number) => void) => {
    const bytes = encoder.encode(source);
    const ptr = w.wgsl_alloc(bytes.length);
    try {
      heap().set(bytes, ptr);
      call(ptr, bytes.length);
      const p = w.wgsl_result_ptr();
      const len = w.wgsl_result_len();
      return JSON.parse(decoder.decode(heap().slice(p, p + len)));
    } finally {
      w.wgsl_free(ptr, bytes.length);
    }
  };

  return {
    validate: (wgsl) => run(wgsl, (ptr, len) => w.wgsl_validate(ptr, len)),
    glslToWgsl: (glsl, stage = 'fragment') =>
      run(glsl, (ptr, len) => w.glsl_to_wgsl(ptr, len, GLSL_STAGES[stage])),
  };
}
