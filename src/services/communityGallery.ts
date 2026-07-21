/**
 * Community Preset-Pack Gallery API client.
 *
 * Publishes and fetches shared shader chains from the FastAPI storage backend.
 * All wire-format encoding/decoding routes through layerChainShare.ts so the
 * SharedChain contract stays single-source.
 */

import { STORAGE_API_URL } from '../config/appConfig';
import { encodeChain, decodeChain, SharedChain } from './layerChainShare';

const API_BASE = STORAGE_API_URL;

export interface CommunityPack {
  id: string;
  name: string;
  description: string;
  author: string;
  date: string;
  chain: string;
  play_count: number;
}

export interface PublishPackInput {
  name: string;
  description?: string;
  author?: string;
  chain: SharedChain;
}

export interface PublishPackResponse {
  success: boolean;
  id: string;
  pack: CommunityPack;
}

export interface ListCommunityPacksResponse {
  total: number;
  limit: number;
  offset: number;
  packs: CommunityPack[];
}

function getHeaders(): Record<string, string> {
  return {
    Accept: 'application/json',
    'Content-Type': 'application/json',
  };
}

async function handleResponse<T>(res: Response): Promise<T> {
  if (!res.ok) {
    let detail: string | undefined;
    try {
      const body = await res.json();
      detail = body.detail ?? body.error ?? JSON.stringify(body);
    } catch {
      detail = res.statusText;
    }
    throw new Error(`Preset pack API error ${res.status}: ${detail}`);
  }
  return res.json() as Promise<T>;
}

/**
 * Publish a SharedChain to the community gallery.
 * The chain is encoded via encodeChain() before being sent over the wire.
 */
export async function publishPack(input: PublishPackInput): Promise<PublishPackResponse> {
  const encoded = encodeChain(input.chain);
  const res = await fetch(`${API_BASE}/api/preset-packs`, {
    method: 'POST',
    headers: getHeaders(),
    body: JSON.stringify({
      name: input.name,
      description: input.description ?? '',
      author: input.author ?? 'Anonymous',
      chain: encoded,
    }),
  });
  return handleResponse<PublishPackResponse>(res);
}

/**
 * List published community packs.
 */
export async function listCommunityPacks(
  options: { limit?: number; offset?: number; sortBy?: 'date' | 'play_count' } = {}
): Promise<ListCommunityPacksResponse> {
  const params = new URLSearchParams();
  if (options.limit !== undefined) params.set('limit', String(options.limit));
  if (options.offset !== undefined) params.set('offset', String(options.offset));
  if (options.sortBy) params.set('sort_by', options.sortBy);
  const query = params.toString();
  const res = await fetch(`${API_BASE}/api/preset-packs${query ? `?${query}` : ''}`, {
    method: 'GET',
    headers: getHeaders(),
  });
  return handleResponse<ListCommunityPacksResponse>(res);
}

/**
 * Fetch a single community pack by id.
 */
export async function getCommunityPack(id: string): Promise<CommunityPack> {
  const res = await fetch(`${API_BASE}/api/preset-packs/${encodeURIComponent(id)}`, {
    method: 'GET',
    headers: getHeaders(),
  });
  return handleResponse<CommunityPack>(res);
}

/**
 * Record that a community pack was played/applied.
 */
export async function recordPresetPackPlay(id: string): Promise<{ success: boolean; id: string; play_count: number; last_played: string }> {
  const res = await fetch(`${API_BASE}/api/preset-packs/${encodeURIComponent(id)}/play`, {
    method: 'POST',
    headers: getHeaders(),
  });
  return handleResponse(res);
}

/**
 * Convenience helper: fetch a pack and decode its chain.
 * Returns null if the stored chain does not decode (should not happen for
 * packs published through this client, but defends against data corruption).
 */
export async function getCommunityPackWithDecodedChain(
  id: string
): Promise<{ pack: CommunityPack; chain: SharedChain } | null> {
  const pack = await getCommunityPack(id);
  const chain = decodeChain(pack.chain);
  if (!chain) return null;
  return { pack, chain };
}

export { encodeChain, decodeChain };
export type { SharedChain };
