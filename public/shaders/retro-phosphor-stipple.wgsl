// ═══════════════════════════════════════════════════════════════════
//  retro-phosphor-stipple
//  Category: advanced-hybrid
//  Features: crt-simulation, blue-noise-stippling, temporal-persistence, mouse-driven
//  Complexity: High
//  Chunks From: retro_phosphor_dream (barrel distortion, scanlines, persistence), spec-blue-noise-stipple (blue-noise dots)
//  Created: 2026-04-18
//  By: Agent CB-6 — Alpha & Post-Process Enhancer
// ═══════════════════════════════════════════════════════════════════
//  CRT Phosphor with Blue-Noise Stippling
//  Authentic CRT barrel distortion, scanlines, and phosphor persistence
//  combined with blue-noise distributed phosphor dots. Each RGB channel
//  gets its own blue-noise jittered dot grid for authentic triad feel
//  without regular stripe banding.
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// ═══ CHUNK: hash (from retro_phosphor_dream.wgsl) ═══
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// ═══ CHUNK: barrel distortion (from retro_phosphor_dream.wgsl) ═══
fn barrelDistort(uv: vec2<f32>, strength: f32) -> vec2<f32> {
    let centered = uv - 0.5;
    let r2 = dot(centered, centered);
    let distortion = 1.0 + strength * r2;
    return centered * distortion + 0.5;
}

fn barrelUndistort(uv: vec2<f32>, strength: f32) -> vec2<f32> {
    let centered = uv - 0.5;
    let r2 = dot(centered, centered);
    let distortion = 1.0 / (1.0 + strength * r2);
    return centered * distortion + 0.5;
}

// ═══ CHUNK: scanlines (from retro_phosphor_dream.wgsl) ═══
fn scanlines(uv: vec2<f32>, intensity: f32, time: f32) -> f32 {
    let scanline = sin(uv.y * 480.0 * PI + time * 0.1) * 0.5 + 0.5;
    return 1.0 - (scanline * intensity);
}

fn interlaceFlicker(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
    let field = floor(time * 30.0) % 2.0;
    let line = floor(uv.y * 240.0) % 2.0;
    let flicker = select(1.0, 0.85, line == field);
    return 1.0 - (1.0 - flicker) * intensity;
}

fn phosphorGlow(current: vec3<f32>, prev: vec3<f32>, decay: f32) -> vec3<f32> {
    return max(current, prev * decay);
}

// ═══ CHUNK: blue-noise offset (from spec-blue-noise-stipple.wgsl) ═══
fn blueNoiseOffset(pixelCoord: vec2<f32>, frame: f32) -> vec2<f32> {
    let phi2 = vec2<f32>(1.3247179572, 1.7548776662);
    return fract(pixelCoord * phi2 + frame * phi2);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let curvature = u.zoom_params.x * 0.3;
    let phosphorScale = mix(8.0, 40.0, u.zoom_params.y);
    let scanlineIntensity = u.zoom_params.z * 0.5;
    let flickerIntensity = u.zoom_params.w * 0.3;
    let audioPulse = u.zoom_config.w;

    // Barrel distortion
    let distortedUV = barrelDistort(uv, curvature);

    // Chromatic aberration at edges
    let centered = distortedUV - 0.5;
    let r = length(centered);
    let aberration = curvature * 0.5 * r * r;
    let rUV = distortedUV + normalize(centered + 0.0001) * aberration;
    let gUV = distortedUV;
    let bUV = distortedUV - normalize(centered + 0.0001) * aberration;

    var channelColors = vec3<f32>(0.0);

    // ═══ CHUNK: Blue-noise stippled phosphor triad (hybrid) ═══
    // Each channel gets its own blue-noise jittered dot grid
    let cellSize = 1.0 / phosphorScale;
    let cellId = floor(uv * phosphorScale);
    let cellLocal = fract(uv * phosphorScale) - 0.5;

    // R channel dots
    let jitterR = blueNoiseOffset(cellId + vec2<f32>(0.0, 0.0), time * 0.1);
    let dotCenterR = (jitterR - 0.5) * 0.8;
    let distR = length(cellLocal - dotCenterR);

    // G channel dots (offset)
    let jitterG = blueNoiseOffset(cellId + vec2<f32>(17.0, 31.0), time * 0.1);
    let dotCenterG = (jitterG - 0.5) * 0.8 + vec2<f32>(0.15, 0.0);
    let distG = length(cellLocal - dotCenterG);

    // B channel dots (offset)
    let jitterB = blueNoiseOffset(cellId + vec2<f32>(53.0, 11.0), time * 0.1);
    let dotCenterB = (jitterB - 0.5) * 0.8 - vec2<f32>(0.15, 0.0);
    let distB = length(cellLocal - dotCenterB);

    let dotSize = mix(0.35, 0.6, audioPulse * 0.5);
    let edgeWidth = 0.08;

    let maskR = 1.0 - smoothstep(dotSize - edgeWidth, dotSize + edgeWidth, distR);
    let maskG = 1.0 - smoothstep(dotSize - edgeWidth, dotSize + edgeWidth, distG);
    let maskB = 1.0 - smoothstep(dotSize - edgeWidth, dotSize + edgeWidth, distB);

    let sampleR = textureSampleLevel(readTexture, u_sampler, fract(rUV), 0.0).r;
    let sampleG = textureSampleLevel(readTexture, u_sampler, fract(gUV), 0.0).g;
    let sampleB = textureSampleLevel(readTexture, u_sampler, fract(bUV), 0.0).b;

    channelColors.r = sampleR * maskR * 1.4;
    channelColors.g = sampleG * maskG * 1.4;
    channelColors.b = sampleB * maskB * 1.4;

    var color = channelColors;

    // Scanlines
    color *= scanlines(uv, scanlineIntensity, time);

    // Interlaced flicker
    color *= interlaceFlicker(uv, time, flickerIntensity);

    // Temporal phosphor persistence
    let prevFrame = textureLoad(dataTextureC, coord, 0).rgb;
    color = phosphorGlow(color, prevFrame, 0.85 + audioPulse * 0.1);

    // Film grain
    color *= hash(uv + time * 0.1) * 0.1 + 0.95;

    // Vignette
    let edgeDist = length(uv - 0.5) * 1.4;
    let vignette = 1.0 - edgeDist * edgeDist * 0.5;
    color *= vignette;

    // HDR boost
    color = color * (1.0 + audioPulse * 0.5);
    color = color / (1.0 + color * 0.5);

    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(color, 1.0));
}
