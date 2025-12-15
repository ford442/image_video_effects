export type RenderMode = string;

export type ShaderCategory = 'shader' | 'image' | 'video' | 'simulation' | 'feedback' | 'sorting' | 'warp' | 'tessellation' | 'audio' | 'glyph' | 'edge' | 'geometry' | 'artistic' | 'glitch' | 'temporal';

// Added 'webcam'
export type InputSource = 'image' | 'video' | 'webcam';

export interface ShaderEntry {
    id: string;
    name: string;
    url: string;
    category: ShaderCategory;
    description?: string;
    params?: any[];
    advanced_params?: any[];
    features?: string[];
}

export interface SlotParams {
    zoomParam1: number;
    zoomParam2: number;
    zoomParam3: number;
    zoomParam4: number;
    lightStrength: number;
    ambient: number;
    normalStrength: number;
    fogFalloff: number;
    depthThreshold: number;
}
