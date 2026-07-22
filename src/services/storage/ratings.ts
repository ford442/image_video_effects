/**
 * Shader rating endpoints — POST /api/shaders/{id}/rate
 *
 * Live storage API expects JSON `{ rating, notes? }` (ShaderRatingUpdate).
 * Play recording (`/play`) is not deployed on production — no-op with warn.
 */

import { encodeResourcePath, fetchJson } from './http';
import { postShaderRating } from '../postShaderRating';
import type { RateShaderResponse, ShaderItem, ShaderRatingInfo, StorageClientConfig } from './types';
import { getShaderMeta } from './shaders';

export async function rateShader(
  config: StorageClientConfig,
  shaderId: string,
  stars: number,
  notes?: string
): Promise<RateShaderResponse> {
  const id = shaderId.replace(/\.json$/, '');
  const normalized = await postShaderRating(config.apiUrl, id, stars, {
    notes: notes ?? null,
  });

  return {
    id: normalized.id,
    stars: normalized.stars,
    rating_count: normalized.rating_count,
    your_rating: normalized.your_rating,
  };
}

/** Rating summary derived from shader metadata (no dedicated /rating route required). */
export async function getShaderRating(
  config: StorageClientConfig,
  shaderId: string
): Promise<ShaderRatingInfo> {
  const meta: ShaderItem = await getShaderMeta(config, shaderId);
  return {
    id: meta.id,
    rating: meta.stars ?? meta.rating ?? 0,
    date: meta.date,
    has_errors: meta.has_errors ?? false,
    rating_count: meta.rating_count,
    play_count: meta.play_count,
  };
}

/**
 * Record a shader play.
 *
 * Production OpenAPI has no `/api/shaders/{id}/play` (only songs/preset-packs).
 * Soft-fail so missing routes never surface as console load failures.
 */
export async function recordShaderPlay(
  config: StorageClientConfig,
  shaderId: string
): Promise<{ success: boolean; id: string; play_count: number; last_played: string } | null> {
  const encoded = encodeResourcePath(shaderId.replace(/\.json$/, ''));
  try {
    return await fetchJson(`${config.apiUrl}/api/shaders/${encoded}/play`, { method: 'POST' });
  } catch (err) {
    // 404 = route or shader missing on this backend revision — not a load failure.
    if (process.env.NODE_ENV !== 'production') {
      console.debug('[storage] recordShaderPlay skipped:', shaderId, err);
    }
    return null;
  }
}
