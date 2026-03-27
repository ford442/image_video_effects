// ═══════════════════════════════════════════════════════════════════
//  Hybrid Noise Kaleidoscope
//  Category: generative
//  Features: hybrid, fbm-noise, kaleidoscope, chromatic-aberration, hue-shift
//  Chunks From: gen_grid.wgsl (fbm2, domainWarp), kaleidoscope.wgsl (kaleidoscope), stellar-plasma.wgsl (hueShift)
//  Created: 2026-03-22
//  By: Agent 2A - Shader Surgeon
// ═══════════════════════════════════════════════════════════════════
//  Concept: Domain-warped FBM noise fed through kaleidoscope symmetry
//           with dynamic hue shifting and RGB channel splits
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

// ═══ CHUNK 1: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK 2: valueNoise (from gen_grid.wgsl) ═══
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ═══ CHUNK 3: fbm2 (from gen_grid.wgsl) ═══
fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// ═══ CHUNK 4: kaleidoscope (from kaleidoscope.wgsl) ═══
fn kaleidoscope(uv: vec2<f32>, segments: f32) -> vec2<f32> {
    let angle = atan2(uv.y, uv.x);
    let radius = length(uv);
    let segmentAngle = 6.28318 / segments;
    let mirroredAngle = abs(fract(angle / segmentAngle + 0.5) - 0.5) * segmentAngle;
    return vec2<f32>(cos(mirroredAngle), sin(mirroredAngle)) * radius;
}

// ═══ CHUNK 5: hueShift (from stellar-plasma.wgsl) ═══
fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(hue);
    return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

// ═══ HYBRID LOGIC ═══
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameter extraction (randomization-safe)
    let noiseScale = mix(1.0, 8.0, u.zoom_params.x);       // x: Noise scale
    let segments = mix(3.0, 16.0, u.zoom_params.y);        // y: Kaleidoscope segments  
    let chromaticStrength = u.zoom_params.z * 0.05;        // z: RGB split amount
    let hueSpeed = mix(0.1, 1.0, u.zoom_params.w);         // w: Hue rotation speed
    
    // Center UVs
    let centered = (uv - 0.5) * 2.0;
    let aspect = resolution.x / resolution.y;
    var p = centered;
    p.x *= aspect;
    
    // Apply FBM noise distortion
    let noiseVal = fbm2(p * noiseScale + time * 0.2, 5);
    let noiseDisplacement = vec2<f32>(
        fbm2(p * noiseScale + vec2<f32>(5.2, 1.3), 4),
        fbm2(p * noiseScale + vec2<f32>(1.7, 9.2), 4)
    ) * 0.3;
    
    // Apply kaleidoscope to warped coordinates
    let warpedP = p + noiseDisplacement;
    let kaled = kaleidoscope(warpedP, segments);
    
    // Convert back to UV space
    let finalUV = kaled / vec2<f32>(aspect, 1.0) * 0.5 + 0.5;
    
    // Chromatic aberration sampling
    let rUV = finalUV + vec2<f32>(chromaticStrength, 0.0);
    let gUV = finalUV;
    let bUV = finalUV - vec2<f32>(chromaticStrength, 0.0);
    
    // Sample or generate color
    var color: vec3<f32>;
    let pattern = fbm2(warpedP * 2.0, 4);
    color = vec3<f32>(pattern, pattern * 0.8, pattern * 0.6);
    
    // Add chromatic variation based on kaleidoscope angle
    let angle = atan2(kaled.y, kaled.x);
    color.r += sin(angle * segments) * chromaticStrength * 5.0;
    color.b += cos(angle * segments) * chromaticStrength * 5.0;
    
    // Apply hue shift
    color = hueShift(color, time * hueSpeed + noiseVal * 0.5);
    
    // Vignette
    let vignette = 1.0 - length(centered) * 0.3;
    color *= vignette;
    
    // Alpha based on pattern intensity
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(0.6, 1.0, luma);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(noiseVal, 0.0, 0.0, 0.0));
}
