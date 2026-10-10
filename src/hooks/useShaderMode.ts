import { useCallback, useRef, RefObject } from 'react';
import { RenderMode, ShaderEntry, InputSource, SlotParams } from '../renderer/types';
import { RendererManager } from '../renderer/RendererManager';
import { mapOrderedParamsToSlotParams } from '../utils/shaderParamMapping';
import { getShaderDefaults } from '../app/constants/shaderDefaults';
import { clearSlot as clearAudioParamHolds } from '../services/audioParamHold';

export interface UseShaderModeOptions {
    rendererRef: RefObject<RendererManager | null>;
    availableModes: ShaderEntry[];
    availableModesRef: RefObject<ShaderEntry[]>;
    modesRef: RefObject<RenderMode[]>;
    slotParamsRef: RefObject<SlotParams[]>;
    inputSourceRef: RefObject<InputSource>;
    slotShaderStatusRef: RefObject<Array<'idle' | 'loading' | 'error'>>;
    setModes: React.Dispatch<React.SetStateAction<RenderMode[]>>;
    setSlotParams: React.Dispatch<React.SetStateAction<SlotParams[]>>;
    setSlotShaderStatus: React.Dispatch<React.SetStateAction<Array<'idle' | 'loading' | 'error'>>>;
    setInputSource: React.Dispatch<React.SetStateAction<InputSource>>;
}

export interface UseShaderModeReturn {
    setMode: (index: number, mode: RenderMode) => Promise<void>;
    updateSlotParam: (slotIndex: number, updates: Partial<SlotParams>) => void;
    mapShaderParamUpdates: (slotParamsUpdates: Record<string, number>, slotIndex: number) => Partial<SlotParams>;
    handleApplyParamsDirect: (paramsList: Record<string, number>[]) => void;
    syncInputSourceToRenderer: (source: InputSource) => void;
}

export function useShaderMode({
    rendererRef,
    availableModes,
    availableModesRef,
    modesRef,
    slotParamsRef,
    inputSourceRef,
    slotShaderStatusRef,
    setModes,
    setSlotParams,
    setSlotShaderStatus,
    setInputSource,
}: UseShaderModeOptions): UseShaderModeReturn {
    const syncInputSourceToRenderer = useCallback((source: InputSource) => {
        inputSourceRef.current = source;
        setInputSource(source);
        rendererRef.current?.setInputSource(source);
    }, [inputSourceRef, setInputSource, rendererRef]);

    const mapShaderParamUpdates = useCallback((slotParamsUpdates: Record<string, number>, slotIndex: number): Partial<SlotParams> => {
        const shaderId = modesRef.current[slotIndex];
        const shaderEntry = availableModesRef.current.find(m => m.id === shaderId);
        if (!shaderEntry || !shaderEntry.params) return {};

        return mapOrderedParamsToSlotParams(slotParamsUpdates, shaderEntry.params.map(p => p.id));
    }, [modesRef, availableModesRef]);

    const handleApplyParamsDirect = useCallback((paramsList: Record<string, number>[]) => {
        paramsList.forEach((slotParamsUpdates, slotIndex) => {
            const updates = mapShaderParamUpdates(slotParamsUpdates, slotIndex);
            if (Object.keys(updates).length > 0) {
                rendererRef.current?.updateSlotParams({
                    zoomParam1: updates.zoomParam1,
                    zoomParam2: updates.zoomParam2,
                    zoomParam3: updates.zoomParam3,
                    zoomParam4: updates.zoomParam4,
                }, slotIndex);
            }
        });
    }, [mapShaderParamUpdates, rendererRef]);

    const applyMode = useCallback(async (index: number, mode: RenderMode) => {
        // New shader → old performer bases for this slot are meaningless.
        if (modesRef.current[index] !== mode) clearAudioParamHolds(index);

        setModes(prev => {
            const next = [...prev];
            next[index] = mode;
            return next;
        });

        if (mode === 'none') {
            slotShaderStatusRef.current[index] = 'idle';
            setSlotShaderStatus(prev => { const n = [...prev]; n[index] = 'idle'; return n; });
            if (rendererRef.current) {
                rendererRef.current.setSlotShader(index, '');
            }
            return;
        }

        const shaderEntry = availableModes.find(s => s.id === mode);
        if (shaderEntry && rendererRef.current) {
            slotShaderStatusRef.current[index] = 'loading';
            setSlotShaderStatus(prev => { const n = [...prev]; n[index] = 'loading'; return n; });

            try {
                const shaderUrl = shaderEntry.url;
                const ok = await rendererRef.current.loadShader(shaderEntry.id, shaderUrl);
                
                if (ok && rendererRef.current) {
                    rendererRef.current.setSlotShader(index, shaderEntry.id);
                }
                
                slotShaderStatusRef.current[index] = ok ? 'idle' : 'error';
                setSlotShaderStatus(prev => { const n = [...prev]; n[index] = ok ? 'idle' : 'error'; return n; });
                
                const hardcodedDefaults = getShaderDefaults(shaderEntry.id, shaderEntry.params?.length || 4);
                const hasHardcoded = hardcodedDefaults.some(v => v !== 0.5);
                
                if (ok && (shaderEntry.params?.length || hasHardcoded)) {
                    const paramDefaults: Partial<SlotParams> = {};
                    const numParams = shaderEntry.params?.length || hardcodedDefaults.length;
                    
                    for (let i = 0; i < numParams; i++) {
                        const defaultValue = hasHardcoded ? hardcodedDefaults[i] : (shaderEntry.params?.[i]?.default ?? 0.5);
                        if (i === 0) paramDefaults.zoomParam1 = defaultValue;
                        else if (i === 1) paramDefaults.zoomParam2 = defaultValue;
                        else if (i === 2) paramDefaults.zoomParam3 = defaultValue;
                        else if (i === 3) paramDefaults.zoomParam4 = defaultValue;
                    }
                    
                    setSlotParams(prev => {
                        const current = prev[index];
                        if (!current) return prev;
                        const next = [...prev];
                        next[index] = { ...current, ...paramDefaults };
                        return next;
                    });
                }

                // Note: production storage API has no /api/shaders/{id}/play
                // (OpenAPI only exposes song/preset-pack play). Skipping avoids
                // a 404 on every successful shader load that looks like a failure.
            } catch (error) {
                console.error(`❌ Failed to load shader ${shaderEntry.id}:`, error);
                slotShaderStatusRef.current[index] = 'error';
                setSlotShaderStatus(prev => { const n = [...prev]; n[index] = 'error'; return n; });
            }
        }
    }, [availableModes, rendererRef, modesRef, slotShaderStatusRef, setModes, setSlotShaderStatus, setSlotParams]);

    /** Picks made while a slot is loading; the newest one is applied when the load settles. */
    const pendingModesRef = useRef(new Map<number, RenderMode>());

    const setMode = useCallback(async (index: number, mode: RenderMode) => {
        if (slotShaderStatusRef.current[index] === 'loading') {
            pendingModesRef.current.set(index, mode);
            return;
        }
        let next: RenderMode | undefined = mode;
        while (next !== undefined) {
            await applyMode(index, next);
            next = pendingModesRef.current.get(index);
            pendingModesRef.current.delete(index);
        }
    }, [applyMode, slotShaderStatusRef]);

    const updateSlotParam = useCallback((slotIndex: number, updates: Partial<SlotParams>) => {
        setSlotParams(prev => {
            const current = prev[slotIndex];
            if (!current) return prev;
            const next = [...prev];
            next[slotIndex] = { ...current, ...updates };
            return next;
        });
        // Push to GPU immediately so remote control / MIDI / sliders affect the
        // live frame without waiting on a React→canvas effect cycle.
        rendererRef.current?.updateSlotParams(
            {
                zoomParam1: updates.zoomParam1,
                zoomParam2: updates.zoomParam2,
                zoomParam3: updates.zoomParam3,
                zoomParam4: updates.zoomParam4,
            },
            slotIndex,
        );
    }, [setSlotParams, rendererRef]);

    return {
        setMode,
        updateSlotParam,
        mapShaderParamUpdates,
        handleApplyParamsDirect,
        syncInputSourceToRenderer,
    };
}
