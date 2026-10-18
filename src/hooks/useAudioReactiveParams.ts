import { useState, useEffect, useCallback, useRef, RefObject, Dispatch, SetStateAction } from 'react';
import { RenderMode, ShaderEntry, SlotParams } from '../renderer/types';
import { RendererManager } from '../renderer/RendererManager';
import { useAudioAnalyzer } from './useAudioAnalyzer';
import { AudioSlotInput, computeAudioSlotUpdates, resolveAudioTargets } from '../utils/audioParamMapping';
import { baseFor, isHeld } from '../services/audioParamHold';

export interface UseAudioReactiveParamsOptions {
    rendererRef: RefObject<RendererManager | null>;
    modes: RenderMode[];
    availableModes: ShaderEntry[];
    updateSlotParam: (slotIndex: number, updates: Partial<SlotParams>) => void;
    getShaderDefaults: (shaderId: string, numParams?: number) => number[];
    setStatus: (status: string) => void;
    /** Quality-tier slot cap; falls back to the renderer's policy. */
    maxActiveSlots?: number;
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
    maxActiveSlots,
}: UseAudioReactiveParamsOptions): UseAudioReactiveParamsReturn {
    const [audioReactiveParams, setAudioReactiveParams] = useState(false);
    const [audioReactiveAmount, setAudioReactiveAmount] = useState(0.8);

    const { startAudio: startAudioAnalyzer, stopAudio: stopAudioAnalyzer, getAudioData: getAudioAnalyzerData, getAudioBins } =
        useAudioAnalyzer();

    const audioParamSmoothedRef = useRef<Record<string, number>>({});
    const slotShaderIdsRef = useRef<Array<RenderMode | undefined>>([]);

    const updateAudioReactiveParams = useCallback(() => {
        const manager = rendererRef.current;
        if (!manager || !audioReactiveParams) return;

        const audioData = getAudioAnalyzerData();
        if (!audioData) return;

        const { bass, mid, treble } = audioData;
        manager.updateAudioData(bass, mid, treble);
        manager.updateAudioFrequencyBins(getAudioBins());

        const overall = (bass + mid + treble) / 3.0;
        const bands = { bass, mid, treble, overall };

        // Every active slot (bounded by the quality-tier cap), every category
        // whose params declare `audio` — generative keeps positional fallback.
        const cap = Math.max(1, maxActiveSlots ?? manager.getMaxActiveSlots());
        const slots: AudioSlotInput[] = [];
        const lastIds = slotShaderIdsRef.current;
        for (let slot = 0; slot < Math.min(cap, modes.length); slot++) {
            const shaderId = modes[slot];
            if (lastIds[slot] !== shaderId) {
                // Shader swapped under this slot: drop its smoothing (performer
                // bases are cleared by setMode via audioParamHold.clearSlot).
                for (const k of Object.keys(audioParamSmoothedRef.current)) {
                    if (k.startsWith(`${slot}:`)) delete audioParamSmoothedRef.current[k];
                }
                lastIds[slot] = shaderId;
            }
            if (!shaderId || shaderId === 'none') continue;
            const shaderEntry = availableModes.find(m => m.id === shaderId);
            if (!shaderEntry) continue;
            const targets = resolveAudioTargets(shaderEntry);
            if (targets.length === 0) continue;
            slots.push({ slot, targets, defaults: getShaderDefaults(shaderId, 4) });
        }

        const updates = computeAudioSlotUpdates({
            slots,
            bands,
            fftBins: getAudioBins(),
            amount: audioReactiveAmount,
            smoothed: audioParamSmoothedRef.current,
            isHeld,
            baseFor,
        });
        // updateSlotParam already pushes to the renderer; one write per slot.
        for (const { slot, updates: u } of updates) updateSlotParam(slot, u);
    }, [
        audioReactiveParams,
        audioReactiveAmount,
        maxActiveSlots,
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
            void startAudioAnalyzer();
        } else {
            stopAudioAnalyzer();
            audioParamSmoothedRef.current = {};
            slotShaderIdsRef.current = [];
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
