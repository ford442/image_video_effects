export type RenderMode = string;

<<<<<<< HEAD
export type ShaderCategory = 'shader' | 'image' | 'video';
=======
export type ShaderCategory = 'shader' | 'image' | 'video' | 'simulation' | 'feedback' | 'sorting' | 'warp' | 'tessellation' | 'audio' | 'glyph' | 'edge' | 'geometry' | 'artistic' | 'glitch' | 'temporal';
>>>>>>> origin/stack-shaders-13277186508483700298

export type InputSource = 'image' | 'video';

export interface ShaderEntry {
    id: string;
    name: string;
    url: string;
    category: ShaderCategory;
<<<<<<< HEAD
=======
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
    // Add Infinite Zoom params here if they are per-slot?
    // Current code mixes them. For now let's stick to the generic 4 + Infinite Zoom specific ones if needed.
    // The user asked for "sliders" to select which shader uses them.
    lightStrength: number;
    ambient: number;
    normalStrength: number;
    fogFalloff: number;
    depthThreshold: number;
>>>>>>> origin/stack-shaders-13277186508483700298
}
