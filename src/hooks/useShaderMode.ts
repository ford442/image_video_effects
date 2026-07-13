import { useCallback, RefObject } from 'react';
import { RenderMode, ShaderEntry, InputSource, SlotParams } from '../renderer/types';
import { RendererManager } from '../renderer/RendererManager';
import { mapOrderedParamsToSlotParams } from '../utils/shaderParamMapping';
import { getShaderDefaults } from '../app/constants/shaderDefaults';
import { SHADER_WGSL_URL } from '../app/constants/fallbackContent';

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

    const setMode = useCallback(async (index: number, mode: RenderMode) => {
        if (slotShaderStatusRef.current[index] === 'loading') return;

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
                        const next = [...prev];
                        next[index] = { ...next[index], ...paramDefaults };
                        return next;
                    });
                }

                if (ok) {
                    fetch(`${SHADER_WGSL_URL}/${shaderEntry.id}/play`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                    }).catch(() => {});
                }
            } catch (error) {
                console.error(`❌ Failed to load shader ${shaderEntry.id}:`, error);
                slotShaderStatusRef.current[index] = 'error';
                setSlotShaderStatus(prev => { const n = [...prev]; n[index] = 'error'; return n; });
            }
        }
    }, [availableModes, rendererRef, slotShaderStatusRef, setModes, setSlotShaderStatus, setSlotParams]);

    const updateSlotParam = useCallback((slotIndex: number, updates: Partial<SlotParams>) => {
        setSlotParams(prev => {
            const next = [...prev];
            next[slotIndex] = { ...next[slotIndex], ...updates };
            return next;
        });
    }, [setSlotParams]);

    return {
        setMode,
        updateSlotParam,
        mapShaderParamUpdates,
        handleApplyParamsDirect,
        syncInputSourceToRenderer,
    };
}
