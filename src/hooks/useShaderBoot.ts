import { useEffect, useRef } from 'react';
import { RenderMode, ShaderEntry, InputSource } from '../renderer/types';
import type { ImageRecord } from '../types/aiVj';

export interface UseShaderBootOptions {
    rendererReady: boolean;
    shadersReady: boolean;
    modes: RenderMode[];
    setMode: (index: number, mode: RenderMode) => void;
    setStatus: (status: string) => void;
    imageManifest: ImageRecord[];
    currentImageUrl: string | undefined;
    inputSource: InputSource;
    handleNewRandomImage: () => Promise<void>;
    availableModes: ShaderEntry[];
    autoChangeEnabled: boolean;
    autoChangeDelay: number;
    shaderCategory: string;
    syncInputSourceToRenderer: (source: InputSource) => void;
}

export function useShaderBoot({
    rendererReady,
    shadersReady,
    modes,
    setMode,
    setStatus,
    imageManifest,
    currentImageUrl,
    inputSource,
    handleNewRandomImage,
    availableModes,
    autoChangeEnabled,
    autoChangeDelay,
    shaderCategory,
    syncInputSourceToRenderer,
}: UseShaderBootOptions): void {
    const initialBootAppliedRef = useRef(false);

    useEffect(() => {
        if (shaderCategory === 'generative') {
            syncInputSourceToRenderer('generative');
            setStatus('Switched to Generative Input');
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [shaderCategory]);

    useEffect(() => {
        if (!rendererReady || !shadersReady) return;
        if (initialBootAppliedRef.current) return;
        initialBootAppliedRef.current = true;

        const initialMode = modes[0];
        if (initialMode && initialMode !== 'none') {
            setMode(0, initialMode);
        } else {
            setStatus('Ready. Select a shader from Slot 1 to get started.');
        }
    }, [rendererReady, shadersReady, modes, setMode, setStatus]);

    useEffect(() => {
        if (!rendererReady || imageManifest.length === 0 || currentImageUrl) return;
        if (inputSource !== 'image') return;
        handleNewRandomImage();
    }, [rendererReady, imageManifest, currentImageUrl, inputSource, handleNewRandomImage]);

    useEffect(() => {
        if (inputSource !== 'video') return;
        if (modes[0] && modes[0] !== 'none') return;
        if (availableModes.length === 0) return;

        const firstImageShader = availableModes.find(s => s.category !== 'generative');
        if (firstImageShader) {
            console.log('[App] Auto-selecting shader for video input:', firstImageShader.id);
            setMode(0, firstImageShader.id as RenderMode);
        }
    }, [inputSource, modes, availableModes, setMode]);

    useEffect(() => {
        if (!autoChangeEnabled || inputSource !== 'image') return;
        const interval = setInterval(() => {
            handleNewRandomImage();
        }, autoChangeDelay * 1000);
        return () => clearInterval(interval);
    }, [autoChangeEnabled, autoChangeDelay, inputSource, handleNewRandomImage]);
}
