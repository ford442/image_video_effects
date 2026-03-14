// ═══════════════════════════════════════════════════════════════
//  Holographic Contour - Edge-based hologram with interference physics
//  Category: artistic
//  Features: mouse-driven, depth-aware, alpha transparency
//  Physics: Thin-film interference, diffraction efficiency, 60Hz flicker
// ═══════════════════════════════════════════════════════════════

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

// ═══════════════════════════════════════════════════════════════
// Thin-Film Interference Physics
// ═══════════════════════════════════════════════════════════════

// Refractive indices for common holographic materials
const N_AIR: f32 = 1.0;
const N_EMULSION: f32 = 1.52;  // Typical photographic emulsion
const N_GLASS: f32 = 1.5;
const N_FILM_BASE: f32 = 1.49; // Polyester film base

// Wavelengths for RGB channels (in nanometers, normalized to 0-1 range)
const LAMBDA_R: f32 = 650.0 / 750.0;  // Red ~650nm
const LAMBDA_G: f32 = 530.0 / 750.0;  // Green ~530nm
const LAMBDA_B: f32 = 460.0 / 750.0;  // Blue ~460nm

// Pepper's ghost reflection coefficient
const REFLECTION_COEFF: f32 = 0.1;

// ═══════════════════════════════════════════════════════════════
// Interference Functions
// ═══════════════════════════════════════════════════════════════

// Calculate thin-film interference intensity
// Uses: 2nd = (m + 0.5)λ/n for constructive interference
fn thinFilmInterference(opticalPath: f32, wavelength: f32, order: f32) -> f32 {
    // Phase difference: δ = (2π/λ) * 2nd
    let phase = 6.28318 * opticalPath / wavelength;
    
    // Constructive when phase ≈ (m + 0.5) * 2π
    // Destructive when phase ≈ m * 2π
    let targetPhase = (order + 0.5) * 6.28318;
    let phaseDiff = phase - targetPhase;
    
    // Interference intensity (cosine squared response)
    return cos(phaseDiff) * cos(phaseDiff);
}

// Calculate diffraction efficiency based on wavelength and angle
// Simulates how holographic gratings diffract different wavelengths
fn diffractionEfficiency(uv: vec2<f32>, viewAngle: f32, wavelength: f32) -> f32 {
    // Grating equation: d*sin(θ) = mλ
    // Efficiency varies with angle and wavelength
    let gratingSpacing = 0.001; // 1 micron spacing
    let sinTheta = sin(viewAngle);
    
    // Phase matching condition
    let phaseMatch = abs(sinTheta - wavelength * gratingSpacing * 1000.0);
    
    // Efficiency peaks when phase matches (Bragg condition)
    let efficiency = exp(-phaseMatch * phaseMatch * 100.0);
    
    return efficiency;
}

// Calculate rainbow color from interference pattern
fn interferenceColor(uv: vec2<f32>, mousePos: vec2<f32>, time: f32) -> vec3<f32> {
    let toMouse = uv - mousePos;
    let angle = atan2(toMouse.y, toMouse.x);
    let dist = length(toMouse);
    
    // Viewing angle affects interference
    let viewAngle = angle + time * 0.1;
    
    // Optical path difference (varies with angle for thin film)
    let opticalPath = 320.0 / 750.0 + dist * 0.1; // ~320nm film thickness
    
    // Calculate interference for each channel
    let intR = thinFilmInterference(opticalPath, LAMBDA_R, 1.0);
    let intG = thinFilmInterference(opticalPath, LAMBDA_G, 1.0);
    let intB = thinFilmInterference(opticalPath, LAMBDA_B, 1.0);
    
    // Add some angle-dependent variation
    let angleMod = sin(angle * 3.0 + time) * 0.3;
    
    return vec3<f32>(
        intR * (0.8 + angleMod),
        intG * (0.9 + angleMod * 0.5),
        intB * (1.0 - angleMod * 0.3)
    );
}

// Calculate scanline alpha modulation
fn scanlineAlpha(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
    // Horizontal scanlines at ~600 lines
    let scanPos = uv.y * 600.0;
    let scanline = sin(scanPos + time * 10.0) * 0.5 + 0.5;
    
    // Vertical retrace effect
    let retrace = sin(uv.x * 200.0 - time * 30.0) * 0.5 + 0.5;
    
    return 1.0 - scanline * retrace * intensity * 0.3;
}

// ═══════════════════════════════════════════════════════════════
// Main Shader
// ═══════════════════════════════════════════════════════════════

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dim = textureDimensions(readTexture);
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));

    if (coord.x >= i32(dim.x) || coord.y >= i32(dim.y)) {
        return;
    }

    var uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(dim.x), f32(dim.y));

    // Parameters
    let threshold = u.zoom_params.x;     // Edge Threshold
    let glow_strength = u.zoom_params.y; // Glow Strength
    let shift_amount = u.zoom_params.z;  // Hologram Shift
    let dim_bg = u.zoom_params.w;        // Darken Background

    // Mouse Position
    let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let time = u.config.x;

    // Sobel Edge Detection
    let dx = vec2<i32>(1, 0);
    let dy = vec2<i32>(0, 1);

    let c = textureLoad(readTexture, coord, 0).rgb;
    let l = textureLoad(readTexture, coord - dx, 0).rgb;
    let r = textureLoad(readTexture, coord + dx, 0).rgb;
    let t = textureLoad(readTexture, coord - dy, 0).rgb;
    let b = textureLoad(readTexture, coord + dy, 0).rgb;

    let edge_x = length(r - l);
    let edge_y = length(b - t);
    let edge = sqrt(edge_x * edge_x + edge_y * edge_y);

    // ═══════════════════════════════════════════════════════════════
    // Holographic Transparency & Interference Physics
    // ═══════════════════════════════════════════════════════════════
    
    // Base transparency: holograms are mostly invisible
    let base_alpha = 0.03;
    
    // Calculate interference color (rainbow effect from diffraction)
    let interference = interferenceColor(uv, mouse_pos, time);
    
    // Diffraction efficiency at edges (where hologram fringes are visible)
    var diffraction_efficiency = 0.0;
    
    var final_color = c * (1.0 - dim_bg * 0.5);
    var alpha = base_alpha;

    if (edge > threshold) {
        // Edge represents interference fringes in hologram
        let to_mouse = uv - mouse_pos;
        let angle = atan2(to_mouse.y, to_mouse.x);
        
        // Calculate diffraction efficiency based on angle
        let viewAngle = angle + time * 0.2;
        diffraction_efficiency = diffractionEfficiency(uv, viewAngle, 0.5);
        
        // Enhanced edge intensity from interference
        let edge_intensity = (edge - threshold) * 3.0;
        
        // Interference creates rainbow colors at edges
        let hue = fract(angle / 6.28 + time * 0.1);
        
        // Spectral colors from thin-film interference
        let r_val = 0.5 + 0.5 * cos(6.28 * (hue + 0.0));
        let g_val = 0.5 + 0.5 * cos(6.28 * (hue + 0.33));
        let b_val = 0.5 + 0.5 * cos(6.28 * (hue + 0.67));
        
        // Combine with physics-based interference
        let edge_color = vec3<f32>(r_val, g_val, b_val) * interference * glow_strength;
        
        // Boost alpha where light is diffracted (interference fringes)
        let fringe_alpha = base_alpha + diffraction_efficiency * 0.35 * edge_intensity;
        
        // Additive blend for holographic glow
        final_color += edge_color * edge_intensity;
        alpha = min(fringe_alpha, 0.5); // Cap max alpha for transparency
    }
    
    // ═══════════════════════════════════════════════════════════════
    // Projection Effects
    // ═══════════════════════════════════════════════════════════════
    
    // 60Hz flicker typical of holographic projectors
    let flicker = 0.92 + 0.08 * sin(time * 377.0); // 60Hz = 377 rad/s
    alpha *= flicker;
    
    // Scanline alpha modulation
    let scanAlpha = scanlineAlpha(uv, time, 0.5);
    alpha *= scanAlpha;
    
    // Pepper's ghost reflection (subtle double image)
    let ghost_offset = 0.003;
    let ghost_uv = uv + vec2<f32>(ghost_offset);
    let ghost_color = textureSampleLevel(readTexture, u_sampler, ghost_uv, 0.0).rgb;
    final_color = mix(final_color, ghost_color * interference, REFLECTION_COEFF * 0.3);
    
    // Temporal noise (holographic speckle)
    let speckle = fract(sin(dot(uv + time * 0.1, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    alpha *= 0.95 + speckle * 0.1;

    // Output with calculated alpha
    textureStore(writeTexture, coord, vec4<f32>(final_color, alpha));
    
    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
