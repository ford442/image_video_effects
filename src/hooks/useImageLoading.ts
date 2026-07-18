import { useCallback, RefObject } from 'react';
import { RendererManager } from '../renderer/RendererManager';
import { ImageRecord } from '../AutoDJ';
import { FALLBACK_IMAGES } from '../app/constants/fallbackContent';

export interface UseImageLoadingOptions {
    rendererRef: RefObject<RendererManager | null>;
    depthEstimator: ((imageUrl: string) => Promise<{ predicted_depth: { data: number[]; dims: number[] } }>) | null;
    runDepthAnalysis: (imageUrl: string) => Promise<void>;
    imageManifest: ImageRecord[];
    setCurrentImageUrl: React.Dispatch<React.SetStateAction<string | undefined>>;
    setStatus: (status: string) => void;
}

export interface UseImageLoadingReturn {
    handleLoadImage: (url: string) => Promise<void>;
    handleNewRandomImage: () => Promise<void>;
}

export function useImageLoading({
    rendererRef,
    depthEstimator,
    runDepthAnalysis,
    imageManifest,
    setCurrentImageUrl,
    setStatus,
}: UseImageLoadingOptions): UseImageLoadingReturn {
    const handleLoadImage = useCallback(async (url: string) => {
        const manager = rendererRef.current;
        if (!manager) return;
        const newImageUrl = await manager.loadImage(url);
        if (newImageUrl) {
            setCurrentImageUrl(newImageUrl);
            if (depthEstimator) {
                await runDepthAnalysis(newImageUrl);
            }
        }
    }, [rendererRef, depthEstimator, runDepthAnalysis, setCurrentImageUrl]);

    const handleNewRandomImage = useCallback(async () => {
        let sourceList = imageManifest;
        if (sourceList.length === 0) {
            sourceList = FALLBACK_IMAGES.map(url => ({
                url,
                tags: ['fallback', 'unsplash', 'demo'],
                description: 'Demo Image'
            }));
        }
        
        const randomImage = sourceList[Math.floor(Math.random() * sourceList.length)];
        if (randomImage) {
            setStatus('Loading image...');
            await handleLoadImage(randomImage.url);
            setStatus('Image loaded');
            setTimeout(() => setStatus('Ready.'), 2000);
        }
    }, [imageManifest, handleLoadImage, setStatus]);

    return { handleLoadImage, handleNewRandomImage };
}
