/**
 * renderWorkerSpawn.ts — the only module that references the worker URL.
 * Reached by dynamic import, so `import.meta` stays out of the main chunk
 * and out of Jest (same pattern as the shader-search worker).
 */

export function spawnRenderWorker(): Worker {
  return new Worker(/* webpackChunkName: "render-worker" */ new URL('./render.worker.ts', import.meta.url));
}
