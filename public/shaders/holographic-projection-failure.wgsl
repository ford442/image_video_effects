// ═══════════════════════════════════════════════════════════════
//  Holographic Projection Failure - Glitchy hologram with interference physics
//  Category: retro-glitch
//  Features: mouse-driven, depth-aware, alpha transparency
//  Physics: Thin-film interference, signal degradation, 60Hz flicker
// ═══════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

// ═══════════════════════════════════════════════════════════════
// Thin-Film Interference Physics
// ═══════════════════════════════════════════════════════════════

const N_AIR: f32 = 1.0;
const N_EMULSION: f32 = 1.52;
const PEPPER_GHOST_REFLECTION: f32 = 0.1;

// Wavelengths (normalized)
const LAMBDA_R: f32 = 650.0 / 750.0;
const LAMBDA_G: f32 = 530.0 / 750.0;
const LAMBDA_B: f32 = 460.0 / 750.0;

// ═══════════════════════════════════════════════════════════════
// Physics Functions
// ═══════════════════════════════════════════════════════════════

fn rand(n: vec2<f32>) -> f32 {
    return fract(sin(dot(n, vec2<f32>(12.9898, 4.1414))) * 43758.5453);
}

// Thin-film interference with degradation
fn thinFilmInterference(opticalPath: f32, wavelength: f32, order: f32, instability: f32) -> f32 {
    // Signal degradation causes phase noise
    let phaseNoise = instability * rand(vec2<f32>(opticalPath, wavelength)) * 0.5;
    let phase = 6.28318 * opticalPath / wavelength + phaseNoise;
    let targetPhase = (order + 0.5) * 6.28318;
    let phaseDiff = phase - targetPhase;
    return cos(phaseDiff) * cos(phaseDiff);
}

// Degraded interference spectrum (signal failure effect)
fn degradedInterference(uv: vec2<f32>, angle: f32, time: f32, instability: f32) -> vec3<f32> {
    // Optical path varies with instability
    let pathNoise = instability * sin(time * 10.0 + uv.y * 50.0) * 0.1;
    let opticalPath = 0.43 + sin(angle + time * 0.2) * 0.08 + pathNoise;
    
    let r = thinFilmInterference(opticalPath, LAMBDA_R, 1.0, instability);
    let g = thinFilmInterference(opticalPath, LAMBDA_G, 1.0, instability);
    let b = thinFilmInterference(opticalPath, LAMBDA_B, 1.0, instability);
    
    // Signal dropout causes color channel loss
    let dropoutR = step(instability * 0.3, rand(vec2<f32>(time, uv.y)));
    let dropoutG = step(instability * 0.3, rand(vec2<f32>(time + 1.0, uv.y)));
    let dropoutB = step(instability * 0.3, rand(vec2<f32>(time + 2.0, uv.y)));
    
    return vec3<f32>(r * dropoutR, g * dropoutG, b * dropoutB);
}

// Projection failure scanlines (erratic)
fn failureScanlines(uv: vec2<f32>, time: f32, instability: f32) -> vec2<f32> {
    // Normal scanline
    let scanFreq = 800.0;
    let scanline = sin(uv.y * scanFreq + time * 5.0) * 0.5 + 0.5;
    
    // V-Hold drift creates rolling bar
    let drift = sin(time * instability * 2.0) * 0.1;
    let rollPos = fract(uv.y + drift + time * 0.1);
    let rollingBar = 1.0 - smoothstep(0.0, 0.1, abs(rollPos - 0.5));
    
    // Alpha modulation
    let scanAlpha = 1.0 - scanline * 0.25 - rollingBar * instability * 0.3;
    
    return vec2<f32>(scanline + rollingBar, scanAlpha);
}

// 60Hz flicker with power instability
fn unstableFlicker(time: f32, instability: f32) -> f32 {
    let baseFlicker = 0.9 + 0.1 * sin(time * 377.0);
    // Power surges cause bright flashes
    let surge = step(0.97, rand(vec2<f32>(time, 0.0))) * instability * 0.5;
    // Brownouts cause dimming
    let brownout = step(rand(vec2<f32>(time * 0.5, 1.0)), instability * 0.2) * 0.3;
    return baseFlicker * (1.0 + surge) * (1.0 - brownout);
}

// ═══════════════════════════════════════════════════════════════
// Main Shader
// ═══════════════════════════════════════════════════════════════

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(coord) / vec2<f32>(dims);

    let instability = u.zoom_params.x;
    let chroma_split = u.zoom_params.y;
    let scan_drift = u.zoom_params.z;
    let static_noise = u.zoom_params.w;

    let time = u.config.y;
    var mouse = u.zoom_config.yz;
    let aspect = f32(dims.x) / f32(dims.y);

    // Mouse Interaction: Stabilize the hologram near the mouse
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);
    let angle = atan2(dist_vec.y, dist_vec.x);

    // Stabilize Factor (1.0 near mouse, 0.0 far away)
    let stability = smoothstep(0.5, 0.0, dist);

    // Net Glitch Level (High far away, Low near mouse)
    let glitch_level = instability * (1.0 - stability);

    // ═══════════════════════════════════════════════════════════════
    // Degraded Interference Physics
    // ═══════════════════════════════════════════════════════════════
    
    let interference = degradedInterference(uv, angle, time, glitch_level);

    // 1. Vertical Sync Drift (V-Hold)
    let y_shift = sin(time * 0.5) * scan_drift * glitch_level;
    let y_jitter = step(0.9, rand(vec2<f32>(time, 0.0))) * (rand(vec2<f32>(time, 1.0)) - 0.5) * glitch_level;
    let drifted_uv = vec2<f32>(uv.x, fract(uv.y + y_shift + y_jitter));

    // 2. Scanline Slicing
    let scan_slice = floor(drifted_uv.y * 50.0);
    let slice_offset = (rand(vec2<f32>(scan_slice, time)) - 0.5) * 0.1 * glitch_level;
    let sliced_uv = vec2<f32>(drifted_uv.x + slice_offset, drifted_uv.y);

    // 3. Chromatic Aberration with interference coloring
    let split_amt = chroma_split * glitch_level * 0.05;
    
    let r = textureSampleLevel(readTexture, u_sampler, sliced_uv + vec2<f32>(split_amt, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sliced_uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, sliced_uv - vec2<f32>(split_amt, 0.0), 0.0).b;

    var color = vec3<f32>(r, g, b);
    
    // Add interference rainbow to glitched areas
    color = mix(color, interference, glitch_level * 0.6);

    // 4. Scanlines with degradation
    let scanEffects = failureScanlines(drifted_uv, time, glitch_level);
    let scanline = 0.5 + 0.5 * sin(drifted_uv.y * 800.0);
    color *= mix(1.0, scanline, 0.5);

    // 5. Static Noise
    let noise = rand(uv * time);
    color += noise * static_noise * glitch_level;

    // 6. Holographic Blue Tint with interference
    let holo_tint = vec3<f32>(0.2, 0.6, 1.0);
    color = mix(color, dot(color, vec3<f32>(0.33)) * holo_tint, glitch_level * 0.5);
    color = mix(color, interference, glitch_level * 0.3);
    
    // ═══════════════════════════════════════════════════════════════
    // Alpha Calculation with Failure Physics
    // ═══════════════════════════════════════════════════════════════
    
    // Base hologram transparency (more transparent when failing)
    let base_alpha = 0.03 * (1.0 + glitch_level * 0.5);
    
    // Diffraction efficiency from degraded interference
    let diffraction_efficiency = (interference.r + interference.g + interference.b) / 3.0;
    
    // Alpha boosted at interference fringes
    var alpha = base_alpha + diffraction_efficiency * 0.35 * (1.0 - glitch_level * 0.3);
    
    // Scanline and failure effects modify alpha
    alpha *= scanEffects.y;
    
    // Signal dropout causes alpha flicker
    let signalDropout = step(glitch_level * 0.4, rand(vec2<f32>(uv.x, time * 5.0)));
    alpha *= signalDropout;
    
    // Unstable flicker
    alpha *= unstableFlicker(time, glitch_level);
    
    // Horizontal tearing alpha effect
    let tearLine = step(0.95, rand(vec2<f32>(floor(uv.y * 100.0), time)));
    alpha *= 1.0 - tearLine * glitch_level * 0.5;
    
    // Pepper's ghost with instability
    let ghost_uv = uv + vec2<f32>(0.003 * glitch_level, 0.002);
    let ghost = textureSampleLevel(readTexture, u_sampler, ghost_uv, 0.0).rgb * interference;
    color = mix(color, ghost, PEPPER_GHOST_REFLECTION * (1.0 + glitch_level));
    
    // Cap alpha
    alpha = min(alpha, 0.45);

    textureStore(writeTexture, coord, vec4<f32>(color, alpha));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, filteringSampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
