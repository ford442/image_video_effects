// ═══════════════════════════════════════════════════════════════
//  Neon Fluid Warp - Liquid Displacement with Alpha Emission
//  Category: lighting-effects
//  Physics: Liquid-like displacement with emissive ring glow
//  Alpha: Core ring = 0.3, Glow = 0.0 (additive)
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

// Helper to get luminance
fn get_luma(color: vec3<f32>) -> f32 {
    return dot(color, vec3(0.299, 0.587, 0.114));
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
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters
    // x: warpStrength, y: radius, z: glowIntensity, w: occlusionBalance
    let warpStrength = u.zoom_params.x * 0.2;
    let radius = u.zoom_params.y * 0.5;
    let glowIntensity = u.zoom_params.z;
    let liquidity = u.zoom_params.w * 0.5; // Reuse w for liquidity
    let occlusionBalance = 0.5;

    // Mouse
    var mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Vector to mouse
    var distVec = (uv - mousePos);
    distVec.x *= aspect;
    let dist = length(distVec);

    // Warp calculation with "liquidity" sine ripples
    let angle = atan2(distVec.y, distVec.x);
    let ripple = sin(dist * 20.0 - time * 5.0) * liquidity * 0.05;

    // Repulsion force
    let force = smoothstep(radius, 0.0, dist);

    // Calculate displacement
    let displaceDir = normalize(distVec);
    let offset = -displaceDir * force * warpStrength * (1.0 + ripple);

    let sampleUV = uv + offset;

    // Sample the texture
    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgba;

    // Edge/Stress detection for Neon Glow
    let edge = smoothstep(0.0, 0.1, abs(dist - radius * 0.8));
    let glowFactor = force * (1.0 - force) * 4.0;

    let neonColor = vec3<f32>(
        0.5 + 0.5 * sin(time + uv.x * 10.0),
        0.5 + 0.5 * sin(time + uv.y * 10.0 + 2.0),
        0.5 + 0.5 * sin(time + 4.0)
    );

    // Emission calculation
    let luma = get_luma(color.rgb);
    let emission = neonColor * glowFactor * glowIntensity * luma * 3.0;

    // Calculate alpha based on emission intensity
    let glowStrength = length(emission);
    let finalAlpha = calculateEmissiveAlpha(glowStrength, occlusionBalance);

    // Output with emission alpha
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, finalAlpha));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
