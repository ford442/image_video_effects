// ═══════════════════════════════════════════════════════════════
//  Neon Edges - Sobel Edge Detection with Alpha Emission
//  Category: lighting-effects
//  Physics: Emissive edge glow with alpha occlusion
//  Alpha: Core edge = 0.3, Glow = 0.0 (additive)
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn neonPalette(v: f32, time: f32) -> vec3<f32> {
    // Map value (0..1) to neon cyan-magenta gradient
    let a = clamp(v, 0.0, 1.0);
    let c = mix(vec3<f32>(0.0, 1.0, 0.9), vec3<f32>(1.0, 0.0, 0.8), a);
    // Slight pulsation
    let pulse = 0.5 + 0.5 * sin(time * 2.0 + a * 6.2831);
    return mix(c * 0.6, c, pulse * 0.8);
}

// Alpha calculation for emissive materials
fn calculateEmissiveAlpha(glowIntensity: f32, occlusionBalance: f32) -> f32 {
    let coreAlpha = 0.3 * glowIntensity;
    let glowAlpha = 0.0;
    return mix(glowAlpha, coreAlpha, clamp(glowIntensity, 0.0, 1.0) * occlusionBalance);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let texel = 1.0 / vec2<f32>(resolution);
    let time = u.config.x;

    // Simple Sobel kernel
    let c00 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0, -1.0), 0.0).rgb;
    let c10 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(0.0, -1.0), 0.0).rgb;
    let c20 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(1.0, -1.0), 0.0).rgb;
    let c01 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0, 0.0), 0.0).rgb;
    let c11 = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let c21 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(1.0, 0.0), 0.0).rgb;
    let c02 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(-1.0, 1.0), 0.0).rgb;
    let c12 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(0.0, 1.0), 0.0).rgb;
    let c22 = textureSampleLevel(readTexture, u_sampler, uv + texel * vec2<f32>(1.0, 1.0), 0.0).rgb;

    let gx = -luminance(c00) - 2.0 * luminance(c01) - luminance(c02) + luminance(c20) + 2.0 * luminance(c21) + luminance(c22);
    let gy = -luminance(c00) - 2.0 * luminance(c10) - luminance(c20) + luminance(c02) + 2.0 * luminance(c12) + luminance(c22);

    let mag = length(vec2<f32>(gx, gy));

    // Edge threshold and neon intensity
    // x: threshold, y: intensity, z: unused, w: occlusion balance
    let threshold = mix(0.05, 0.6, u.zoom_params.x);
    let intensity = mix(0.4, 2.0, u.zoom_params.y);
    let occlusionBalance = u.zoom_params.w;

    let edge = smoothstep(threshold * 0.5, threshold, mag) * intensity;
    
    // Neon emission - can exceed 1.0 for HDR
    let neonColor = neonPalette(edge, time);
    let emission = neonColor * edge * 2.0; // Boost for HDR

    // Calculate alpha based on emission intensity
    let glowIntensity = length(emission);
    let finalAlpha = calculateEmissiveAlpha(glowIntensity, occlusionBalance);

    // Output RGBA: RGB = emission (HDR), A = physical occlusion
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, finalAlpha));

    // Pass through original depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
