import type { Plugin } from 'vite';

// onnxruntime-web's bundle references its wasm as `new URL("ort-wasm-….wasm", import.meta.url)`,
// which makes Vite copy a 27 MB binary into the build per bundle that includes it. It is never
// loaded from there: transformers.js pins `env.backends.onnx.wasm.wasmPaths` to the jsDelivr copy
// of the same onnxruntime-web version (see src/services/aiModels/transformersLoader.ts), exactly
// as the CRA build behaved. Wrapping the literal keeps Vite's static URL analysis from matching it.
const ORT_URL = /new URL\((["'])(ort-wasm-[\w.-]+\.(?:wasm|mjs))\1,\s*import\.meta\.url\)/g;

export function ortWasmPlugin(): Plugin {
  return {
    name: 'pixelocity:ort-wasm-no-emit',
    enforce: 'pre',
    transform(code, id) {
      if (!id.includes('onnxruntime-web') || !code.includes('ort-wasm-')) return null;
      const out = code.replace(ORT_URL, (_m, quote: string, file: string) => `new URL(String(${quote}${file}${quote}),import.meta.url)`);
      return out === code ? null : { code: out, map: null };
    },
  };
}
