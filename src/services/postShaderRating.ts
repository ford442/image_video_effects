/**
 * POST /api/shaders/{id}/rate against storage.noahcohn.com.
 *
 * Live API contract (OpenAPI ShaderRatingUpdate):
 *   Content-Type: application/json
 *   body: { rating: 0–5, notes?: string | null }
 *
 * Response shape varies by backend revision; normalize to a stable client form.
 */

export interface PostShaderRatingOptions {
  notes?: string | null;
  /** Optional client-side dedupe token (ignored by current live schema). */
  idempotencyKey?: string;
}

export interface NormalizedShaderRating {
  id: string;
  stars: number;
  rating_count: number;
  your_rating: number;
  has_errors?: boolean;
  message?: string;
}

function clampRating(rating: number): number {
  if (!Number.isFinite(rating)) {
    throw new RangeError('Rating must be a finite number');
  }
  const n = Math.round(rating);
  if (n < 0 || n > 5) {
    throw new RangeError('Rating must be between 0 and 5');
  }
  return n;
}

/**
 * Normalize heterogeneous rate-endpoint payloads into { id, stars, ... }.
 */
export function normalizeShaderRatingResponse(
  shaderId: string,
  payload: unknown,
  fallbackRating: number,
): NormalizedShaderRating {
  const data = (payload && typeof payload === 'object')
    ? (payload as Record<string, unknown>)
    : {};

  const starsRaw = data.stars ?? data.rating ?? fallbackRating;
  const stars = typeof starsRaw === 'number' ? starsRaw : fallbackRating;

  const countRaw = data.rating_count;
  const rating_count = typeof countRaw === 'number' ? countRaw : 0;

  const yoursRaw = data.your_rating ?? data.rating ?? fallbackRating;
  const your_rating = typeof yoursRaw === 'number' ? yoursRaw : fallbackRating;

  const idRaw = data.id ?? data.shader_id ?? shaderId;
  const id = typeof idRaw === 'string' ? idRaw : shaderId;

  return {
    id,
    stars,
    rating_count,
    your_rating,
    has_errors: typeof data.has_errors === 'boolean' ? data.has_errors : undefined,
    message: typeof data.message === 'string' ? data.message : undefined,
  };
}

/**
 * Submit a shader star rating as JSON (production storage API).
 */
export async function postShaderRating(
  apiBaseUrl: string,
  shaderId: string,
  rating: number,
  options?: PostShaderRatingOptions,
): Promise<NormalizedShaderRating> {
  const value = clampRating(rating);
  const base = apiBaseUrl.replace(/\/$/, '');
  const body: Record<string, unknown> = { rating: value };

  if (options?.notes !== undefined) {
    body.notes = options.notes;
  }
  if (options?.idempotencyKey) {
    body.idempotency_key = options.idempotencyKey;
  }

  const response = await fetch(`${base}/api/shaders/${encodeURIComponent(shaderId)}/rate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    throw new Error(`Rating failed (${response.status})`);
  }

  let payload: unknown = null;
  try {
    payload = await response.json();
  } catch {
    payload = null;
  }

  return normalizeShaderRatingResponse(shaderId, payload, value);
}
