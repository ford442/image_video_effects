/**
 * Shader rating endpoints — POST /api/shaders/{id}/rate
 */

import { encodeResourcePath, fetchJson, mapHttpError } from './http';
import type { RateShaderResponse, ShaderItem, ShaderRatingInfo, StorageClientConfig } from './types';
import { getShaderMeta } from './shaders';

export async function rateShader(
  config: StorageClientConfig,
  shaderId: string,
  stars: number,
  _notes?: string
): Promise<RateShaderResponse> {
  const encoded = encodeResourcePath(shaderId.replace(/\.json$/, ''));
  const form = new FormData();
  form.append('stars', String(stars));

  const response = await fetch(`${config.apiUrl}/api/shaders/${encoded}/rate`, {
    method: 'POST',
    body: form,
  });

  if (!response.ok) {
    throw await mapHttpError(response);
  }

  return response.json() as Promise<RateShaderResponse>;
}

/** Rating summary derived from shader metadata (no dedicated /rating route on backend). */
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

export async function recordShaderPlay(
  config: StorageClientConfig,
  shaderId: string
): Promise<{ success: boolean; id: string; play_count: number; last_played: string }> {
  const encoded = encodeResourcePath(shaderId.replace(/\.json$/, ''));
  return fetchJson(`${config.apiUrl}/api/shaders/${encoded}/play`, { method: 'POST' });
}
