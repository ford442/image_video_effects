import { useEffect } from 'react';
import { ShaderEntry } from '../renderer/types';
import { ShaderApi } from '../services/shaderApi';
import { resolveShaderUrl } from '../utils/resolveShaderUrl';
import { determineCategory } from '../app/constants/shaderCatalogUtils';

export interface UseShaderCatalogLoadOptions {
    setAvailableModes: React.Dispatch<React.SetStateAction<ShaderEntry[]>>;
    setShadersReady: React.Dispatch<React.SetStateAction<boolean>>;
    setStatus: (status: string) => void;
    rendererReady: boolean;
    supportsDeepWorkgroup: boolean;
    availableModes: ShaderEntry[];
}

export function useShaderCatalogLoad({
    setAvailableModes,
    setShadersReady,
    setStatus,
    rendererReady,
    supportsDeepWorkgroup,
    availableModes,
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
                    params: (shader.params || []).map((p: { id?: string; name?: string; label?: string; default?: number; min?: number; max?: number; step?: number; labels?: string[] }, idx: number) => ({
                        id: p.id || p.name || `param${idx + 1}`,
                        name: p.label || p.name || `Parameter ${idx + 1}`,
                        default: p.default ?? 0.5,
                        min: p.min ?? 0,
                        max: p.max ?? 1,
                        step: p.step ?? 0.01,
                        labels: p.labels,
                    })),
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

        loadShaders();
        return () => { isMounted = false; };
    }, [setAvailableModes, setShadersReady, setStatus]);

    useEffect(() => {
        if (!rendererReady || supportsDeepWorkgroup) return;
        const skipped: string[] = [];
        const filtered = availableModes.filter(s => {
            if (s.requiresDeepWorkgroup) {
                skipped.push(s.id);
                return false;
            }
            return true;
        });
        if (skipped.length > 0) {
            console.log(
                `[Shaders] ${skipped.length} shader(s) require deep-workgroup (16×16×4) ` +
                `which is not supported on this GPU — hiding from list: ${skipped.join(', ')}`
            );
            setAvailableModes(filtered);
        }
    // availableModes.length (not the full array) is intentional: we react when the
    // list grows, but filtering reduces length, so subsequent runs are prevented until
    // more shaders are added.  supportsDeepWorkgroup is stable after renderer init.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [rendererReady, supportsDeepWorkgroup, availableModes.length]);
}
