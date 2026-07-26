import { useState, useCallback, useRef, useEffect } from 'react';
import { RenderMode, ShaderEntry, SlotParams } from '../renderer/types';
import { pickWeightedShader } from '../utils/thumbnailWeightedPick';

export interface UseRouletteOptions {
    availableModes: ShaderEntry[];
    modes: RenderMode[];
    activeSlot: number;
    setMode: (index: number, mode: RenderMode) => void;
    updateSlotParam: (slotIndex: number, updates: Partial<SlotParams>) => void;
    setStatus: (status: string) => void;
    /** Prefer shaders with preview thumbnails. */
    hasThumbnail?: (id: string) => boolean;
}

export interface UseRouletteReturn {
    isRouletteActive: boolean;
    chaosModeEnabled: boolean;
    setChaosModeEnabled: React.Dispatch<React.SetStateAction<boolean>>;
    showConfetti: boolean;
    rouletteFlashRef: React.RefObject<HTMLDivElement | null>;
    handleRandomizeSlot: (slot: number) => void;
    triggerRoulette: () => void;
    triggerRandomizeAllSlots: () => void;
}

export function useRoulette({
    availableModes,
    modes,
    activeSlot,
    setMode,
    updateSlotParam,
    setStatus,
    hasThumbnail = () => false,
}: UseRouletteOptions): UseRouletteReturn {
    const [isRouletteActive, setIsRouletteActive] = useState(false);
    const [chaosModeEnabled, setChaosModeEnabled] = useState(false);
    const [rouletteFirstUse, setRouletteFirstUse] = useState(true);
    const [showConfetti, setShowConfetti] = useState(false);
    const chaosIntervalRef = useRef<NodeJS.Timeout | null>(null);
    const rouletteFlashRef = useRef<HTMLDivElement | null>(null);

    const getRandomShader = useCallback((): ShaderEntry | null => {
        if (availableModes.length === 0) return null;
        const EXCLUDED_CATEGORIES = new Set(['generative', 'simulation']);
        const validShaders = availableModes.filter(s => {
            if (!s.id || s.id === 'none') return false;
            if (EXCLUDED_CATEGORIES.has(s.category)) return false;
            if (s.tags?.includes('generative') || s.tags?.includes('simulation')) return false;
            return true;
        });
        if (validShaders.length === 0) return null;
        return pickWeightedShader(validShaders, hasThumbnail);
    }, [availableModes, hasThumbnail]);

    const randomizeSlotParams = useCallback((): SlotParams => {
        return {
            zoomParam1: 0.3 + Math.random() * 0.7,
            zoomParam2: 0.5 + Math.random() * 0.5,
            zoomParam3: Math.random() * 1.0,
            zoomParam4: Math.random() * 1.0,
            lightStrength: 0.5 + Math.random() * 1.5,
            ambient: 0.1 + Math.random() * 0.4,
            normalStrength: 0.05 + Math.random() * 0.25,
            fogFalloff: 2.0 + Math.random() * 6.0,
            depthThreshold: 0.3 + Math.random() * 0.5,
        };
    }, []);

    const handleRandomizeSlot = useCallback((slot: number) => {
        const randomShader = getRandomShader();
        if (!randomShader) {
            setStatus('No shaders available for randomize.');
            return;
        }
        setMode(slot, randomShader.id as RenderMode);
        const newParams = randomizeSlotParams();
        updateSlotParam(slot, newParams);
        setStatus(`🎲 Randomized slot ${slot + 1}: ${randomShader.name}`);
        setIsRouletteActive(true);
        setTimeout(() => setIsRouletteActive(false), 500);
    }, [getRandomShader, randomizeSlotParams, setMode, updateSlotParam, setStatus]);

    const triggerRoulette = useCallback(() => {
        const randomShader = getRandomShader();
        if (!randomShader) {
            setStatus('No shaders available for Roulette!');
            return;
        }

        if (rouletteFlashRef.current) {
            rouletteFlashRef.current.classList.add('flash-active');
            setTimeout(() => {
                rouletteFlashRef.current?.classList.remove('flash-active');
            }, 300);
        }

        setMode(activeSlot, randomShader.id as RenderMode);

        const newParams = randomizeSlotParams();
        updateSlotParam(activeSlot, newParams);

        if (rouletteFirstUse) {
            setShowConfetti(true);
            setRouletteFirstUse(false);
            setTimeout(() => setShowConfetti(false), 3000);
        }

        setStatus(`🎰 Roulette slot ${activeSlot + 1}: ${randomShader.name}`);
        setIsRouletteActive(true);
        setTimeout(() => setIsRouletteActive(false), 500);
    }, [getRandomShader, randomizeSlotParams, setMode, updateSlotParam, rouletteFirstUse, activeSlot, setStatus]);

    const triggerRandomizeAllSlots = useCallback(() => {
        if (rouletteFlashRef.current) {
            rouletteFlashRef.current.classList.add('flash-active');
            setTimeout(() => {
                rouletteFlashRef.current?.classList.remove('flash-active');
            }, 300);
        }

        const names: string[] = [];
        for (let i = 0; i < modes.length; i++) {
            const randomShader = getRandomShader();
            if (randomShader) {
                setMode(i, randomShader.id as RenderMode);
                updateSlotParam(i, randomizeSlotParams());
                names.push(randomShader.name);
            }
        }

        setStatus(`🎲 All slots randomized: ${names.join(', ')}`);
        setIsRouletteActive(true);
        setTimeout(() => setIsRouletteActive(false), 500);
    }, [getRandomShader, randomizeSlotParams, setMode, updateSlotParam, modes.length, setStatus]);

    useEffect(() => {
        if (chaosModeEnabled) {
            triggerRoulette();
            chaosIntervalRef.current = setInterval(() => {
                triggerRoulette();
            }, 6000 + Math.random() * 4000);
        } else {
            if (chaosIntervalRef.current) {
                clearInterval(chaosIntervalRef.current);
                chaosIntervalRef.current = null;
            }
        }

        return () => {
            if (chaosIntervalRef.current) {
                clearInterval(chaosIntervalRef.current);
            }
        };
    }, [chaosModeEnabled, triggerRoulette]);

    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.key === 'r' || e.key === 'R') {
                if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
                    return;
                }
                triggerRoulette();
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [triggerRoulette]);

    return {
        isRouletteActive,
        chaosModeEnabled,
        setChaosModeEnabled,
        showConfetti,
        rouletteFlashRef,
        handleRandomizeSlot,
        triggerRoulette,
        triggerRandomizeAllSlots,
    };
}
