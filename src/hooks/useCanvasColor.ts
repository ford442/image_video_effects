/**
 * useCanvasColor.ts
 *
 * The Render Quality → Wide-gamut output (Display P3) toggle, connected to the
 * renderer (#1512). On an HDR display the same opt-in negotiates the HDR canvas
 * (rgba16float + extended tone mapping); `hdrActive` says when that happened, so
 * the panel can show the paper-white / peak controls.
 *
 * The choice persists (px_display_p3; ?display_p3=1 still wins). A toggle during
 * a recording is deferred by the renderer and re-applied when recording stops,
 * so one take never mixes colour spaces.
 */

import { RefObject, useCallback, useEffect, useRef, useState } from 'react';
import type { RendererManager } from '../renderer/RendererManager';
import type { DisplayP3Result } from '../renderer/webgpuBootProbe';
import {
    describeDisplayP3Status,
    isDisplayP3UrlForced,
    isHdrDisplay,
    loadDisplayP3,
    saveDisplayP3,
} from '../services/displayP3';

export interface UseCanvasColorReturn {
    displayP3: boolean;
    setDisplayP3: (enabled: boolean) => void;
    /** One-line applied-state text for the panel ('' when off). */
    status: string;
    /** The canvas is rgba16float with extended tone mapping (the HDR tonemap applies). */
    hdrActive: boolean;
}

function statusOf(requested: boolean, result: DisplayP3Result | null): string {
    if (result?.deferred) return 'Applies after recording stops';
    const applied = typeof window !== 'undefined' ? window.webgpuProbe : undefined;
    return describeDisplayP3Status(requested, result
        ? { canvasColorSpace: result.colorSpace, canvasToneMapping: result.toneMapping, canvasColorFallback: result.reason }
        : applied);
}

export function useCanvasColor(
    rendererRef: RefObject<RendererManager | null>,
    rendererReady: boolean,
    isRecording: boolean,
): UseCanvasColorReturn {
    const [displayP3, setState] = useState(() => loadDisplayP3() || isDisplayP3UrlForced());
    const [result, setResult] = useState<DisplayP3Result | null>(null);
    const pending = useRef<boolean | null>(null);

    const apply = useCallback(async (enabled: boolean) => {
        const manager = rendererRef.current;
        if (!manager) return;
        const next = await manager.setDisplayP3(enabled, isHdrDisplay());
        if (!next) return;
        pending.current = next.deferred ? enabled : null;
        setResult(next);
    }, [rendererRef]);

    // The boot probe already negotiated the saved choice; read what it applied.
    useEffect(() => {
        if (!rendererReady || typeof window === 'undefined') return;
        const probe = window.webgpuProbe;
        if (!probe) return;
        setResult({
            requested: { displayP3 },
            applied: { displayP3: probe.canvasColorSpace === 'display-p3', extendedToneMapping: probe.canvasToneMapping === 'extended' },
            colorSpace: probe.canvasColorSpace ?? 'srgb',
            toneMapping: probe.canvasToneMapping ?? 'standard',
            canvasFormat: probe.canvasFormat ?? 'bgra8unorm',
            ...(probe.canvasColorFallback ? { reason: probe.canvasColorFallback } : {}),
        });
        // Only on readiness: later changes come back through apply().
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [rendererReady]);

    useEffect(() => {
        if (!isRecording && pending.current !== null) void apply(pending.current);
    }, [isRecording, apply]);

    const setDisplayP3 = useCallback((enabled: boolean) => {
        setState(enabled);
        saveDisplayP3(enabled);
        void apply(enabled);
    }, [apply]);

    return {
        displayP3,
        setDisplayP3,
        status: statusOf(displayP3, result),
        hdrActive: !result?.deferred && result?.toneMapping === 'extended' && result.canvasFormat === 'rgba16float',
    };
}
