export type RenderMode = string;

export type ShaderCategory = 'shader' | 'image' | 'video' | 'simulation' | 'feedback' | 'sorting' | 'warp' | 'tessellation' | 'audio' | 'glyph' | 'edge' | 'geometry' | 'artistic' | 'glitch' | 'temporal';

// Added 'webcam'
export type InputSource = 'image' | 'video' | 'webcam';

export interface ShaderParam {
    id: string;
    name: string;
    default: number;
    min: number;
    max: number;
    step?: number;
    labels?: string[];
}

export interface ShaderEntry {
    id: string;
    name: string;
    url: string;
    category: ShaderCategory;
    description?: string;
    tags?: string[];
    params?: ShaderParam[];
    advanced_params?: ShaderParam[];
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