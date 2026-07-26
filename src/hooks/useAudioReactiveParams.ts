import { useState, useEffect, useCallback, useRef, RefObject, Dispatch, SetStateAction } from 'react';
import { RenderMode, ShaderEntry, SlotParams } from '../renderer/types';
import { RendererManager } from '../renderer/RendererManager';
import { useAudioAnalyzer } from './useAudioAnalyzer';
import { resolveAudioTargets, sampleAudioSource } from '../utils/audioParamMapping';

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

    const audioParamSmoothedRef = useRef<Record<string, number>>({});

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
        const bands = { bass, mid, treble, overall };
        const fftBins = getAudioBins();

        const currentShader = modes[0];
        const shaderEntry = availableModes.find(m => m.id === currentShader);
        if (shaderEntry && shaderEntry.category === 'generative') {
            const targets = resolveAudioTargets(shaderEntry);
            const baseDefaults = getShaderDefaults(currentShader, 4);
            const modulated: Partial<SlotParams> = {};
            const smoothing = 0.15;

            targets.forEach((target, idx) => {
                const raw = sampleAudioSource(target.audioSource, bands, fftBins);
                const key = target.slotParamKey;
                const prev = audioParamSmoothedRef.current[key] ?? raw;
                const smoothed = prev + (raw - prev) * smoothing;
                audioParamSmoothedRef.current[key] = smoothed;

                const baseDefault = baseDefaults[idx] ?? target.default;
                const value = Math.max(
                    target.min,
                    Math.min(target.max, baseDefault + (smoothed - 0.5) * amount),
                );
                modulated[key] = value;
            });

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
            audioParamSmoothedRef.current = {};
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
