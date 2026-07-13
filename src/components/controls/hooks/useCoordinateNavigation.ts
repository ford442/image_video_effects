import React, { useState, useEffect, useMemo, useCallback, useRef } from 'react';
import { RenderMode, ShaderEntry } from '../../../renderer/types';
// @ts-ignore
import shaderCoordinates from '../../../shader_coordinates.json';
import type { ShaderCoordData } from '../types';

export interface ZoneGroup {
    label: string;
    min: number;
    max: number;
    color: string;
    shaders: { id: string; data: ShaderCoordData }[];
}

export interface UseCoordinateNavigationOptions {
    availableModes: ShaderEntry[];
    activeSlot: number;
    setMode: (index: number, mode: RenderMode) => void;
}

export interface UseCoordinateNavigationReturn {
    coordMap: Record<string, ShaderCoordData>;
    getShaderCoordinate: (id: string) => number | null;
    findShaderByCoordinate: (targetCoord: number) => string | null;
    getZoneColor: (coord: number) => string;
    shadersByZone: ZoneGroup[];
    showCoordinateBrowser: boolean;
    setShowCoordinateBrowser: React.Dispatch<React.SetStateAction<boolean>>;
    showNumberOverlay: boolean;
    typedNumber: string;
}

export function getZoneColor(coord: number): string {
    if (coord < 100) return '#1a5276';
    if (coord < 250) return '#1e8449';
    if (coord < 400) return '#2874a6';
    if (coord < 550) return '#8e44ad';
    if (coord < 700) return '#c0392b';
    if (coord < 850) return '#d35400';
    return '#7d3c98';
}

export function useCoordinateNavigation({
    availableModes,
    activeSlot,
    setMode,
}: UseCoordinateNavigationOptions): UseCoordinateNavigationReturn {
    const [showCoordinateBrowser, setShowCoordinateBrowser] = useState(false);
    const [typedNumber, setTypedNumber] = useState('');
    const [showNumberOverlay, setShowNumberOverlay] = useState(false);
    const numberTimeoutRef = useRef<NodeJS.Timeout | null>(null);

    const coordMap = useMemo(() => shaderCoordinates as Record<string, ShaderCoordData>, []);

    const getShaderCoordinate = useCallback((id: string): number | null => {
        return coordMap[id]?.coordinate ?? null;
    }, [coordMap]);

    const findShaderByCoordinate = useCallback((targetCoord: number): string | null => {
        let closestId: string | null = null;
        let minDiff = Infinity;

        for (const [id, data] of Object.entries(coordMap)) {
            const diff = Math.abs(data.coordinate - targetCoord);
            if (diff < minDiff) {
                minDiff = diff;
                closestId = id;
            }
        }

        return closestId;
    }, [coordMap]);

    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
                return;
            }

            const key = e.key;

            if (/^[0-9]$/.test(key)) {
                e.preventDefault();

                if (numberTimeoutRef.current) {
                    clearTimeout(numberTimeoutRef.current);
                }

                const newNumber = typedNumber + key;
                setTypedNumber(newNumber);
                setShowNumberOverlay(true);

                numberTimeoutRef.current = setTimeout(() => {
                    const coord = parseInt(newNumber, 10);
                    if (!isNaN(coord) && coord >= 0 && coord <= 1000) {
                        const shaderId = findShaderByCoordinate(coord);
                        if (shaderId) {
                            const isAvailable = availableModes.some(m => m.id === shaderId);
                            if (isAvailable) {
                                setMode(activeSlot, shaderId);
                            }
                        }
                    }
                    setTypedNumber('');
                    setShowNumberOverlay(false);
                }, 800);
            } else if (key === 'Escape') {
                if (numberTimeoutRef.current) {
                    clearTimeout(numberTimeoutRef.current);
                }
                setTypedNumber('');
                setShowNumberOverlay(false);
                setShowCoordinateBrowser(false);
            } else if (key === 'b' || key === 'B') {
                if (!(e.target instanceof HTMLInputElement)) {
                    setShowCoordinateBrowser(prev => !prev);
                }
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        return () => {
            window.removeEventListener('keydown', handleKeyDown);
            if (numberTimeoutRef.current) {
                clearTimeout(numberTimeoutRef.current);
            }
        };
    }, [typedNumber, availableModes, activeSlot, setMode, findShaderByCoordinate]);

    const shadersByZone = useMemo(() => {
        const zones: ZoneGroup[] = [
            { label: '🌊 Ambient', min: 0, max: 100, color: '#1a5276', shaders: [] },
            { label: '🌿 Organic', min: 100, max: 250, color: '#1e8449', shaders: [] },
            { label: '👆 Interactive', min: 250, max: 400, color: '#2874a6', shaders: [] },
            { label: '🎨 Artistic', min: 400, max: 550, color: '#8e44ad', shaders: [] },
            { label: '✨ Visual FX', min: 550, max: 700, color: '#c0392b', shaders: [] },
            { label: '📺 Retro', min: 700, max: 850, color: '#d35400', shaders: [] },
            { label: '🌀 Extreme', min: 850, max: 1000, color: '#7d3c98', shaders: [] },
        ];

        for (const [id, data] of Object.entries(coordMap)) {
            const zone = zones.find(z => data.coordinate >= z.min && data.coordinate < z.max);
            if (zone) {
                zone.shaders.push({ id, data });
            }
        }

        zones.forEach(z => z.shaders.sort((a, b) => a.data.coordinate - b.data.coordinate));

        return zones.filter(z => z.shaders.length > 0);
    }, [coordMap]);

    return {
        coordMap,
        getShaderCoordinate,
        findShaderByCoordinate,
        getZoneColor,
        shadersByZone,
        showCoordinateBrowser,
        setShowCoordinateBrowser,
        showNumberOverlay,
        typedNumber,
    };
}
