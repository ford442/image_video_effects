/**
 * Main-thread client for the shader search worker.
 *
 * Imported only via dynamic import from useSemanticShaderSearch so the worker URL
 * (import.meta.url) never enters the main chunk or Jest's module graph.
 */

import type { ShaderSearchHit } from './semanticIndex';
import type { ShaderSearchRequest, ShaderSearchResponse } from './shaderSearchProtocol';

// Minimal module using a SIMD opcode; onnxruntime-web's fast path needs it.
const SIMD_PROBE = new Uint8Array([
  0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 96, 0, 1, 123, 3, 2, 1, 0, 10, 10, 1, 8, 0, 65, 0, 253, 15, 253, 98, 11,
]);

export function supportsSemanticSearch(): boolean {
  try {
    return (
      typeof Worker !== 'undefined' &&
      typeof WebAssembly !== 'undefined' &&
      WebAssembly.validate(SIMD_PROBE)
    );
  } catch {
    return false;
  }
}

export interface ShaderSearchClient {
  warmup(): Promise<number>;
  search(query: string, opts?: { topK?: number; allowIds?: string[] }): Promise<ShaderSearchHit[]>;
  dispose(): void;
}

let singleton: ShaderSearchClient | null = null;

export function getShaderSearchClient(): ShaderSearchClient | null {
  if (singleton) return singleton;
  if (!supportsSemanticSearch()) return null;

  const worker = new Worker(new URL('./shaderSearch.worker.ts', import.meta.url));
  let nextId = 1;
  const pending = new Map<number, { resolve: (r: ShaderSearchResponse) => void; reject: (e: Error) => void }>();

  worker.addEventListener('message', (event: MessageEvent<ShaderSearchResponse>) => {
    const entry = pending.get(event.data.requestId);
    if (!entry) return;
    pending.delete(event.data.requestId);
    if (event.data.type === 'error') entry.reject(new Error(event.data.message));
    else entry.resolve(event.data);
  });
  worker.addEventListener('error', event => {
    for (const { reject } of pending.values()) reject(new Error(event.message || 'shader search worker failed'));
    pending.clear();
  });

  // Distributive Omit so each request variant keeps its own fields.
  type RequestBody = ShaderSearchRequest extends infer R ? (R extends unknown ? Omit<R, 'requestId'> : never) : never;
  const send = (request: RequestBody) =>
    new Promise<ShaderSearchResponse>((resolve, reject) => {
      const requestId = nextId++;
      pending.set(requestId, { resolve, reject });
      worker.postMessage({ ...request, requestId } as ShaderSearchRequest);
    });

  singleton = {
    async warmup() {
      const res = await send({ type: 'init' });
      return res.type === 'ready' ? res.count : 0;
    },
    async search(query, opts = {}) {
      const res = await send({ type: 'query', query, ...opts });
      return res.type === 'results' ? res.hits : [];
    },
    dispose() {
      worker.terminate();
      pending.clear();
      singleton = null;
    },
  };
  return singleton;
}
