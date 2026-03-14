// ═══════════════════════════════════════════════════════════════
//  Holographic Glitch - Futuristic hologram with interference physics
//  Category: retro-glitch
//  Features: mouse-driven, depth-aware, alpha transparency
//  Physics: Thin-film interference, diffraction efficiency, 60Hz flicker
//  Description: Simulates unstable holographic projection with RGB separation,
//               scanlines, chromatic aberration, and digital artifacts
// ═══════════════════════════════════════════════════════════════

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

struct Uniforms {
  config: vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=mouseX, y=mouseY, z=unused, w=unused
  zoom_params: vec4<f32>,  // x=glitchIntensity, y=scanlineSpeed, z=rgbShift, w=flicker
  ripples: array<vec4<f32>, 50>,
};

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
// Helper Functions
// ═══════════════════════════════════════════════════════════════

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash13(p: vec3<f32>) -> f32 {
    let p3 = fract(p * 0.1031);
    let p3_dot = dot(vec3<f32>(p3.x, p3.y, p3.z), vec3<f32>(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y + p3.z) * p3_dot);
}

// Thin-film interference calculation
fn thinFilmInterference(opticalPath: f32, wavelength: f32, order: f32) -> f32 {
    let phase = 6.28318 * opticalPath / wavelength;
    let targetPhase = (order + 0.5) * 6.28318;
    let phaseDiff = phase - targetPhase;
    return cos(phaseDiff) * cos(phaseDiff);
}

// Diffraction efficiency with wavelength dependence
fn diffractionEfficiency(angle: f32, wavelength: f32) -> f32 {
    let braggAngle = wavelength * 0.5;
    let angleDiff = abs(angle - braggAngle);
    return exp(-angleDiff * angleDiff * 30.0);
}

// Interference spectrum calculation
fn interferenceSpectrum(uv: vec2<f32>, angle: f32, time: f32, glitch: f32) -> vec3<f32> {
    // Glitch causes interference pattern distortion
    let distortedPath = 0.43 + sin(angle * 3.0 + time + glitch * 5.0) * 0.08;
    
    let r = thinFilmInterference(distortedPath, LAMBDA_R, 1.0) * diffractionEfficiency(angle, LAMBDA_R);
    let g = thinFilmInterference(distortedPath, LAMBDA_G, 1.0) * diffractionEfficiency(angle, LAMBDA_G);
    let b = thinFilmInterference(distortedPath, LAMBDA_B, 1.0) * diffractionEfficiency(angle, LAMBDA_B);
    
    return vec3<f32>(r, g, b);
}

// Holographic scanline with alpha modulation
fn holographicScanline(uv: vec2<f32>, time: f32, speed: f32, intensity: f32) -> vec2<f32> {
    let scanlinePos = fract(uv.y * 200.0 - time * speed * 2.0);
    let scanline = smoothstep(0.3, 0.5, scanlinePos) - smoothstep(0.5, 0.7, scanlinePos);
    
    // Alpha modulation from scanlines (darker lines = more transparent)
    let scanAlpha = 1.0 - scanline * 0.2;
    
    return vec2<f32>(scanline, scanAlpha);
}

// 60Hz flicker + glitch flicker
fn projectionFlicker(time: f32, glitchFlicker: f32) -> f32 {
    let baseFlicker = 0.92 + 0.08 * sin(time * 377.0); // 60Hz
    let glitchPulse = 1.0 - glitchFlicker * 0.3 * (sin(time * 30.0) * 0.5 + 0.5);
    return baseFlicker * glitchPulse;
}

// ═══════════════════════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════════════════════
const GLITCH_BLOCK_FREQUENCY: f32 = 5.0;
const GRID_SIZE: f32 = 50.0;

// ═══════════════════════════════════════════════════════════════
// Main Shader
// ═══════════════════════════════════════════════════════════════

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    
    // Get depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Parameters
    let glitchIntensity = u.zoom_params.x;
    let scanlineSpeed = u.zoom_params.y;
    let rgbShift = u.zoom_params.z;
    let flicker = u.zoom_params.w;
    
    // Random glitch blocks
    let blockTime = floor(time * GLITCH_BLOCK_FREQUENCY);
    let blockY = floor(uv.y * 20.0);
    let glitchBlock = hash(vec2<f32>(blockY, blockTime));
    
    // Apply horizontal displacement glitch
    var glitchedUV = uv;
    if (glitchBlock > (1.0 - glitchIntensity * 0.3)) {
        let displacement = (hash(vec2<f32>(blockY, blockTime + 0.5)) - 0.5) * glitchIntensity * 0.2;
        glitchedUV.x += displacement;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // Interference-based RGB chromatic aberration
    // ═══════════════════════════════════════════════════════════════
    
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let interference = interferenceSpectrum(uv, angle, time, glitchIntensity);
    
    // Depth-aware aberration with interference coloring
    let aberrationAmount = rgbShift * 0.01 * (1.0 + depth * 0.5);
    let r = textureSampleLevel(readTexture, u_sampler, glitchedUV + vec2<f32>(aberrationAmount, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, glitchedUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, glitchedUV - vec2<f32>(aberrationAmount, 0.0), 0.0).b;
    
    var color = vec3<f32>(r, g, b);
    
    // Apply interference rainbow tint to glitched areas
    color = mix(color, color * (1.0 + interference), glitchIntensity * 0.5);
    
    // ═══════════════════════════════════════════════════════════════
    // Holographic Scanlines with Alpha
    // ═══════════════════════════════════════════════════════════════
    
    let scanEffects = holographicScanline(uv, time, scanlineSpeed, 0.3);
    let scanline = scanEffects.x;
    color = color + vec3<f32>(0.0, 0.3, 0.5) * scanline * 0.3;
    
    // Horizontal scan interference
    let interferenceLines = sin(uv.y * 100.0 + time * 10.0 * scanlineSpeed) * 0.5 + 0.5;
    color = color * (1.0 - interferenceLines * 0.05);
    
    // Vertical sync glitch
    let vsyncGlitch = step(0.98, hash(vec2<f32>(floor(time * 2.0), 0.0)));
    if (vsyncGlitch > 0.5) {
        let offset = (hash(vec2<f32>(floor(time * 2.0), 1.0)) - 0.5) * glitchIntensity * 0.3;
        glitchedUV.y += offset;
        color = textureSampleLevel(readTexture, u_sampler, glitchedUV, 0.0).rgb;
    }
    
    // Digital artifact noise
    let noise = hash13(vec3<f32>(uv * resolution, time * 10.0));
    if (noise > (1.0 - glitchIntensity * 0.1)) {
        color = vec3<f32>(noise) * (1.0 + interference * 0.5);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // Alpha Calculation with Physics
    // ═══════════════════════════════════════════════════════════════
    
    // Base hologram transparency
    let base_alpha = 0.04;
    
    // Diffraction efficiency varies by position and glitch state
    let diffraction_efficiency = (interference.r + interference.g + interference.b) / 3.0;
    
    // Alpha boosted at interference fringes (scanlines, glitches)
    var alpha = base_alpha + diffraction_efficiency * 0.35;
    
    // Glitch causes alpha spikes (signal dropout effect)
    let glitchAlpha = 1.0 - glitchIntensity * 0.2 * step(0.95, hash(vec2<f32>(uv.y, time)));
    alpha *= glitchAlpha;
    
    // Scanline alpha modulation
    alpha *= scanEffects.y;
    
    // Flicker effect (60Hz + glitch flicker)
    alpha *= projectionFlicker(time, flicker);
    
    // Edge hologram effect - alpha varies at edges
    let edgeX = smoothstep(0.0, 0.05, uv.x) * smoothstep(1.0, 0.95, uv.x);
    let edgeY = smoothstep(0.0, 0.05, uv.y) * smoothstep(1.0, 0.95, uv.y);
    let edgeFade = edgeX * edgeY;
    alpha *= (0.5 + edgeFade * 0.5);
    
    // Holographic tint with interference
    color = color + vec3<f32>(0.0, 0.15, 0.25) * (1.0 - depth * 0.5) * interference.b;
    
    // Grid overlay
    let grid = abs(fract(uv.x * GRID_SIZE) - 0.5) < 0.05 || abs(fract(uv.y * GRID_SIZE) - 0.5) < 0.05;
    if (grid) {
        color = color + vec3<f32>(0.0, 0.2, 0.3) * 0.1;
        alpha += 0.05; // Grid lines slightly more opaque
    }
    
    // Temporal persistence for trail effect
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let blended = mix(vec4<f32>(color, alpha), prev, 0.3);
    textureStore(dataTextureA, gid.xy, blended);
    
    // Add subtle scan interference to persistence
    color = max(color, prev.rgb * 0.5);
    
    // Pepper's ghost reflection
    let ghost_uv = uv + vec2<f32>(0.003, 0.003) * (1.0 - depth);
    let ghost = textureSampleLevel(readTexture, u_sampler, ghost_uv, 0.0).rgb;
    color = mix(color, ghost * interference, PEPPER_GHOST_REFLECTION * glitchIntensity);
    
    // Holographic speckle
    let speckle = hash(uv * 150.0 + time);
    alpha *= 0.94 + speckle * 0.12;
    
    // Cap alpha
    alpha = min(alpha, 0.5);
    
    // Output
    textureStore(writeTexture, gid.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
