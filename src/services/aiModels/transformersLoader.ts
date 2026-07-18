/**
 * Lazy loader for @xenova/transformers — keeps heavy ONNX/WASM out of the main bundle.
 *
 * Security note (#873): models load from Hugging Face CDN at runtime only when the user
 * triggers depth or AutoDJ. Playground default path never downloads ML weights.
 * Treat CDN as trusted only on networks you control; restricted VMs show offline UX.
 */

let modulePromise: Promise<typeof import('@xenova/transformers')> | null = null;
let configured = false;

export function loadTransformersModule(): Promise<typeof import('@xenova/transformers')> {
  if (!modulePromise) {
    modulePromise = import(/* webpackChunkName: "transformers" */ '@xenova/transformers');
  }
  return modulePromise.then(mod => {
    if (!configured) {
      configureTransformersEnv(mod.env);
      configured = true;
    }
    return mod;
  });
}

function configureTransformersEnv(env: typeof import('@xenova/transformers').env): void {
  env.allowLocalModels = false;
  env.backends.onnx.logLevel = 'warning';
  env.useBrowserCache = true;
}

/** Reset cache — for tests only. */
export function resetTransformersModuleCache(): void {
  modulePromise = null;
  configured = false;
}
