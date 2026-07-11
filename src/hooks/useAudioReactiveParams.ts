import React, { useState, useEffect, useCallback, useRef, RefObject, Dispatch, SetStateAction } from 'react';
import { RenderMode, ShaderEntry, SlotParams } from '../renderer/types';
import { RendererManager } from '../renderer/RendererManager';
import { useAudioAnalyzer } from './useAudioAnalyzer';

export interface UseAudioReactiveParamsOptions {
    rendererRef: RefObject<RendererManager | null>;
    modes: RenderMode[];
    availableModes: ShaderEntry[];
    updateSlotParam: (slotIndex: number, updates: Partial<SlotParams>) => void;
    getShaderDefaults: (shaderId: string, numParams?: number) => number[];
    setStatus: (status: string) => void;
}

export interface UseAudioReactiveParamsReturn {
    audioReactiveParams: boolean;
    setAudioReactiveParams: Dispatch<SetStateAction<boolean>>;
    audioReactiveAmount: number;
    setAudioReactiveAmount: Dispatch<SetStateAction<number>>;
}

export function useAudioReactiveParams({
    rendererRef,
    modes,
    availableModes,
    updateSlotParam,
    getShaderDefaults,
    setStatus,
}: UseAudioReactiveParamsOptions): UseAudioReactiveParamsReturn {
    const [audioReactiveParams, setAudioReactiveParams] = useState(false);
    const [audioReactiveAmount, setAudioReactiveAmount] = useState(0.8);

    const { startAudio: startAudioAnalyzer, stopAudio: stopAudioAnalyzer, getAudioData: getAudioAnalyzerData, getAudioBins } =
        useAudioAnalyzer();

    const audioParamSmoothedRef = useRef<[number, number, number, number]>([0.5, 0.5, 0.5, 0.5]);

    const updateAudioReactiveParams = useCallback(() => {
        const manager = rendererRef.current;
        if (!manager || !audioReactiveParams) return;

        const audioData = getAudioAnalyzerData();
        if (!audioData) return;

        const { bass, mid, treble } = audioData;
        manager.updateAudioData(bass, mid, treble);
        manager.updateAudioFrequencyBins(getAudioBins());

        const overall = (bass + mid + treble) / 3.0;
        const amount = audioReactiveAmount;

        const smoothed = audioParamSmoothedRef.current;
        const smoothing = 0.15;
        smoothed[0] += (bass - smoothed[0]) * smoothing;
        smoothed[1] += (mid - smoothed[1]) * smoothing;
        smoothed[2] += (treble - smoothed[2]) * smoothing;
        smoothed[3] += (overall - smoothed[3]) * smoothing;

        const currentShader = modes[0];
        const shaderEntry = availableModes.find(m => m.id === currentShader);
        if (shaderEntry && shaderEntry.category === 'generative') {
            const baseDefaults = getShaderDefaults(currentShader, 4);

            const modulated = {
                zoomParam1: Math.max(0, Math.min(1, baseDefaults[0] + (smoothed[0] - 0.5) * amount)),
                zoomParam2: Math.max(0, Math.min(1, baseDefaults[1] + (smoothed[1] - 0.5) * amount)),
                zoomParam3: Math.max(0, Math.min(1, baseDefaults[2] + (smoothed[2] - 0.5) * amount)),
                zoomParam4: Math.max(0, Math.min(1, baseDefaults[3] + (smoothed[3] - 0.5) * amount)),
            };

            updateSlotParam(0, modulated);
            rendererRef.current?.updateSlotParams(modulated, 0);
        }
    }, [
        audioReactiveParams,
        audioReactiveAmount,
        modes,
        availableModes,
        updateSlotParam,
        getAudioAnalyzerData,
        getAudioBins,
        getShaderDefaults,
        rendererRef,
    ]);

    useEffect(() => {
        if (!audioReactiveParams) return;

        let rafId: number;
        const tick = () => {
            updateAudioReactiveParams();
            rafId = requestAnimationFrame(tick);
        };
        rafId = requestAnimationFrame(tick);

        return () => cancelAnimationFrame(rafId);
    }, [audioReactiveParams, updateAudioReactiveParams]);

    useEffect(() => {
        if (audioReactiveParams) {
            startAudioAnalyzer();
        } else {
            stopAudioAnalyzer();
        }
    }, [audioReactiveParams, startAudioAnalyzer, stopAudioAnalyzer]);

    // Keyboard shortcuts: A toggles audio-reactive; [ ] adjust amount
    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;

            if (e.key === 'a' || e.key === 'A') {
                setAudioReactiveParams(prev => {
                    const next = !prev;
                    setStatus(next ? '🔊 Audio-reactive params ON' : '🔇 Audio-reactive params OFF');
                    return next;
                });
            }
            if (e.key === '[') {
                setAudioReactiveAmount(prev => {
                    const next = Math.max(0, Math.min(1, prev - 0.1));
                    setStatus(`🔊 Audio React Amount: ${Math.round(next * 100)}%`);
                    return next;
                });
            }
            if (e.key === ']') {
                setAudioReactiveAmount(prev => {
                    const next = Math.max(0, Math.min(1, prev + 0.1));
                    setStatus(`🔊 Audio React Amount: ${Math.round(next * 100)}%`);
                    return next;
                });
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [setStatus]);

    return {
        audioReactiveParams,
        setAudioReactiveParams,
        audioReactiveAmount,
        setAudioReactiveAmount,
    };
}
