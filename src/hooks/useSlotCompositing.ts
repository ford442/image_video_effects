/**
 * useSlotCompositing.ts
 *
 * App-side state for the layer strip (#1512): per-slot chained/parallel mode
 * and compositing layer (blend / opacity / mask). Every change is pushed to the
 * renderer; RendererManager keeps its own copy and replays it onto a rebuilt
 * backend, so this hook never has to re-sync after a device loss.
 *
 * Opacity is also a slot param ('opacity', LAYER_OPACITY_PARAM), so MIDI /
 * keyboard / OSC bindings automate it through the same setSlotParam action as
 * the shader sliders.
 */

import { RefObject, useCallback, useEffect, useRef, useState } from 'react';
import type { RendererManager } from '../renderer/RendererManager';
import type { SlotMode } from '../renderer/types';
import { PHYSICAL_SLOT_LIMIT } from '../renderer/slotOrchestrator';
import { defaultSlotLayer, normalizeSlotLayer, slotLayersEqual, type SlotLayer } from '../renderer/layerState';

/** The slot-param name bindings use to drive a layer's opacity. */
export const LAYER_OPACITY_PARAM = 'opacity';

export interface UseSlotCompositingReturn {
    slotModes: SlotMode[];
    slotLayers: SlotLayer[];
    setSlotMode: (index: number, mode: SlotMode) => void;
    setSlotLayer: (index: number, layer: SlotLayer) => void;
    /** 0..1. A replace layer becomes a normal blend so the change is visible. */
    setSlotOpacity: (index: number, opacity: number) => void;
    /** Replace every slot's mode and layer (shared chains, project files). */
    applySlotCompositing: (modes: readonly SlotMode[], layers: readonly SlotLayer[]) => void;
}

export function useSlotCompositing(
    rendererRef: RefObject<RendererManager | null>,
    rendererReady = true,
): UseSlotCompositingReturn {
    const [slotModes, setSlotModes] = useState<SlotMode[]>(() => Array.from({ length: PHYSICAL_SLOT_LIMIT }, () => 'chained'));
    const [slotLayers, setSlotLayers] = useState<SlotLayer[]>(() =>
        Array.from({ length: PHYSICAL_SLOT_LIMIT }, () => defaultSlotLayer()));
    // Bindings fire faster than renders; read-modify-write against the latest value
    // (only this hook writes slotLayers, so the ref never lags it).
    const layersRef = useRef(slotLayers);

    const setSlotMode = useCallback((index: number, mode: SlotMode) => {
        if (index < 0 || index >= PHYSICAL_SLOT_LIMIT) return;
        rendererRef.current?.setSlotMode(index, mode);
        setSlotModes((prev) => prev.map((m, i) => (i === index ? mode : m)));
    }, [rendererRef]);

    const setSlotLayer = useCallback((index: number, layer: SlotLayer) => {
        if (index < 0 || index >= PHYSICAL_SLOT_LIMIT) return;
        const next = normalizeSlotLayer(layer);
        const current = layersRef.current[index];
        if (current && slotLayersEqual(current, next)) return;
        layersRef.current = layersRef.current.map((l, i) => (i === index ? next : l));
        rendererRef.current?.setSlotLayer(index, next);
        setSlotLayers(layersRef.current);
    }, [rendererRef]);

    const setSlotOpacity = useCallback((index: number, opacity: number) => {
        const current = layersRef.current[index];
        if (!current) return;
        const base = current.output === 'replace' ? { ...current, output: 'blend' as const, blend: 'normal' as const } : current;
        setSlotLayer(index, { ...base, opacity });
    }, [setSlotLayer]);

    const modesRef = useRef(slotModes);
    useEffect(() => { modesRef.current = slotModes; }, [slotModes]);
    // Changes made before the renderer existed (or by a remount) reach it once it is ready.
    useEffect(() => {
        const manager = rendererRef.current;
        if (!rendererReady || !manager) return;
        modesRef.current.forEach((mode, i) => {
            if (mode !== 'chained') manager.setSlotMode(i, mode);
        });
        layersRef.current.forEach((layer, i) => {
            if (!slotLayersEqual(layer, defaultSlotLayer())) manager.setSlotLayer(i, layer);
        });
    }, [rendererReady, rendererRef]);

    const applySlotCompositing = useCallback((modes: readonly SlotMode[], layers: readonly SlotLayer[]) => {
        for (let i = 0; i < PHYSICAL_SLOT_LIMIT; i++) {
            setSlotMode(i, modes[i] ?? 'chained');
            setSlotLayer(i, layers[i] ?? defaultSlotLayer());
        }
    }, [setSlotMode, setSlotLayer]);

    return { slotModes, slotLayers, setSlotMode, setSlotLayer, setSlotOpacity, applySlotCompositing };
}
