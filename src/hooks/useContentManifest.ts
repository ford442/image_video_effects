import { useEffect, RefObject } from 'react';
import { RendererManager } from '../renderer/RendererManager';
import type { ImageRecord } from '../types/aiVj';
import { VideoRecord } from '../syncTypes';
import { fetchContentManifest } from '../services/contentLoader';
import { FALLBACK_IMAGES, FALLBACK_VIDEOS } from '../app/constants/fallbackContent';

export interface UseContentManifestOptions {
    rendererRef: RefObject<RendererManager | null>;
    setImageManifest: React.Dispatch<React.SetStateAction<ImageRecord[]>>;
    setVideoList: React.Dispatch<React.SetStateAction<VideoRecord[]>>;
    setStatus: (status: string) => void;
}

export function useContentManifest({
    rendererRef,
    setImageManifest,
    setVideoList,
    setStatus,
}: UseContentManifestOptions): void {
    useEffect(() => {
        const controller = new AbortController();

        const fetchManifests = async () => {
            let content;
            try {
                content = await fetchContentManifest({ signal: controller.signal });
            } catch (error) {
                if (controller.signal.aborted || (error as Error).name === 'AbortError') return;
                console.warn("Failed to fetch manifests:", error);
                content = {
                    manifest: FALLBACK_IMAGES.map(url => ({
                        url,
                        tags: ['fallback', 'unsplash', 'demo'],
                        description: 'Demo Image'
                    })),
                    videos: FALLBACK_VIDEOS.map(url => ({ url })),
                };
            }

            if (controller.signal.aborted) return;

            setImageManifest(content.manifest);
            setVideoList(content.videos);
            setStatus(`Loaded ${content.manifest.length} images, ${content.videos.length} videos`);

            // Durations are intentionally not probed here: each probe is a
            // cross-origin media request. They are filled in on demand
            // (B3HD mode, video selection) by the hooks that need them.

            if (rendererRef.current) {
                rendererRef.current.setImageList(content.manifest.map(m => m.url));
            }
        };
        void fetchManifests();
        return () => controller.abort();
    }, [rendererRef, setImageManifest, setVideoList, setStatus]);
}
