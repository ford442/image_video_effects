// --- Webcam Fun Shaders ---
export const WEBCAM_FUN_SHADERS = [
    'liquid', 'liquid-chrome-ripple', 'liquid-rainbow', 'liquid-swirl',
    'neon-pulse', 'neon-edge-pulse', 'neon-fluid-warp', 'neon-warp',
    'vortex', 'vortex-distortion', 'vortex-warp', 'chroma-vortex',
    'distortion', 'chromatic-folds', 'holographic-projection', 'cyber-glitch-hologram',
    'kaleidoscope', 'kaleido-scope', 'fractal-kaleidoscope', 'astral-kaleidoscope',
    'rgb-fluid', 'rgb-ripple-distortion', 'rgb-shift-brush',
    'pixel-sorter', 'pixel-sort-glitch', 'ascii-shockwave',
    'magnetic-field', 'magnetic-pixels', 'magnetic-rgb'
];

// --- Shader Parameter Defaults ---
// Hardcoded defaults for shaders where API returns generic 0.5 values
// Format: shader_id -> [param1, param2, param3, param4, param5, param6]
export const SHADER_DEFAULTS: Record<string, number[]> = {
    // Liquid shaders - tuned for fluid dynamics
    'liquid': [0.35, 0.50, 0.30, 0.50],           // surfaceTension, gravityScale, damping, turbidity
    'liquid-chrome-ripple': [0.40, 0.60, 0.25, 0.45],
    'liquid-rainbow': [0.50, 0.40, 0.35, 0.60],
    'liquid-swirl': [0.45, 0.55, 0.30, 0.40],
    'liquid-viscous': [0.60, 0.30, 0.50, 0.35],
    
    // Distortion shaders
    'distortion': [0.40, 0.50, 0.30, 0.45],
    'vortex': [0.50, 0.40, 0.60, 0.35],
    'vortex-distortion': [0.45, 0.45, 0.55, 0.40],
    'vortex-warp': [0.40, 0.50, 0.50, 0.45],
    'chroma-vortex': [0.35, 0.55, 0.45, 0.50],
    
    // Chromatic/Color shaders
    'chromatic-folds': [0.45, 0.40, 0.50, 0.35],
    'chromatic-aberration': [0.30, 0.50, 0.40, 0.45],
    'rgb-fluid': [0.40, 0.35, 0.55, 0.45],
    'rgb-ripple-distortion': [0.35, 0.45, 0.50, 0.40],
    'rgb-shift-brush': [0.50, 0.30, 0.45, 0.55],
    
    // Neon/Glow shaders
    'neon-pulse': [0.60, 0.40, 0.50, 0.35],
    'neon-edge-pulse': [0.55, 0.45, 0.40, 0.50],
    'neon-fluid-warp': [0.45, 0.55, 0.35, 0.45],
    'neon-warp': [0.50, 0.50, 0.40, 0.40],
    
    // Kaleidoscope/Geometric
    'kaleidoscope': [0.40, 0.50, 0.45, 0.35],
    'kaleido-scope': [0.45, 0.40, 0.50, 0.40],
    'fractal-kaleidoscope': [0.35, 0.55, 0.40, 0.45],
    'astral-kaleidoscope': [0.50, 0.35, 0.45, 0.50],
    
    // Glitch/Effects
    'pixel-sorter': [0.40, 0.45, 0.55, 0.35],
    'pixel-sort-glitch': [0.35, 0.50, 0.45, 0.40],
    'ascii-shockwave': [0.45, 0.40, 0.50, 0.45],
    'cyber-glitch-hologram': [0.50, 0.35, 0.40, 0.55],
    
    // Magnetic/Field shaders
    'magnetic-field': [0.40, 0.50, 0.35, 0.50],
    'magnetic-pixels': [0.45, 0.40, 0.50, 0.40],
    'magnetic-rgb': [0.35, 0.55, 0.45, 0.35],
    
    // Projection/3D effects
    'holographic-projection': [0.45, 0.45, 0.40, 0.50],
    
    // Generative shaders (common defaults)
    'gen-orb': [0.50, 0.40, 0.60, 0.35],
    'gen-grid': [0.40, 0.50, 0.45, 0.40],
    'gen-neuro-kinetic-bloom': [0.50, 0.35, 0.55, 0.40],
    'gen-quantum-foam': [0.45, 0.45, 0.40, 0.50],
    'gen-crystal-caverns': [0.35, 0.55, 0.45, 0.35],
    'gen-fractal-clockwork': [0.50, 0.40, 0.50, 0.40],
    // Showcase-optimized generative shaders
    'gen-showcase-nebula-core': [0.50, 0.30, 0.40, 0.20],
    'gen-showcase-kinetic-bloom': [0.50, 0.30, 0.40, 0.30],
    'gen-showcase-crystalline-pulse': [0.50, 0.30, 0.50, 0.20],
    'molten-gold': [0.50, 0.50, 0.50, 0.50],
    'galaxy': [0.50, 0.40, 0.60, 0.35],
    'plasma': [0.45, 0.55, 0.40, 0.45],
    
    // Interactive/Mouse shaders
    'cmyk-halftone-interactive': [0.40, 0.50, 0.35, 0.45],
    'interactive-rgb-split': [0.35, 0.45, 0.50, 0.40],
    'interactive-zoom-blur': [0.50, 0.40, 0.45, 0.35],
    'mouse-pixel-sort': [0.40, 0.35, 0.55, 0.45],
    'magnetic-interference': [0.45, 0.50, 0.40, 0.35],
    
    // Artistic/Painterly
    'artistic_painterly_oil': [0.50, 0.40, 0.45, 0.50],
    'double-exposure-zoom': [0.40, 0.50, 0.35, 0.45],
    'halftone-reveal': [0.45, 0.40, 0.50, 0.35],
    'rorschach-inkblot': [0.50, 0.45, 0.40, 0.50],
    
    // Simulation/Physics
    'reaction-diffusion': [0.40, 0.50, 0.45, 0.35],
    'physarum': [0.50, 0.40, 0.60, 0.45],
    'lenia': [0.45, 0.45, 0.50, 0.40],
    'navier-stokes-dye': [0.40, 0.50, 0.35, 0.50],
    
    // Lighting/Glow
    'bloom': [0.50, 0.40, 0.55, 0.35],
    'dynamic-lens-flares': [0.45, 0.50, 0.40, 0.45],
    'chromatic-crawler': [0.40, 0.45, 0.50, 0.35],
    
    // Image processing effects
    'digital-haze': [0.50, 0.40, 0.45, 0.35],
    
    // Generative: Crystalline Chrono-Dyson (Panel Density, Quasar Glow, Flux Speed, Swarm Count)
    'gen-crystalline-chrono-dyson': [0.40, 0.55, 0.50, 0.45],
};

// Helper to get shader defaults - tries multiple ID variations for matching
export function getShaderDefaults(shaderId: string, numParams: number = 4): number[] {
    // Try multiple variations of the shader ID
    const variations = [
        shaderId,                                    // exact match
        shaderId.replace('.wgsl', ''),              // strip .wgsl extension if present
        `${shaderId}.wgsl`,                         // with .wgsl
        shaderId.replace(/-/g, '_'),                // snake_case
        shaderId.replace(/_/g, '-'),                // kebab-case
        shaderId.replace(/^gen[-_]/, 'gen-'),       // normalize gen prefix
    ];
    
    for (const key of variations) {
        const defaults = SHADER_DEFAULTS[key];
        if (defaults) {
            return [...defaults, ...Array(4 - defaults.length).fill(0.5)].slice(0, numParams);
        }
    }
    
    return Array(numParams).fill(0.5);
}
