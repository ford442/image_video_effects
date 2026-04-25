// ═══════════════════════════════════════════════════════════════════
//  Retro Phosphor HDR
//  Category: advanced-hybrid
//  Features: crt-phosphor, hdr-bloom, temporal-persistence, audio-reactive
//  Complexity: High
//  Chunks From: retro_phosphor_dream.wgsl, alpha-hdr-bloom-chain.wgsl
//  Created: 2026-04-18
//  By: Agent CB-13 — Retro & Glitch Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Authentic CRT phosphor simulation with full HDR bloom chain.
//  Phosphor persistence, barrel distortion, and scanlines are enhanced
//  by HDR bloom with ACES tone mapping for dramatic glowing phosphors.
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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn barrelDistort(uv: vec2<f32>, strength: f32) -> vec2<f32> {
    let centered = uv - 0.5;
    let r2 = dot(centered, centered);
    let distortion = 1.0 + strength * r2;
    return centered * distortion + 0.5;
}

fn phosphorTriad(uv: vec2<f32>, triadSize: f32) -> vec3<f32> {
    let x = uv.x / triadSize;
    let triadX = fract(x);
    if (triadX < 0.33) { return vec3<f32>(1.0, 0.0, 0.0); }
    else if (triadX < 0.66) { return vec3<f32>(0.0, 1.0, 0.0); }
    else { return vec3<f32>(0.0, 0.0, 1.0); }
}

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

fn chromaticAberration(uv: vec2<f32>, strength: f32) -> vec3<f32> {
    let centered = uv - 0.5;
    let r = length(centered);
    let aberration = strength * r * r;
    let rUV = uv + normalize(centered) * aberration;
    let gUV = uv;
    let bUV = uv - normalize(centered) * aberration;
    return vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
        textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g,
        textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
    );
}

// ACES tone mapping
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let coord = vec2<i32>(global_id.xy);

    let curvature = u.zoom_params.x * 0.3;
    let phosphorSize = 0.001 + u.zoom_params.y * 0.003;
    let scanlineIntensity = u.zoom_params.z * 0.5;
    let bloomIntensity = u.zoom_params.w * 2.0;

    let audioPulse = u.zoom_config.w;

    // Barrel distortion
    let distortedUV = barrelDistort(uv, curvature);

    // Chromatic aberration
    var color = chromaticAberration(distortedUV, curvature * 0.5);

    // Phosphor triad
    let triad = phosphorTriad(uv, phosphorSize);
    color *= 0.7 + triad * 0.6;

    // Scanlines
    color *= scanlines(uv, scanlineIntensity, time);

    // Interlaced flicker
    color *= interlaceFlicker(uv, time, 0.2);

    // Temporal phosphor persistence
    let prevFrame = textureLoad(dataTextureC, coord, 0).rgb;
    color = max(color, prevFrame * (0.85 + audioPulse * 0.1));

    // Film grain
    color *= hash(uv + time * 0.1) * 0.1 + 0.95;

    // Vignette
    let edgeDist = length(uv - 0.5) * 1.4;
    color *= 1.0 - edgeDist * edgeDist * 0.5;

    // HDR boost
    color = color * (1.0 + audioPulse * 0.5);

    // ═══ HDR BLOOM CHAIN ═══
    let bloomRadius = 0.05;
    let bloomSamples = 16;
    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;

    for (var i = 0; i < bloomSamples; i = i + 1) {
        let angle = f32(i) * 6.283185307 / f32(bloomSamples);
        let radius = bloomRadius * (1.0 + f32(i % 4) * 0.5);
        let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
        let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
        let neighbor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let neighborMax = max(neighbor.r, max(neighbor.g, neighbor.b));
        let neighborExposure = max(0.0, neighborMax - 1.0);
        let weight = exp(-f32(i % 4) * 0.5);
        bloom += neighbor * neighborExposure * weight;
        totalWeight += neighborExposure * weight;
    }

    if (totalWeight > 0.001) {
        bloom /= totalWeight;
    }
    bloom *= bloomIntensity;

    let hdrColor = color + bloom;

    // Ripple flash
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 0.5 && rDist < 0.1) {
            let flash = smoothstep(0.1, 0.0, rDist) * max(0.0, 1.0 - age * 2.0);
            hdrColor += vec3<f32>(flash * 2.0, flash * 1.5, flash);
        }
    }

    // Tone map
    let ldrColor = toneMapACES(hdrColor);

    textureStore(writeTexture, coord, vec4<f32>(ldrColor, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, max(hdrColor.r, max(hdrColor.g, hdrColor.b)) - 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
