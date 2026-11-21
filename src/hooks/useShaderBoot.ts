import { useEffect, useRef } from 'react';
import { RenderMode, ShaderEntry, InputSource } from '../renderer/types';
import type { ImageRecord } from '../types/aiVj';
import { DEFAULT_SLOT1_SHADER_ID, FALLBACK_SLOT1_SHADER_ID } from '../app/constants/shaderDefaults';

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
            // Default startup shader (Slot 1): the FROZEN original Liquid (Interactive), exactly as it
            // runs live at go.1ink.us/pixelocity. public/shaders/liquid-original.wgsl is a do-not-upgrade
            // reference — build variations from a copy of it, but keep it as the boot default.
            // (`liquid` is the upgraded sibling and is no longer the boot default.)
            // The catalog is served from storage, which only gains liquid-original after a shader sync:
            // until then fall back to the upgraded sibling so the app never boots with an empty Slot 1.
            const bootShader =
                availableModes.find(s => s.id === DEFAULT_SLOT1_SHADER_ID) ??
                availableModes.find(s => s.id === FALLBACK_SLOT1_SHADER_ID);
            if (bootShader) {
                setMode(0, bootShader.id as RenderMode);
                setStatus(
                    bootShader.id === DEFAULT_SLOT1_SHADER_ID
                        ? 'Started with Liquid (Interactive) — Original.'
                        : 'Started with Liquid (Interactive).',
                );
            } else {
                setStatus('Ready. Select a shader from Slot 1 to get started.');
            }
        }
    }, [rendererReady, shadersReady, modes, setMode, setStatus, availableModes]);

    useEffect(() => {
        if (!rendererReady || imageManifest.length === 0 || currentImageUrl) return;
        if (inputSource !== 'image') return;
        void handleNewRandomImage();
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
            void handleNewRandomImage();
        }, autoChangeDelay * 1000);
        return () => clearInterval(interval);
    }, [autoChangeEnabled, autoChangeDelay, inputSource, handleNewRandomImage]);
}
