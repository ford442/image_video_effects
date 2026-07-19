import { useMemo } from 'react';
import type { ShaderMegaMenuOption } from '../../ShaderMegaMenu';
import type { ShaderCategory, ShaderEntry } from '../../../renderer/types';
import type { ShaderCoordData } from '../types';

interface RatedShader {
    id: string;
    stars: number;
    ratingCount: number;
}

export interface UseShaderMenuOptionsArgs {
    availableModes: ShaderEntry[];
    shaderCategory: ShaderCategory;
    coordMap: Record<string, ShaderCoordData>;
    ratedShaders: RatedShader[];
}

export function useShaderMenuOptions({
    availableModes,
    shaderCategory,
    coordMap,
    ratedShaders,
}: UseShaderMenuOptionsArgs) {
    const ratingMap = useMemo(() => {
        const map = new Map<string, { stars: number; ratingCount: number }>();
        for (const shader of ratedShaders) {
            map.set(shader.id, { stars: shader.stars, ratingCount: shader.ratingCount });
        }
        return map;
    }, [ratedShaders]);

    const currentModes = useMemo(() => {
        if (shaderCategory === 'image') {
            return availableModes.filter(entry => entry.category !== 'generative');
        }
        return availableModes.filter(entry => entry.category === shaderCategory);
    }, [availableModes, shaderCategory]);

    const slotMenuOptions = useMemo(
        () => currentModes.map((mode): ShaderMegaMenuOption => {
            const rating = ratingMap.get(mode.id);
            return {
                id: mode.id,
                name: mode.name,
                coordinate: coordMap[mode.id]?.coordinate ?? null,
                category: coordMap[mode.id]?.category ?? mode.category,
                stars: rating?.stars,
                ratingCount: rating?.ratingCount,
            };
        }),
        [currentModes, coordMap, ratingMap]
    );

    const generativeMenuOptions = useMemo(
        () => availableModes
            .filter(mode => mode.category === 'generative')
            .map((mode): ShaderMegaMenuOption => {
                const rating = ratingMap.get(mode.id);
                return {
                    id: mode.id,
                    name: mode.name,
                    coordinate: coordMap[mode.id]?.coordinate ?? null,
                    category: coordMap[mode.id]?.category ?? mode.category,
                    stars: rating?.stars,
                    ratingCount: rating?.ratingCount,
                };
            }),
        [availableModes, coordMap, ratingMap]
    );

    return {
        ratingMap,
        currentModes,
        slotMenuOptions,
        generativeMenuOptions,
    };
}
