import { useEffect, useState, useCallback } from 'react';

export interface ThumbnailManifestEntry {
  thumbnail_url: string;
  generated_at?: string;
  params_snapshot?: number[];
}

export type ThumbnailManifest = Record<string, ThumbnailManifestEntry>;

const MANIFEST_URL = './thumbnails/manifest.json';
const UNHEALTHY_URL = './thumbnails/unhealthy.json';

let cachedManifest: ThumbnailManifest | null = null;
let cachedUnhealthy: Set<string> | null = null;
let loadPromise: Promise<{ manifest: ThumbnailManifest; unhealthy: Set<string> }> | null = null;

export function parseUnhealthyIds(data: unknown): Set<string> {
  if (Array.isArray(data)) {
    return new Set(data.filter((id): id is string => typeof id === 'string'));
  }
  if (data && typeof data === 'object' && Array.isArray((data as { ids?: unknown }).ids)) {
    return new Set((data as { ids: unknown[] }).ids.filter((id): id is string => typeof id === 'string'));
  }
  return new Set();
}

export function hasThumbnailInManifest(manifest: ThumbnailManifest, id: string): boolean {
  return Boolean(manifest[id]?.thumbnail_url);
}

export function hasHealthyThumbnailInManifest(
  manifest: ThumbnailManifest,
  id: string,
  unhealthyIds: Set<string>,
): boolean {
  return hasThumbnailInManifest(manifest, id) && !unhealthyIds.has(id);
}

function loadThumbnailAssets(): Promise<{ manifest: ThumbnailManifest; unhealthy: Set<string> }> {
  if (cachedManifest && cachedUnhealthy) {
    return Promise.resolve({ manifest: cachedManifest, unhealthy: cachedUnhealthy });
  }
  if (!loadPromise) {
    loadPromise = Promise.all([
      fetch(MANIFEST_URL)
        .then(r => (r.ok ? r.json() : {}))
        .catch(() => ({})),
      fetch(UNHEALTHY_URL)
        .then(r => (r.ok ? r.json() : { ids: [] }))
        .catch(() => ({ ids: [] })),
    ]).then(([manifestData, unhealthyData]) => {
      cachedManifest = manifestData as ThumbnailManifest;
      cachedUnhealthy = parseUnhealthyIds(unhealthyData);
      return { manifest: cachedManifest, unhealthy: cachedUnhealthy };
    });
  }
  return loadPromise;
}

export function fetchThumbnailManifest(): Promise<ThumbnailManifest> {
  return loadThumbnailAssets().then(r => r.manifest);
}

export interface UseThumbnailManifestResult {
  manifest: ThumbnailManifest;
  loading: boolean;
  hasThumbnail: (id: string) => boolean;
  hasHealthyThumbnail: (id: string) => boolean;
}

export function useThumbnailManifest(): UseThumbnailManifestResult {
  const [state, setState] = useState({
    manifest: cachedManifest ?? ({} as ThumbnailManifest),
    unhealthy: cachedUnhealthy ?? new Set<string>(),
    loading: !cachedManifest,
  });

  useEffect(() => {
    let cancelled = false;
    loadThumbnailAssets().then(({ manifest: data, unhealthy: flags }) => {
      if (!cancelled) {
        setState({ manifest: data, unhealthy: flags, loading: false });
      }
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const { manifest, unhealthy, loading } = state;

  const hasThumbnail = useCallback(
    (id: string) => hasThumbnailInManifest(manifest, id),
    [manifest],
  );

  const hasHealthyThumbnail = useCallback(
    (id: string) => hasHealthyThumbnailInManifest(manifest, id, unhealthy),
    [manifest, unhealthy],
  );

  return { manifest, loading, hasThumbnail, hasHealthyThumbnail };
}

export function _resetCache() {
  cachedManifest = null;
  cachedUnhealthy = null;
  loadPromise = null;
}
