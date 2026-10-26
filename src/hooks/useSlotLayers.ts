import { createContext, useCallback, useContext, useEffect, useRef, useState, RefObject } from 'react';
import type { RendererManager } from '../renderer/RendererManager';
import type { SlotMode } from '../renderer/types';
import { PHYSICAL_SLOT_LIMIT } from '../renderer/slotOrchestrator';
import { DEFAULT_SLOT_OUTPUT, normalizeSlotOutput, patchSlotOutput, type SlotOutput } from '../renderer/slotOutput';
import type { AudioBandSource } from '../utils/audioParamMapping';

/** Per-slot layering state (#1512): chained / parallel, compositor output, audio → opacity. */
export interface SlotLayers {
    slotModes: SlotMode[];
    slotOutputs: SlotOutput[];
    /** Audio band that gates a slot's opacity while audio reactivity is on (session only). */
    opacityAudio: Array<AudioBandSource | null>;
    setSlotMode: (index: number, mode: SlotMode) => void;
    setSlotOutput: (index: number, patch: Partial<SlotOutput>) => void;
    /** Opacity only: what MIDI / keys / OSC drive. */
    setSlotOpacity: (index: number, opacity: number) => void;
    setOpacityAudio: (index: number, band: AudioBandSource | null) => void;
    /** Replace every slot's mode and output at once (share links, project files). */
    applyLayers: (layers: { slotModes?: SlotMode[]; slotOutputs?: SlotOutput[] }) => void;
}

export const SlotLayersContext = createContext<SlotLayers | null>(null);

/** The app's slot layering, or null outside the provider (isolated component tests). */
export function useSlotLayersContext(): SlotLayers | null {
    return useContext(SlotLayersContext);
}

const fill = <T,>(make: () => T): T[] => Array.from({ length: PHYSICAL_SLOT_LIMIT }, make);

export interface UseSlotLayersOptions {
    rendererRef: RefObject<RendererManager | null>;
    rendererReady: boolean;
}

/**
 * Owns slot modes and compositor outputs on the page and keeps the renderer in step.
 * The renderer manager also remembers outputs across backend switches; modes are
 * re-sent here whenever a backend becomes ready.
 */
export function useSlotLayers({ rendererRef, rendererReady }: UseSlotLayersOptions): SlotLayers {
    const [slotModes, setSlotModes] = useState<SlotMode[]>(() => fill(() => 'chained' as SlotMode));
    const [slotOutputs, setSlotOutputs] = useState<SlotOutput[]>(() => fill(() => ({ ...DEFAULT_SLOT_OUTPUT })));
    const [opacityAudio, setOpacityAudioState] = useState<Array<AudioBandSource | null>>(() => fill(() => null));
    const latest = useRef({ slotModes, slotOutputs });
    latest.current = { slotModes, slotOutputs };

    const setSlotMode = useCallback((index: number, mode: SlotMode) => {
        if (index < 0 || index >= PHYSICAL_SLOT_LIMIT) return;
        setSlotModes((prev) => (prev[index] === mode ? prev : prev.map((m, i) => (i === index ? mode : m))));
        rendererRef.current?.setSlotMode(index, mode);
    }, [rendererRef]);

    const setSlotOutput = useCallback((index: number, patch: Partial<SlotOutput>) => {
        if (index < 0 || index >= PHYSICAL_SLOT_LIMIT) return;
        setSlotOutputs((prev) => prev.map((o, i) => (i === index ? patchSlotOutput(o, patch) : o)));
        rendererRef.current?.setSlotOutput(index, patch);
    }, [rendererRef]);

    const setSlotOpacity = useCallback(
        (index: number, opacity: number) => setSlotOutput(index, { opacity }),
        [setSlotOutput],
    );

    const setOpacityAudio = useCallback((index: number, band: AudioBandSource | null) => {
        setOpacityAudioState((prev) => prev.map((b, i) => (i === index ? band : b)));
        // Back to the fader value when the band is switched off.
        if (!band) rendererRef.current?.setSlotOutput(index, { opacity: latest.current.slotOutputs[index]?.opacity ?? 1 });
    }, [rendererRef]);

    const applyLayers = useCallback((layers: { slotModes?: SlotMode[]; slotOutputs?: SlotOutput[] }) => {
        const modes = fill(() => 'chained' as SlotMode).map((m, i) => layers.slotModes?.[i] ?? m);
        const outputs = fill(() => ({ ...DEFAULT_SLOT_OUTPUT })).map((o, i) => normalizeSlotOutput(layers.slotOutputs?.[i] ?? o));
        setSlotModes(modes);
        setSlotOutputs(outputs);
        const manager = rendererRef.current;
        modes.forEach((mode, i) => manager?.setSlotMode(i, mode));
        outputs.forEach((output, i) => manager?.setSlotOutput(i, output));
    }, [rendererRef]);

    // A new backend starts chained / replace: hand it the page's layering.
    useEffect(() => {
        const manager = rendererRef.current;
        if (!rendererReady || !manager) return;
        latest.current.slotModes.forEach((mode, i) => {
            if (mode !== 'chained') manager.setSlotMode(i, mode);
        });
        latest.current.slotOutputs.forEach((output, i) => manager.setSlotOutput(i, output));
    }, [rendererReady, rendererRef]);

    return {
        slotModes,
        slotOutputs,
        opacityAudio,
        setSlotMode,
        setSlotOutput,
        setSlotOpacity,
        setOpacityAudio,
        applyLayers,
    };
}
