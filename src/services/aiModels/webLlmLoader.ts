/**
 * Lazy loader for @mlc-ai/web-llm — only fetched when AutoDJ / LLM features initialize.
 */

export type WebLlmModule = typeof import('@mlc-ai/web-llm');

let modulePromise: Promise<WebLlmModule> | null = null;

export function loadWebLlmModule(): Promise<WebLlmModule> {
  if (!modulePromise) {
    modulePromise = import(/* webpackChunkName: "web-llm" */ '@mlc-ai/web-llm');
  }
  return modulePromise;
}

/** Reset cache — for tests only. */
export function resetWebLlmModuleCache(): void {
  modulePromise = null;
}
