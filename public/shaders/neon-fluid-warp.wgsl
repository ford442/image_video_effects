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

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
    let lenSq = max(dot(v, v), 1e-6);
    return v * inverseSqrt(lenSq);
}

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.50, 0.49, 0.53) +
           vec3<f32>(0.48, 0.42, 0.45) *
           cos(6.28318 * (vec3<f32>(1.0, 0.80, 0.55) * t + vec3<f32>(0.28, 0.18, 0.08)));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = max(u.zoom_config.x, plasmaBuffer[0].w);
    let audioBass = max(plasmaBuffer[0].x, audioOverall * 1.5);
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioReactivity = 1.0 + audioOverall * 0.3;

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
    let ripple = sin(dist * 20.0 - time * 5.0 * audioReactivity) * liquidity * 0.05;

    // Repulsion force
    let force = smoothstep(radius, 0.0, dist);

    // Calculate displacement
    let displaceDir = safeNormalize(distVec);
    let tangent = vec2<f32>(-displaceDir.y, displaceDir.x);
    let offset = (-displaceDir * force * warpStrength * (1.0 + ripple)) +
                 tangent * sin(dist * 32.0 + time * 2.2) * force * liquidity * 0.018;

    let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));

    // Sample the texture
    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgba;

    // Edge/Stress detection for Neon Glow
    let edge = 1.0 - smoothstep(0.0, 0.13 + treble * 0.03, abs(dist - radius * 0.8));
    let glowFactor = force * (1.0 - force) * 4.0;
    let caustic = pow(max(0.0, sin(dist * 42.0 - time * (5.0 + audioBass * 1.5)) * 0.5 + 0.5), 5.0) * force;

    let neonColor = palette(time * 0.09 + dist * 1.3 + mids * 0.25);

    // Emission calculation
    let luma = get_luma(color.rgb);
    var hdr = color.rgb * (0.58 + force * 0.28);
    let emission = neonColor * glowFactor * glowIntensity * luma * (3.2 + audioBass);
    hdr = hdr + emission;
    hdr = hdr + vec3<f32>(0.42, 0.75, 1.0) * edge * glowIntensity * (0.75 + treble);
    hdr = hdr + vec3<f32>(1.0, 0.82, 0.46) * caustic * (0.45 + audioBass * 0.35);
    hdr = hdr * mix(1.0, 0.66, smoothstep(0.46, 1.0, length(uv - vec2<f32>(0.5)) * 1.414));

    // Calculate alpha based on emission intensity
    let glowStrength = length(hdr);
    let bloomAlpha = pow(max(0.0, get_luma(hdr) - 0.55), 2.0) * 2.7;
    let finalAlpha = clamp(calculateEmissiveAlpha(glowStrength, occlusionBalance) + edge * 0.18 + bloomAlpha, 0.0, 1.0);
    let dither = (ign(vec2<f32>(global_id.xy) + time * 37.0) - 0.5) / 255.0;
    let finalRGB = clamp(aces(hdr * 1.16) + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));

    // Output with emission alpha
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB * finalAlpha, finalAlpha));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
