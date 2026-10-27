import { useEffect } from 'react';
import { ShaderEntry } from '../renderer/types';
import { ShaderApi } from '../services/shaderApi';
import { resolveShaderUrl } from '../utils/resolveShaderUrl';
import { determineCategory } from '../app/constants/shaderCatalogUtils';
import {
    catalogExclusionReason,
    inferRequiresRgba32Float,
    type DeviceFormatCapabilities,
} from '../config/formatPolicy';

export interface UseShaderCatalogLoadOptions {
    setAvailableModes: React.Dispatch<React.SetStateAction<ShaderEntry[]>>;
    setShadersReady: React.Dispatch<React.SetStateAction<boolean>>;
    setStatus: (status: string) => void;
    rendererReady: boolean;
    supportsDeepWorkgroup: boolean;
    availableModes: ShaderEntry[];
    /** Measured format capabilities once the renderer is ready (#1512 catalog exclusions). */
    getFormatCapabilities?: () => DeviceFormatCapabilities | undefined;
}

export function useShaderCatalogLoad({
    setAvailableModes,
    setShadersReady,
    setStatus,
    rendererReady,
    supportsDeepWorkgroup,
    availableModes,
    getFormatCapabilities,
}: UseShaderCatalogLoadOptions): void {
    useEffect(() => {
        let isMounted = true;

        const loadShaders = async () => {
            try {
                const apiShaders = await ShaderApi.getShaderList();
                if (!isMounted) return;

                const entries: ShaderEntry[] = apiShaders.map(shader => ({
                    id: shader.id,
                    name: shader.name || shader.id,
                    url: shader.url || resolveShaderUrl(`shaders/${shader.id}.wgsl`),
                    category: determineCategory(shader),
                    description: shader.description || '',
                    tags: shader.tags || [],
                    rating: shader.rating,
                    hasErrors: shader.has_errors,
                    requiresDeepWorkgroup: shader.requiresDeepWorkgroup === true,
                    requiresHistoryRing: shader.requiresHistoryRing === true,
                    requiresRgba32Float: inferRequiresRgba32Float({
                        id: shader.id,
                        requiresRgba32Float: shader.requiresRgba32Float === true,
                    }),
                    params: shader.params ?? [],
                }));

                setAvailableModes(entries);
                setShadersReady(true);
            } catch (error) {
                if (!isMounted) return;
                console.warn('Failed to load shaders:', error);
                setShadersReady(true);
                setStatus('⚠️ Could not load shader list. Some effects may be unavailable.');
            }
        };

        void loadShaders();
        return () => { isMounted = false; };
    }, [setAvailableModes, setShadersReady, setStatus]);

    useEffect(() => {
        if (!rendererReady) return;
        const formatCaps = getFormatCapabilities?.();
        const skipped: Record<string, string[]> = {};
        const filtered = availableModes.filter(s => {
            // Without measured caps only the deep-workgroup rule can be judged.
            const reason = formatCaps
                ? catalogExclusionReason(s, { supportsDeepWorkgroup, formatCaps })
                : (s.requiresDeepWorkgroup && !supportsDeepWorkgroup ? 'deep-workgroup' : null);
            if (!reason) return true;
            (skipped[reason] ??= []).push(s.id);
            return false;
        });
        const why: Record<string, string> = {
            'deep-workgroup': 'require deep-workgroup (16×16×4), not supported on this GPU',
            'rgba32float-storage': 'need rgba32float storage, not available on this device (compat / mobile)',
        };
        for (const [reason, ids] of Object.entries(skipped)) {
            console.log(`[Shaders] ${ids.length} shader(s) ${why[reason] ?? reason} — hiding from list: ${ids.join(', ')}`);
        }
        if (filtered.length !== availableModes.length) setAvailableModes(filtered);
    // availableModes.length (not the full array) is intentional: we react when the
    // list grows, but filtering reduces length, so subsequent runs are prevented until
    // more shaders are added.  supportsDeepWorkgroup is stable after renderer init.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [rendererReady, supportsDeepWorkgroup, availableModes.length]);
}
