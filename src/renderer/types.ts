export type RenderMode = string;

export type ShaderCategory =
    | 'shader'
    | 'image'
    | 'video'
    | 'simulation'
    | 'feedback'
    | 'sorting'
    | 'warp'
    | 'tessellation'
    | 'audio'
    | 'glyph'
    | 'edge'
    | 'geometry'
    | 'artistic'
    | 'glitch'
    | 'temporal'
    | 'generative'
    | 'distortion'
    | 'geometric'
    | 'interactive-mouse'
    | 'lighting-effects'
    | 'liquid-effects'
    | 'retro-glitch'
    | 'visual-effects'
    | 'post-processing';

// Added 'webcam', 'generative', and 'live' (HLS streaming)
export type InputSource = 'image' | 'video' | 'webcam' | 'generative' | 'live';

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
    zoomParam5: number;
    zoomParam6: number;
    lightStrength: number;
    ambient: number;
    normalStrength: number;
    fogFalloff: number;
    depthThreshold: number;
}

// ── Slot Parallelization Mode ────────────────────────────────────────────────
// 'chained': Sequential - output of slot N feeds into slot N+1 (default)
// 'parallel': Concurrent - runs independently, all read from same input
//
// Parallel slots enable GPU work overlap for independent effects:
// Example: Parallel background plasma + foreground particles
// Chained is correct for layered effects like liquid → distortion

export type SlotMode = 'chained' | 'parallel';

export interface ShaderSlot {
    shaderId: string | null;
    enabled: boolean;
    mode: SlotMode;
}

// ── WebGPU Uniform Buffer Layout ────────────────────────────────────────────
// Matches the WGSL Uniforms struct used by all compute shaders

export interface UniformConfig {
    /** Time in seconds */ 
    time: number;
    /** Number of active ripples */
    rippleCount: number;
    /** Canvas width */
    resX: number;
    /** Canvas height */
    resY: number;
}

export interface UniformZoomConfig {
    /** Time in seconds (duplicate for compatibility) */
    time: number;
    /** Mouse X position (0-1) */
    mouseX: number;
    /** Mouse Y position (0-1) */
    mouseY: number;
    /** Mouse down state (1=pressed, 0=released) */
    mouseDown: number;
}

export interface UniformZoomParams {
    /** Parameter 1 (x) - mapped to UI slider */
    x: number;
    /** Parameter 2 (y) - mapped to UI slider */
    y: number;
    /** Parameter 3 (z) - mapped to UI slider */
    z: number;
    /** Parameter 4 (w) - mapped to UI slider */
    w: number;
}

export interface UniformRipple {
    /** Normalized X position (0-1) */
    x: number;
    /** Normalized Y position (0-1) */
    y: number;
    /** Start time in seconds */
    startTime: number;
    /** Unused padding */
    _padding: number;
}

/** Complete uniforms structure matching WGSL */
export interface Uniforms {
    config: UniformConfig;
    zoom_config: UniformZoomConfig;
    zoom_params: UniformZoomParams;
    ripples: UniformRipple[];
}

/** GPU buffer layout constants */
export const UNIFORM_BUFFER_LAYOUT = {
    /** config: vec4<f32> = 16 bytes */
    CONFIG_OFFSET: 0,
    /** zoom_config: vec4<f32> = 16 bytes */
    ZOOM_CONFIG_OFFSET: 16,
    /** zoom_params: vec4<f32> = 16 bytes */
    ZOOM_PARAMS_OFFSET: 32,
    /** ripples: array<vec4<f32>, 50> = 800 bytes */
    RIPPLES_OFFSET: 48,
    /** Total: 848 bytes */
    TOTAL_SIZE: 848,
    /** Maximum ripples */
    MAX_RIPPLES: 50,
} as const;
