/**
 * Shader search index — decode + cosine ranking. Pure; no ML imports.
 *
 * Built offline by scripts/build-shader-search-index.mjs (see that file for the format).
 * Query vectors come from the lazily loaded CLIP text tower in shaderSearch.worker.ts.
 */

export const SHADER_SEARCH_INDEX_URL = './shader-search-index.json';
export const SHADER_SEARCH_INDEX_VERSION = 1;

export interface ShaderSearchIndexEntry {
  id: string;
  name: string;
  category: string;
  tags: string[];
  description: string;
  hash?: string;
  embedding: string | null;
}

export interface ShaderSearchIndexFile {
  version: number;
  model: string;
  dtype: string;
  dim: number;
  recipe: string;
  count: number;
  mean: string;
  entries: ShaderSearchIndexEntry[];
}

export interface DecodedShaderSearchIndex {
  model: string;
  dtype: string;
  dim: number;
  ids: string[];
  entries: ShaderSearchIndexEntry[];
  mean: Float32Array;
  /** Centered, L2-normalised row per entry; null when the entry has no embedding. */
  vectors: Array<Float32Array | null>;
}

export interface ShaderSearchHit {
  id: string;
  score: number;
}

function base64ToBytes(b64: string): Uint8Array {
  if (typeof atob === 'function') {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  return new Uint8Array(Buffer.from(b64, 'base64'));
}

function normalizeInPlace(v: Float32Array): Float32Array {
  let n = 0;
  for (let i = 0; i < v.length; i++) n += v[i] * v[i];
  n = Math.sqrt(n) || 1;
  for (let i = 0; i < v.length; i++) v[i] /= n;
  return v;
}

/** Subtract the catalog mean and L2-normalise. Used for both documents and queries. */
export function centerVector(raw: ArrayLike<number>, mean: Float32Array): Float32Array {
  const out = new Float32Array(mean.length);
  let n = 0;
  for (let i = 0; i < raw.length; i++) n += raw[i] * raw[i];
  n = Math.sqrt(n) || 1;
  for (let i = 0; i < mean.length; i++) out[i] = raw[i] / n - mean[i];
  return normalizeInPlace(out);
}

export function decodeShaderSearchIndex(file: ShaderSearchIndexFile): DecodedShaderSearchIndex {
  if (file.version !== SHADER_SEARCH_INDEX_VERSION) {
    throw new Error(`Unsupported shader search index version ${file.version}`);
  }
  const meanBytes = base64ToBytes(file.mean);
  const mean = new Float32Array(meanBytes.buffer.slice(meanBytes.byteOffset, meanBytes.byteOffset + meanBytes.byteLength));
  const vectors = file.entries.map(entry => {
    if (!entry.embedding) return null;
    const bytes = base64ToBytes(entry.embedding);
    return centerVector(new Int8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength), mean);
  });
  return {
    model: file.model,
    dtype: file.dtype,
    dim: file.dim,
    ids: file.entries.map(e => e.id),
    entries: file.entries,
    mean,
    vectors,
  };
}

/** Lexical bonus so exact name/id hits never rank below today's substring filter. */
export const LEXICAL_BONUS = 0.25;

function foldSeparators(text: string): string {
  return text.toLowerCase().replace(/[-_\s]+/g, ' ').trim();
}

function lexicalMatch(entry: ShaderSearchIndexEntry, query: string): boolean {
  const q = foldSeparators(query);
  if (!q) return false;
  return foldSeparators(entry.name).includes(q) || foldSeparators(entry.id).includes(q);
}

export interface RankOptions {
  topK?: number;
  /** Restrict to these ids (e.g. the options the picker was given). */
  allowIds?: ReadonlySet<string>;
  /** Raw query text, for the lexical bonus. */
  queryText?: string;
}

/** Cosine top-k over the centered index. `rawQuery` is the un-centered CLIP text embedding. */
export function rankShaderSearch(
  index: DecodedShaderSearchIndex,
  rawQuery: ArrayLike<number>,
  { topK = 60, allowIds, queryText }: RankOptions = {},
): ShaderSearchHit[] {
  const q = centerVector(rawQuery, index.mean);
  const hits: ShaderSearchHit[] = [];
  for (let i = 0; i < index.entries.length; i++) {
    const entry = index.entries[i];
    if (allowIds && !allowIds.has(entry.id)) continue;
    const v = index.vectors[i];
    let score = 0;
    if (v) {
      for (let j = 0; j < q.length; j++) score += v[j] * q[j];
    }
    if (queryText && lexicalMatch(entry, queryText)) score += LEXICAL_BONUS;
    if (v || score > 0) hits.push({ id: entry.id, score });
  }
  hits.sort((a, b) => b.score - a.score);
  return hits.slice(0, topK);
}

/** Today's picker behaviour; used whenever the index or the encoder is unavailable. */
export function substringFilter<T extends { id: string; name: string }>(items: T[], query: string): T[] {
  const q = query.trim().toLowerCase();
  if (!q) return items;
  return items.filter(o => o.name.toLowerCase().includes(q) || o.id.toLowerCase().includes(q));
}
