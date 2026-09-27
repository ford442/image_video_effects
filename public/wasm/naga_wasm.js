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

const DEFAULT_WASM_URL = '/wasm/naga_wasm.wasm';

/**
 * Instantiate the validator.
 *
 * @param {Object} [options]
 * @param {BufferSource} [options.bytes]  Pre-read wasm bytes (Node reads the file itself).
 * @param {string} [options.url]          URL to fetch instead; defaults to /wasm/naga_wasm.wasm.
 * @returns {Promise<{ validate: (wgsl: string) => NagaDiagnostic }>}
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

  function validate(wgsl) {
    const bytes = encoder.encode(wgsl);
    const ptr = wasm.wgsl_alloc(bytes.length);
    if (!ptr) throw new Error('naga_wasm: allocation failed');
    try {
      heap().set(bytes, ptr);
      wasm.wgsl_validate(ptr, bytes.length);
      const resultPtr = wasm.wgsl_result_ptr();
      const resultLen = wasm.wgsl_result_len();
      // slice() copies: the buffer is reused by the next validate().
      const json = decoder.decode(heap().slice(resultPtr, resultPtr + resultLen));
      return JSON.parse(json);
    } finally {
      wasm.wgsl_free(ptr, bytes.length);
    }
  }

  return { validate };
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
