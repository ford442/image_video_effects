import type { ShaderSearchHit } from './semanticIndex';

export type ShaderSearchRequest =
  | { type: 'init'; requestId: number; indexUrl?: string }
  | {
      type: 'query';
      requestId: number;
      indexUrl?: string;
      query: string;
      topK?: number;
      allowIds?: string[];
    };

export type ShaderSearchResponse =
  | { type: 'ready'; requestId: number; count: number }
  | { type: 'results'; requestId: number; query: string; hits: ShaderSearchHit[] }
  | { type: 'error'; requestId: number; message: string };
