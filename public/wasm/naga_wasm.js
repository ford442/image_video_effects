// HAND-WRITTEN — not emitted by scripts/emit-wasm-bridge.mjs.
//
// The only supported caller of tools/naga_wasm. One module serves both
// consumers so the ABI cannot drift between them:
//   browser  await import(/* webpackIgnore: true */ '/wasm/naga_wasm.js')
//   node     await import(pathToFileURL('public/wasm/naga_wasm.js'))
//
// Keep in sync with tools/naga_wasm/src/lib.rs. Rebuild both together via
// tools/naga_wasm/build.sh.

/**
 * @typedef {Object} NagaDiagnostic
 * @property {boolean} ok
 * @property {'parse'|'validate'|'encoding'} [kind]
 * @property {string} [message]  Full rendered diagnostic, including the source excerpt.
 * @property {number} [line]     1-based; 0 when naga could not place the error.
 * @property {number} [pos]      1-based column.
 */

/**
 * @typedef {Object} NagaGlslResult
 * @property {boolean} ok
 * @property {string} [wgsl]     Translated module when ok.
 * @property {'parse'|'validate'|'write'|'encoding'} [kind]
 * @property {string} [message]
 * @property {number} [line]
 * @property {number} [pos]
 */

const GLSL_STAGES = { vertex: 0, fragment: 1, compute: 2 };

const DEFAULT_WASM_URL = '/wasm/naga_wasm.wasm';

/**
 * Instantiate the validator.
 *
 * @param {Object} [options]
 * @param {BufferSource} [options.bytes]  Pre-read wasm bytes (Node reads the file itself).
 * @param {string} [options.url]          URL to fetch instead; defaults to /wasm/naga_wasm.wasm.
 * @returns {Promise<{
 *   validate: (wgsl: string) => NagaDiagnostic,
 *   glslToWgsl: (glsl: string, stage?: 'vertex'|'fragment'|'compute') => NagaGlslResult,
 * }>}
 */
export async function createNagaValidator(options = {}) {
  const { instance } = options.bytes
    ? await WebAssembly.instantiate(options.bytes, {})
    : await instantiateFromUrl(options.url ?? DEFAULT_WASM_URL);

  const wasm = instance.exports;
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  // The heap detaches on memory growth, so re-view it after every call that
  // can allocate rather than caching a Uint8Array.
  const heap = () => new Uint8Array(wasm.memory.buffer);

  /** Copies `source` into wasm memory, runs `call(ptr, len)`, returns the parsed JSON result. */
  function run(source, call) {
    const bytes = encoder.encode(source);
    const ptr = wasm.wgsl_alloc(bytes.length);
    if (!ptr) throw new Error('naga_wasm: allocation failed');
    try {
      heap().set(bytes, ptr);
      call(ptr, bytes.length);
      const resultPtr = wasm.wgsl_result_ptr();
      const resultLen = wasm.wgsl_result_len();
      // slice() copies: the buffer is reused by the next call.
      const json = decoder.decode(heap().slice(resultPtr, resultPtr + resultLen));
      return JSON.parse(json);
    } finally {
      wasm.wgsl_free(ptr, bytes.length);
    }
  }

  function validate(wgsl) {
    return run(wgsl, (ptr, len) => wasm.wgsl_validate(ptr, len));
  }

  function glslToWgsl(glsl, stage = 'fragment') {
    if (typeof wasm.glsl_to_wgsl !== 'function') {
      throw new Error('naga_wasm: artifact has no glsl_to_wgsl export — rebuild with tools/naga_wasm/build.sh');
    }
    const stageId = GLSL_STAGES[stage] ?? GLSL_STAGES.fragment;
    return run(glsl, (ptr, len) => wasm.glsl_to_wgsl(ptr, len, stageId));
  }

  return { validate, glslToWgsl };
}

async function instantiateFromUrl(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`naga_wasm: fetch ${url} failed with HTTP ${response.status}`);
  }
  if (typeof WebAssembly.instantiateStreaming === 'function') {
    try {
      // clone(): instantiateStreaming consumes the body, so the fallback below
      // needs its own copy to read.
      return await WebAssembly.instantiateStreaming(response.clone(), {});
    } catch {
      // Falls through: some servers mis-serve the MIME type as
      // application/octet-stream, which instantiateStreaming rejects.
    }
  }
  return WebAssembly.instantiate(await response.arrayBuffer(), {});
}
