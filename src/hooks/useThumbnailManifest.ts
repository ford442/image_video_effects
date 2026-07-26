import { useEffect, useState, useCallback } from 'react';

export interface ThumbnailManifestEntry {
  thumbnail_url: string;
  generated_at?: string;
  params_snapshot?: number[];
}

export type ThumbnailManifest = Record<string, ThumbnailManifestEntry>;

const MANIFEST_URL = './thumbnails/manifest.json';

let cachedManifest: ThumbnailManifest | null = null;
let loadPromise: Promise<ThumbnailManifest> | null = null;

export function fetchThumbnailManifest(): Promise<ThumbnailManifest> {
  if (cachedManifest) return Promise.resolve(cachedManifest);
  if (!loadPromise) {
    loadPromise = fetch(MANIFEST_URL)
      .then(r => (r.ok ? r.json() : {}))
      .then((data: ThumbnailManifest) => {
        cachedManifest = data;
        return data;
      })
      .catch(() => {
        cachedManifest = {};
        return {};
      });
  }
  return loadPromise;
}

export function hasThumbnailInManifest(manifest: ThumbnailManifest, id: string): boolean {
  return Boolean(manifest[id]?.thumbnail_url);
}

export interface UseThumbnailManifestResult {
  manifest: ThumbnailManifest;
  loading: boolean;
  hasThumbnail: (id: string) => boolean;
}

export function useThumbnailManifest(): UseThumbnailManifestResult {
  const [manifest, setManifest] = useState<ThumbnailManifest>(cachedManifest ?? {});
  const [loading, setLoading] = useState(!cachedManifest);

  useEffect(() => {
    let cancelled = false;
    fetchThumbnailManifest().then(data => {
      if (!cancelled) {
        setManifest(data);
        setLoading(false);
      }
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const hasThumbnail = useCallback(
    (id: string) => hasThumbnailInManifest(manifest, id),
    [manifest],
  );

  return { manifest, loading, hasThumbnail };
}
