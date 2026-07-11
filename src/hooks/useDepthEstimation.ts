import { useState, useCallback, RefObject } from 'react';
import { pipeline, env } from '@xenova/transformers';
import { RendererManager } from '../renderer/RendererManager';

// Configure transformers.js once at module load (same as former App.tsx top-level)
env.allowLocalModels = false;
env.backends.onnx.logLevel = 'warning';

const DEPTH_MODEL_ID = 'Xenova/dpt-hybrid-midas';

export interface UseDepthEstimationOptions {
    rendererRef: RefObject<RendererManager | null>;
    currentImageUrl: string | undefined;
    setStatus: (status: string) => void;
}

export interface UseDepthEstimationReturn {
    depthEstimator: unknown | null;
    isModelLoaded: boolean;
    loadDepthModel: () => Promise<void>;
    runDepthAnalysis: (imageUrl: string) => Promise<void>;
}

export function useDepthEstimation({
    rendererRef,
    currentImageUrl,
    setStatus,
}: UseDepthEstimationOptions): UseDepthEstimationReturn {
    const [depthEstimator, setDepthEstimator] = useState<unknown | null>(null);

    const runDepthAnalysis = useCallback(async (imageUrl: string) => {
        if (!depthEstimator || !rendererRef.current) return;
        setStatus('Analyzing image with depth model...');
        try {
            const estimator = depthEstimator as (url: string) => Promise<{
                predicted_depth: { data: number[]; dims: number[] };
            }>;
            const result = await estimator(imageUrl);
            const { data, dims } = result.predicted_depth;
            const [height, width] = [dims[dims.length - 2], dims[dims.length - 1]];
            const normalizedData = new Float32Array(data.length);
            let min = Infinity;
            let max = -Infinity;
            data.forEach((v: number) => {
                min = Math.min(min, v);
                max = Math.max(max, v);
            });
            const range = max - min;
            for (let i = 0; i < data.length; ++i) {
                normalizedData[i] = 1.0 - ((data[i] - min) / range);
            }
            if (rendererRef.current.updateDepthMap) {
                rendererRef.current.updateDepthMap(normalizedData, width, height);
            }
            setStatus('Depth map updated.');
        } catch (e: unknown) {
            const message = e instanceof Error ? e.message : String(e);
            console.error('Error during analysis:', e);
            setStatus(`Failed to analyze image: ${message}`);
        }
    }, [depthEstimator, rendererRef, setStatus]);

    const loadDepthModel = useCallback(async () => {
        if (depthEstimator) {
            setStatus('Depth model already loaded.');
            return;
        }
        try {
            setStatus('Loading depth model...');
            const estimator = await pipeline('depth-estimation', DEPTH_MODEL_ID, {
                progress_callback: (p: { status?: string }) =>
                    setStatus(`Loading depth model: ${p.status}...`),
            });
            setDepthEstimator(() => estimator);
            setStatus('Depth model loaded.');
            if (currentImageUrl) await runDepthAnalysis(currentImageUrl);
        } catch (e: unknown) {
            const message = e instanceof Error ? e.message : String(e);
            console.error(e);
            setStatus(`Failed to load depth model: ${message}`);
        }
    }, [depthEstimator, currentImageUrl, runDepthAnalysis, setStatus]);

    return {
        depthEstimator,
        isModelLoaded: !!depthEstimator,
        loadDepthModel,
        runDepthAnalysis,
    };
}
