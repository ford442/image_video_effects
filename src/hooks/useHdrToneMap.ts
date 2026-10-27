/**
 * useHdrToneMap.ts
 *
 * Paper white / peak nits for the HDR canvas tonemap (#1512). Persisted in
 * localStorage and project files (render.hdr); pushed to the renderer on
 * change and once it is ready. Only visible while the canvas is HDR.
 */

import { RefObject, useCallback, useEffect, useState } from 'react';
import type { RendererManager } from '../renderer/RendererManager';
import {
    loadHdrToneMap,
    normalizeHdrToneMap,
    saveHdrToneMap,
    type HdrToneMapSettings,
} from '../services/hdrOutput';

export interface UseHdrToneMapReturn {
    settings: HdrToneMapSettings;
    setSettings: (settings: HdrToneMapSettings) => void;
}

export function useHdrToneMap(rendererRef: RefObject<RendererManager | null>, rendererReady: boolean): UseHdrToneMapReturn {
    const [settings, setState] = useState<HdrToneMapSettings>(() => loadHdrToneMap());

    useEffect(() => {
        if (rendererReady) rendererRef.current?.setHdrToneMap(settings);
    }, [rendererReady, rendererRef, settings]);

    const setSettings = useCallback((next: HdrToneMapSettings) => {
        const normalized = normalizeHdrToneMap(next);
        saveHdrToneMap(normalized);
        setState(normalized);
    }, []);

    return { settings, setSettings };
}
