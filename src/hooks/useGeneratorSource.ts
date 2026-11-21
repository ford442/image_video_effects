import { useCallback, useEffect, useRef, useState, type RefObject } from 'react';
import type { RendererManager } from '../renderer/RendererManager';
import type { InputSource, RenderMode, ShaderEntry } from '../renderer/types';
import { getShaderDefaults } from '../app/constants/shaderDefaults';

export type GeneratorParams = [number, number, number, number];

interface UseGeneratorSourceOptions {
    rendererRef: RefObject<RendererManager | null>;
    rendererReady: boolean;
    inputSource: InputSource;
    /** The generative shader picked in the Generative source panel. */
    activeGenerativeShader: string;
    availableModes: ShaderEntry[];
    /** The picker's setter: a pick the device cannot run (hidden from the catalog) is swapped for one it can. */
    setActiveGenerativeShader: (id: string) => void;
    /** Fallback for backends without a generator stage (WASM, Canvas2D): the shader goes in slot 0. */
    setMode: (index: number, mode: RenderMode) => Promise<void> | void;
    setStatus: (status: string) => void;
}

interface UseGeneratorSourceResult {
    /** The generator's four sliders (zoom_params p1..p4). */
    generatorParams: GeneratorParams;
    setGeneratorParam: (index: number, value: number) => void;
}

/** A shader's four slider defaults: the catalog entry, unless a tuned default exists. */
export function generatorDefaults(entry: ShaderEntry | undefined): GeneratorParams {
    if (!entry) return [0.5, 0.5, 0.5, 0.5];
    const tuned = getShaderDefaults(entry.id, 4);
    const hasTuned = tuned.some((v) => v !== 0.5);
    const out = [0, 1, 2, 3].map((i) => (hasTuned ? tuned[i] : entry.params?.[i]?.default) ?? 0.5);
    return out as GeneratorParams;
}

/**
 * Generative input mode: the picked generative shader runs as the *source* (the renderer's
 * generator stage), ahead of the effect slots. It does not occupy a slot, so the user's effect
 * stack (Liquid, …) keeps processing it. Leaving Generative mode turns the stage off.
 */
export function useGeneratorSource({
    rendererRef,
    rendererReady,
    inputSource,
    activeGenerativeShader,
    availableModes,
    setActiveGenerativeShader,
    setMode,
    setStatus,
}: UseGeneratorSourceOptions): UseGeneratorSourceResult {
    const [generatorParams, setGeneratorParams] = useState<GeneratorParams>([0.5, 0.5, 0.5, 0.5]);
    const generatorParamsRef = useRef(generatorParams);
    const requestRef = useRef(0);
    const entry = availableModes.find((s) => s.id === activeGenerativeShader);
    const entryRef = useRef(entry);
    entryRef.current = entry;
    const entryId = entry?.id;
    const entryUrl = entry?.url;
    const setModeRef = useRef(setMode);
    setModeRef.current = setMode;
    const setStatusRef = useRef(setStatus);
    setStatusRef.current = setStatus;
    const setActiveRef = useRef(setActiveGenerativeShader);
    setActiveRef.current = setActiveGenerativeShader;
    const fallbackId = availableModes.find((s) => s.category === 'generative')?.id;

    useEffect(() => {
        const manager = rendererRef.current;
        if (!rendererReady || !manager) return;
        const request = ++requestRef.current;

        if (inputSource !== 'generative') {
            void manager.setGenerator(null);
            return;
        }
        const current = entryRef.current;
        if (!current) {
            // Not in the catalog: an imported preview (armed by whoever loaded it), or a shader this
            // device cannot run (the catalog hides those). The latter must not leave the source black.
            if (manager.getGenerator() === activeGenerativeShader) return;
            if (fallbackId && fallbackId !== activeGenerativeShader) setActiveRef.current(fallbackId);
            return;
        }

        const defaults = generatorDefaults(current);
        generatorParamsRef.current = defaults;
        setGeneratorParams(defaults);
        manager.setGeneratorParams(...defaults);
        void manager
            .setGenerator(current.id, {
                url: current.url,
                meta: {
                    requiresDeepWorkgroup: current.requiresDeepWorkgroup,
                    requiresHistoryRing: current.requiresHistoryRing,
                    requiresRgba32Float: current.requiresRgba32Float,
                },
            })
            .then((ok) => {
                if (request !== requestRef.current || ok) return;
                if (!manager.supportsGenerator()) {
                    // No generator stage on this backend: the old behaviour, the shader in slot 0.
                    void setModeRef.current(0, current.id as RenderMode);
                } else {
                    setStatusRef.current(`Failed to load generative shader: ${current.name}`);
                }
            });
    }, [rendererRef, rendererReady, inputSource, activeGenerativeShader, entryId, entryUrl, fallbackId]);

    const setGeneratorParam = useCallback((index: number, value: number) => {
        if (index < 0 || index > 3) return;
        const next = [...generatorParamsRef.current] as GeneratorParams;
        next[index] = value;
        generatorParamsRef.current = next;
        setGeneratorParams(next);
        rendererRef.current?.setGeneratorParams(...next);
    }, [rendererRef]);

    return { generatorParams, setGeneratorParam };
}
