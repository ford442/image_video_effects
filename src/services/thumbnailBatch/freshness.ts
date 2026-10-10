/**
 * Thumbnail freshness — which shaders need a new thumbnail.
 *
 * Compares public/thumbnails/source-hashes.json (generated in prestart/prebuild by
 * scripts/build-shader-source-hashes.js) with public/thumbnails/manifest.json.
 * Mirrors thumbnailFreshness() in scripts/lib/shaderSourceHash.js.
 */

export interface ThumbnailManifestEntry {
  thumbnail_url: string;
  generated_at: string;
  params_snapshot?: number[];
  source_hash?: string | null;
  engine?: string;
}

export type ThumbnailManifest = Record<string, ThumbnailManifestEntry>;

export interface UpgradeRecord {
  date: string;
  note: string | null;
  count: number;
}

export interface SourceHashFile {
  generated_at: string;
  algorithm: string;
  hashes: Record<string, string>;
  upgrades: Record<string, UpgradeRecord>;
  /** reports/thumbnail_skip_allowlist.json ids — never queued for capture. */
  skip?: string[];
}

/**
 * missing — no thumbnail recorded
 * unknown — thumbnail predates source hashing, or the shader has no hash yet
 * stale   — shader source changed after the thumbnail was captured
 * fresh   — thumbnail matches the current source
 */
export type ThumbnailFreshness = 'missing' | 'unknown' | 'stale' | 'fresh';

export interface ThumbnailState {
  hashes: SourceHashFile | null;
  manifest: ThumbnailManifest;
}

export function freshnessFor(id: string, state: ThumbnailState): ThumbnailFreshness {
  const entry = state.manifest[id];
  if (!entry) return 'missing';
  const current = state.hashes?.hashes[id];
  if (!entry.source_hash || !current) return 'unknown';
  return entry.source_hash === current ? 'fresh' : 'stale';
}

export function isSkipped(id: string, state: ThumbnailState): boolean {
  return state.hashes?.skip?.includes(id) ?? false;
}

/** Missing / unknown / stale and not on the skip allowlist. */
export function needsThumbnail(id: string, state: ThumbnailState): boolean {
  return !isSkipped(id, state) && freshnessFor(id, state) !== 'fresh';
}

async function fetchJson<T>(url: string): Promise<T | null> {
  try {
    const res = await fetch(url, { cache: 'no-store' });
    if (!res.ok) return null;
    return (await res.json()) as T;
  } catch {
    return null;
  }
}

/** Loads both files from the app's own origin (public/thumbnails). */
export async function loadThumbnailState(manifestOverride?: ThumbnailManifest): Promise<ThumbnailState> {
  const [hashes, manifest] = await Promise.all([
    fetchJson<SourceHashFile>('./thumbnails/source-hashes.json'),
    manifestOverride ? Promise.resolve(manifestOverride) : fetchJson<ThumbnailManifest>('./thumbnails/manifest.json'),
  ]);
  return { hashes, manifest: manifest ?? {} };
}

export function summarizeFreshness(ids: string[], state: ThumbnailState): Record<ThumbnailFreshness, number> {
  const out: Record<ThumbnailFreshness, number> = { missing: 0, unknown: 0, stale: 0, fresh: 0 };
  for (const id of ids) out[freshnessFor(id, state)]++;
  return out;
}
