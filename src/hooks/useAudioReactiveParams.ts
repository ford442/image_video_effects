import { useState, useEffect, useCallback, useRef, RefObject, Dispatch, SetStateAction } from 'react';
import { RenderMode, ShaderEntry, SlotParams } from '../renderer/types';
import { RendererManager } from '../renderer/RendererManager';
import { useAudioAnalyzer } from './useAudioAnalyzer';
import { AudioBandSource, AudioSlotInput, computeAudioSlotUpdates, resolveAudioTargets } from '../utils/audioParamMapping';
import type { SlotOutput } from '../renderer/slotOutput';
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
    /** Fader opacity per slot (#1512): the base the audio band gates. */
    slotOutputs?: SlotOutput[];
    /** Band that drives each slot's opacity while audio reactivity is on (null = fader only). */
    opacityAudio?: Array<AudioBandSource | null>;
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
    slotOutputs,
    opacityAudio,
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

        // Layer opacity: the band gates the fader value, renderer-side only (the fader keeps its base).
        opacityAudio?.forEach((band, slot) => {
            if (!band) return;
            const base = slotOutputs?.[slot]?.opacity ?? 1;
            const level = Math.min(1, Math.max(0, bands[band]));
            manager.setSlotOutput(slot, { opacity: base * (1 - audioReactiveAmount + audioReactiveAmount * level) });
        });
    }, [
        slotOutputs,
        opacityAudio,
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

    // Turning audio off leaves each banded layer at its last gated opacity (on the renderer and
    // in the manager's replay cache): put the fader value back, once, on that transition.
    const layerRef = useRef({ slotOutputs, opacityAudio });
    layerRef.current = { slotOutputs, opacityAudio };
    const wasReactiveRef = useRef(false);
    useEffect(() => {
        const was = wasReactiveRef.current;
        wasReactiveRef.current = audioReactiveParams;
        if (audioReactiveParams || !was) return;
        const manager = rendererRef.current;
        const { slotOutputs: outputs, opacityAudio: bands } = layerRef.current;
        bands?.forEach((band, slot) => {
            if (band) manager?.setSlotOutput(slot, { opacity: outputs?.[slot]?.opacity ?? 1 });
        });
    }, [audioReactiveParams, rendererRef]);

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
