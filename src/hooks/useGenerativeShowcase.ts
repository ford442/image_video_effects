import { useState, useCallback, useRef, useEffect } from 'react';
import { RenderMode, ShaderEntry, InputSource } from '../renderer/types';
import { getShaderDefaults } from '../app/constants/shaderDefaults';

export interface UseGenerativeShowcaseOptions {
    availableModes: ShaderEntry[];
    setMode: (index: number, mode: RenderMode) => void;
    updateSlotParam: (slotIndex: number, updates: Partial<{ zoomParam1: number; zoomParam2: number; zoomParam3: number; zoomParam4: number }>) => void;
    syncInputSourceToRenderer: (source: InputSource) => void;
    setActiveGenerativeShader: (id: string) => void;
    setStatus: (status: string) => void;
}

export interface UseGenerativeShowcaseReturn {
    generativeShowcaseActive: boolean;
    generativeShowcaseLocked: boolean;
    startGenerativeShowcase: () => void;
    stopGenerativeShowcase: () => void;
    lockGenerativeShowcase: () => void;
    unlockGenerativeShowcase: () => void;
}

export function useGenerativeShowcase({
    availableModes,
    setMode,
    updateSlotParam,
    syncInputSourceToRenderer,
    setActiveGenerativeShader,
    setStatus,
}: UseGenerativeShowcaseOptions): UseGenerativeShowcaseReturn {
    const [generativeShowcaseActive, setGenerativeShowcaseActive] = useState(false);
    const [generativeShowcaseLocked, setGenerativeShowcaseLocked] = useState(false);
    const [generativeShowcaseDelay] = useState(12);
    const generativeShowcaseTimerRef = useRef<NodeJS.Timeout | null>(null);

    const getGenerativeShaders = useCallback((): ShaderEntry[] => {
        return availableModes.filter(s => s.category === 'generative' && s.id !== 'none');
    }, [availableModes]);

    const advanceGenerativeShowcase = useCallback(() => {
        const genShaders = getGenerativeShaders();
        if (genShaders.length === 0) return;

        const nextShader = genShaders[Math.floor(Math.random() * genShaders.length)];
        if (!nextShader) return;

        syncInputSourceToRenderer('generative');
        setActiveGenerativeShader(nextShader.id);

        setMode(0, nextShader.id as RenderMode);

        const defaults = getShaderDefaults(nextShader.id, nextShader.params?.length || 4);
        updateSlotParam(0, {
            zoomParam1: defaults[0],
            zoomParam2: defaults[1],
            zoomParam3: defaults[2],
            zoomParam4: defaults[3],
        });

        setStatus(`🎨 Generative Showcase: ${nextShader.name}`);
    }, [getGenerativeShaders, setMode, updateSlotParam, syncInputSourceToRenderer, setActiveGenerativeShader, setStatus]);

    const startGenerativeShowcase = useCallback(() => {
        setGenerativeShowcaseLocked(false);
        setGenerativeShowcaseActive(true);
        syncInputSourceToRenderer('generative');
        advanceGenerativeShowcase();
        setStatus('🎨 Generative Showcase started! Click or press SPACE to lock the current shader.');
    }, [advanceGenerativeShowcase, syncInputSourceToRenderer, setStatus]);

    const stopGenerativeShowcase = useCallback(() => {
        setGenerativeShowcaseActive(false);
        setGenerativeShowcaseLocked(false);
        if (generativeShowcaseTimerRef.current) {
            clearInterval(generativeShowcaseTimerRef.current);
            generativeShowcaseTimerRef.current = null;
        }
        setStatus('Generative Showcase stopped.');
    }, [setStatus]);

    const lockGenerativeShowcase = useCallback(() => {
        if (!generativeShowcaseActive) return;
        setGenerativeShowcaseLocked(true);
        if (generativeShowcaseTimerRef.current) {
            clearInterval(generativeShowcaseTimerRef.current);
            generativeShowcaseTimerRef.current = null;
        }
        setStatus('🔒 Generative shader locked! Mouse control is active.');
    }, [generativeShowcaseActive, setStatus]);

    const unlockGenerativeShowcase = useCallback(() => {
        if (!generativeShowcaseActive) return;
        setGenerativeShowcaseLocked(false);
        if (generativeShowcaseTimerRef.current) {
            clearInterval(generativeShowcaseTimerRef.current);
        }
        generativeShowcaseTimerRef.current = setInterval(() => {
            advanceGenerativeShowcase();
        }, generativeShowcaseDelay * 1000);
        setStatus('🔓 Showcase resumed. Auto-switching generative shaders.');
    }, [generativeShowcaseActive, generativeShowcaseDelay, advanceGenerativeShowcase, setStatus]);

    useEffect(() => {
        if (generativeShowcaseActive && !generativeShowcaseLocked) {
            if (generativeShowcaseTimerRef.current) {
                clearInterval(generativeShowcaseTimerRef.current);
            }
            generativeShowcaseTimerRef.current = setInterval(() => {
                advanceGenerativeShowcase();
            }, generativeShowcaseDelay * 1000);
        } else {
            if (generativeShowcaseTimerRef.current) {
                clearInterval(generativeShowcaseTimerRef.current);
                generativeShowcaseTimerRef.current = null;
            }
        }

        return () => {
            if (generativeShowcaseTimerRef.current) {
                clearInterval(generativeShowcaseTimerRef.current);
            }
        };
    }, [generativeShowcaseActive, generativeShowcaseLocked, generativeShowcaseDelay, advanceGenerativeShowcase]);

    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;

            if (e.key === 'g' || e.key === 'G') {
                if (generativeShowcaseActive) {
                    stopGenerativeShowcase();
                } else {
                    startGenerativeShowcase();
                }
            }
            if (e.key === ' ') {
                e.preventDefault();
                if (generativeShowcaseActive) {
                    if (generativeShowcaseLocked) {
                        unlockGenerativeShowcase();
                    } else {
                        lockGenerativeShowcase();
                    }
                }
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [generativeShowcaseActive, generativeShowcaseLocked, startGenerativeShowcase, stopGenerativeShowcase, lockGenerativeShowcase, unlockGenerativeShowcase]);

    return {
        generativeShowcaseActive,
        generativeShowcaseLocked,
        startGenerativeShowcase,
        stopGenerativeShowcase,
        lockGenerativeShowcase,
        unlockGenerativeShowcase,
    };
}
