import { useState, useCallback, RefObject } from 'react';
import { RendererManager } from '../renderer/RendererManager';
import {
  cancelDepthPipelineLoad,
  loadDepthPipeline,
  runDepthInference,
  classifyDepthLoadError,
  type DepthLoadState,
  type DepthEstimatorPipeline,
} from '../services/depthEstimation';

const INITIAL_LOAD_STATE: DepthLoadState = {
  phase: 'idle',
  message: 'Depth model not loaded.',
};

export interface UseDepthEstimationOptions {
  rendererRef: RefObject<RendererManager | null>;
  currentImageUrl: string | undefined;
  setStatus: (status: string) => void;
}

export interface UseDepthEstimationReturn {
  depthEstimator: DepthEstimatorPipeline | null;
  isModelLoaded: boolean;
  isLoadingModel: boolean;
  loadState: DepthLoadState;
  loadDepthModel: () => Promise<void>;
  cancelLoadModel: () => void;
  runDepthAnalysis: (imageUrl: string) => Promise<void>;
}

export function useDepthEstimation({
  rendererRef,
  currentImageUrl,
  setStatus,
}: UseDepthEstimationOptions): UseDepthEstimationReturn {
  const [depthEstimator, setDepthEstimator] = useState<DepthEstimatorPipeline | null>(null);
  const [loadState, setLoadState] = useState<DepthLoadState>(INITIAL_LOAD_STATE);
  const [isLoadingModel, setIsLoadingModel] = useState(false);

  const runDepthAnalysis = useCallback(async (imageUrl: string) => {
    if (!depthEstimator || !rendererRef.current) return;

    setStatus('Analyzing image with depth model...');
    const result = await runDepthInference(depthEstimator, imageUrl);

    if (!result.ok) {
      setStatus(result.message);
      return;
    }

    try {
      const { data, width, height } = result.map;
      if (rendererRef.current.updateDepthMap) {
        rendererRef.current.updateDepthMap(data, width, height);
      }
      setStatus('Depth map updated.');
    } catch (e: unknown) {
      const message = e instanceof Error ? e.message : String(e);
      console.error('[depth] updateDepthMap failed:', e);
      setStatus(`Depth map ready but upload failed: ${message}`);
    }
  }, [depthEstimator, rendererRef, setStatus]);

  const loadDepthModel = useCallback(async () => {
    if (depthEstimator) {
      setStatus('Depth model already loaded.');
      return;
    }
    if (isLoadingModel) {
      setStatus('Depth model is already loading...');
      return;
    }

    setIsLoadingModel(true);
    setLoadState({ phase: 'loading', message: 'Loading depth model...' });
    setStatus('Loading depth model...');

    try {
      const { pipeline, backend } = await loadDepthPipeline({
        onProgress: (p) => {
          const pct =
            typeof p.progress === 'number' ? ` (${(p.progress * 100).toFixed(0)}%)` : '';
          const msg = `Loading depth model: ${p.status || '...'}${pct}`;
          setLoadState({ phase: 'loading', message: msg, progress: p.progress, backend });
          setStatus(msg);
        },
        onStateChange: setLoadState,
        rendererDeviceActive: !!rendererRef.current?.getDevice(),
      });

      setDepthEstimator(() => pipeline);
      setLoadState({
        phase: 'ready',
        message: `Depth model loaded${backend === 'webgpu' ? ' (WebGPU)' : ''}.`,
        backend,
      });
      setStatus(`Depth model loaded${backend === 'webgpu' ? ' (WebGPU)' : ''}.`);

      if (currentImageUrl) {
        await runDepthAnalysis(currentImageUrl);
      }
    } catch (e: unknown) {
      console.error('[depth] load failed:', e);
      const classified = classifyDepthLoadError(e);
      setLoadState({
        phase: classified.phase,
        message: classified.message,
        error: e instanceof Error ? e.message : String(e),
      });
      setStatus(classified.message);
    } finally {
      setIsLoadingModel(false);
    }
  }, [depthEstimator, isLoadingModel, currentImageUrl, runDepthAnalysis, rendererRef, setStatus]);

  const cancelLoadModel = useCallback(() => {
    cancelDepthPipelineLoad();
    setIsLoadingModel(false);
    setLoadState({ phase: 'cancelled', message: 'Depth model load cancelled.' });
    setStatus('Depth model load cancelled.');
  }, [setStatus]);

  return {
    depthEstimator,
    isModelLoaded: !!depthEstimator,
    isLoadingModel,
    loadState,
    loadDepthModel,
    cancelLoadModel,
    runDepthAnalysis,
  };
}

export type {
  DepthEstimatorPipeline,
  DepthLoadState,
} from '../services/depthEstimation';
