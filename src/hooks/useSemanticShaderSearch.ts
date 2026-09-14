import { useEffect, useState } from 'react';
import type { ShaderSearchHit } from '../services/shaderSearch/semanticIndex';

export type SemanticSearchStatus = 'off' | 'loading' | 'ready' | 'unavailable';

export interface SemanticShaderSearchResult {
  status: SemanticSearchStatus;
  /** Ranked hits for the current query, or null → caller uses the substring filter. */
  hits: ShaderSearchHit[] | null;
}

const DEBOUNCE_MS = 250;
const MIN_QUERY_CHARS = 3;

/**
 * CLIP-backed picker search. Opt-in: nothing (index, worker, model) loads until
 * `enabled` is true. Any failure reports `unavailable` and returns null hits so the
 * picker keeps its substring filter.
 */
export function useSemanticShaderSearch(
  query: string,
  enabled: boolean,
  allowIds: string[],
  topK = 60,
): SemanticShaderSearchResult {
  const [status, setStatus] = useState<SemanticSearchStatus>('off');
  const [hits, setHits] = useState<ShaderSearchHit[] | null>(null);

  useEffect(() => {
    if (!enabled) {
      setStatus('off');
      return;
    }
    let cancelled = false;
    setStatus(s => (s === 'ready' ? s : 'loading'));
    import('../services/shaderSearch/shaderSearchClient')
      .then(({ getShaderSearchClient }) => {
        const client = getShaderSearchClient();
        if (!client) throw new Error('semantic search unsupported');
        return client.warmup();
      })
      .then(() => !cancelled && setStatus('ready'))
      .catch(err => {
        console.warn('[shader-search] falling back to substring filter:', err);
        if (!cancelled) setStatus('unavailable');
      });
    return () => {
      cancelled = true;
    };
  }, [enabled]);

  const trimmed = query.trim();
  const allowKey = allowIds.join('\n');

  useEffect(() => {
    if (status !== 'ready' || trimmed.length < MIN_QUERY_CHARS) {
      setHits(null);
      return;
    }
    let cancelled = false;
    const timer = window.setTimeout(() => {
      import('../services/shaderSearch/shaderSearchClient')
        .then(({ getShaderSearchClient }) =>
          getShaderSearchClient()?.search(trimmed, { topK, allowIds: allowKey ? allowKey.split('\n') : undefined }),
        )
        .then(result => !cancelled && setHits(result ?? null))
        .catch(() => !cancelled && setHits(null));
    }, DEBOUNCE_MS);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [status, trimmed, allowKey, topK]);

  return { status, hits };
}
