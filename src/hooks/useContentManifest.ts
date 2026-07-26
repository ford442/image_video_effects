import { useEffect, RefObject } from 'react';
import { RendererManager } from '../renderer/RendererManager';
import type { ImageRecord } from '../types/aiVj';
import { VideoRecord } from '../syncTypes';
import { fetchContentManifest } from '../services/contentLoader';
import { hydrateDurations } from '../services/videoSegmentManager';
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
                content = await fetchContentManifest();
            } catch (error) {
                if ((error as Error).name === 'AbortError') return;
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

            setImageManifest(content.manifest);
            setVideoList(content.videos);
            setStatus(`Loaded ${content.manifest.length} images, ${content.videos.length} videos`);

            if (content.videos.length > 0) {
                hydrateDurations(content.videos).then((hydrated) => {
                    setVideoList(hydrated);
                }).catch((e) => {
                    console.warn("Failed to hydrate video durations:", e);
                });
            }

            if (rendererRef.current) {
                rendererRef.current.setImageList(content.manifest.map(m => m.url));
            }
        };
        fetchManifests();
        return () => controller.abort();
    }, [rendererRef, setImageManifest, setVideoList, setStatus]);
}
