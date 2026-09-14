/* eslint-disable no-restricted-globals */
/**
 * Shader search worker — owns the CLIP text tower and the decoded index.
 *
 * Transformers loads only through aiModels/transformersLoader (dynamic import). The text
 * tower runs on WASM/CPU: never `device: 'webgpu'`, which could create a second GPUDevice
 * while the canvas renderer is live.
 */

import { loadTransformersModule } from '../aiModels/transformersLoader';
import {
  decodeShaderSearchIndex,
  rankShaderSearch,
  SHADER_SEARCH_INDEX_URL,
  type DecodedShaderSearchIndex,
  type ShaderSearchIndexFile,
} from './semanticIndex';
import type { ShaderSearchRequest, ShaderSearchResponse } from './shaderSearchProtocol';

declare let __webpack_public_path__: string;

// CRA builds with a relative public path ("homepage": "."), which webpack resolves
// against this worker's own URL (static/js/). Re-anchor chunk loads and the index
// fetch at the app root before the transformers chunk is requested.
const APP_BASE = new URL('../../', self.location.href).href;
if (process.env.NODE_ENV === 'production') {
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  __webpack_public_path__ = APP_BASE;
}

type EncodeFn = (text: string) => Promise<Float32Array>;

let ready: Promise<{ index: DecodedShaderSearchIndex; encode: EncodeFn }> | null = null;

async function init(indexUrl: string) {
  const res = await fetch(indexUrl);
  if (!res.ok) throw new Error(`index fetch ${res.status}`);
  const index = decodeShaderSearchIndex((await res.json()) as ShaderSearchIndexFile);

  const { AutoTokenizer, CLIPTextModelWithProjection } = await loadTransformersModule();
  const tokenizer = await AutoTokenizer.from_pretrained(index.model);
  const model = await CLIPTextModelWithProjection.from_pretrained(index.model, {
    dtype: index.dtype as 'q8',
    device: 'wasm',
  });
  const encode: EncodeFn = async text => {
    const inputs = tokenizer([text], { padding: true, truncation: true });
    const { text_embeds } = await model(inputs);
    return Float32Array.from(text_embeds.data as ArrayLike<number>);
  };
  return { index, encode };
}

function post(message: ShaderSearchResponse) {
  (self as unknown as Worker).postMessage(message);
}

self.addEventListener('message', async (event: MessageEvent<ShaderSearchRequest>) => {
  const msg = event.data;
  if (!ready) {
    ready = init(new URL(msg.indexUrl || SHADER_SEARCH_INDEX_URL, APP_BASE).href);
    ready.catch(() => {
      ready = null;
    });
  }
  try {
    const { index, encode } = await ready;
    if (msg.type === 'init') {
      post({ type: 'ready', requestId: msg.requestId, count: index.entries.length });
      return;
    }
    const vector = await encode(msg.query);
    const hits = rankShaderSearch(index, vector, {
      topK: msg.topK,
      queryText: msg.query,
      allowIds: msg.allowIds ? new Set(msg.allowIds) : undefined,
    });
    post({ type: 'results', requestId: msg.requestId, query: msg.query, hits });
  } catch (err) {
    post({ type: 'error', requestId: msg.requestId, message: err instanceof Error ? err.message : String(err) });
  }
});

export {};
