// ═══════════════════════════════════════════════════════════════════
//  Sim: Fluid Feedback Field (Pass 3 - Composite)
//  Category: simulation
//  Features: simulation, multi-pass-3, composite, glow, color-grading
//  Complexity: Very High
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Pass 3: Read density from Pass 2
//  Add glow, color grading, volumetric rendering approximation
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

// ═══ GLOW CALCULATION ═══
fn calculateGlow(uv: vec2<f32>, intensity: f32) -> vec3<f32> {
    var glow = vec3<f32>(0.0);
    let samples = 16;
    
    for (var i = 0; i < samples; i++) {
        let angle = f32(i) * 6.28318 / f32(samples);
        let radius = 0.02 * (1.0 + f32(i % 4) * 0.3);
        let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
        let sampleColor = textureSampleLevel(dataTextureC, u_sampler, uv + offset, 0.0).rgb;
        glow += sampleColor;
    }
    
    return glow / f32(samples) * intensity;
}

// ═══ MAIN: COMPOSITE ═══
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let glowAmount = mix(0.5, 2.0, u.zoom_params.w);  // w: Glow intensity
    
    // Read density from dataTextureB (written by Pass 2)
    let density = textureLoad(dataTextureC, gid.xy, 0).rgb;
    let densityMag = length(density);
    
    // Sample original image
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    // Calculate glow
    let glow = calculateGlow(uv, glowAmount);
    
    // Volumetric approximation (screen-space scattering)
    var scattered = vec3<f32>(0.0);
    let scatterSamples = 8;
    let scatterDir = normalize(vec2<f32>(0.5) - uv);
    for (var i = 0; i < scatterSamples; i++) {
        let t = f32(i) / f32(scatterSamples);
        let sampleUV = uv + scatterDir * t * 0.1;
        let sampleDensity = textureSampleLevel(dataTextureC, u_sampler, sampleUV, 0.0).rgb;
        scattered += sampleDensity * (1.0 - t);
    }
    scattered /= f32(scatterSamples);
    
    // Combine everything
    var color = baseColor * (1.0 - densityMag * 0.5);
    color += density * 2.0;
    color += glow * densityMag;
    color += scattered * 0.5;
    
    // Color grading - boost saturation
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = mix(vec3<f32>(luma), color, 1.3);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.7, 1.0, densityMag);
    
    textureStore(writeTexture, gid.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth * (1.0 - densityMag * 0.2), 0.0, 0.0, 0.0));
}
