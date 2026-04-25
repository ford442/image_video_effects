// ═══════════════════════════════════════════════════════════════════
//  alucinate-hdr
//  Category: advanced-hybrid
//  Features: psychedelic-warping, hdr-bloom, tone-mapping, mouse-driven
//  Complexity: High
//  Chunks From: alucinate.wgsl, alpha-hdr-bloom-chain.wgsl
//  Created: 2026-04-18
//  By: Agent CB-16 — Generative & Cosmic Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Psychedelic interactive warping meets HDR bloom chain. Warped UVs
//  generate chromatic displacement; bloom kernel accumulates on the
//  warped result. ACES tone mapping brings HDR values back to LDR.
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

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.5;

    let mouse_uv = u.zoom_config.yz;
    let mouse_active = u.zoom_config.w > 0.0;
    let dist_to_mouse = distance(uv, mouse_uv);
    let mouse_effect = smoothstep(0.3, 0.0, dist_to_mouse) * f32(mouse_active);

    // ═══ Alucinate Warp ═══
    let warp_freq = mix(4.0, 10.0, mouse_effect);
    let warp_amp = mix(0.02, 0.1, mouse_effect);
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let radius = distance(uv, vec2<f32>(0.5));
    let warp_offset_x = sin(uv.y * warp_freq - time) * cos(radius * 10.0 + time) * warp_amp;
    let warp_offset_y = cos(uv.x * warp_freq + time) * sin(radius * 10.0 - time) * warp_amp;
    let warped_uv = uv + vec2<f32>(warp_offset_x, warp_offset_y);

    let shift_amount = mix(0.005, 0.02, mouse_effect) * sin(time * 2.0);
    let r = textureSampleLevel(readTexture, u_sampler, warped_uv + vec2<f32>(shift_amount, shift_amount), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, warped_uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, warped_uv - vec2<f32>(shift_amount, shift_amount), 0.0).b;
    var warpedColor = vec3<f32>(r, g, b);

    // ═══ HDR Bloom Chain ═══
    let bloomRadius = mix(0.01, 0.08, u.zoom_params.x);
    let bloomIntensity = u.zoom_params.y * 2.0;
    let bloomSamples = 16;

    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;

    for (var i = 0; i < bloomSamples; i = i + 1) {
        let a = f32(i) * 6.283185307 / f32(bloomSamples);
        let rad = bloomRadius * (1.0 + f32(i % 4) * 0.5);
        let offset = vec2<f32>(cos(a), sin(a)) * rad;
        let sampleUV = clamp(warped_uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
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

    // Mouse bloom boost
    let mouseGlow = smoothstep(0.2, 0.0, dist_to_mouse) * u.zoom_config.w * 2.0;
    bloom += vec3<f32>(mouseGlow * 0.5, mouseGlow * 0.3, mouseGlow * 0.1);

    // Ripple flash
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time * 2.0 - ripple.z;
        if (age < 0.5 && rDist < 0.1) {
            let flash = smoothstep(0.1, 0.0, rDist) * max(0.0, 1.0 - age * 2.0);
            bloom += vec3<f32>(flash * 2.0, flash * 1.5, flash);
        }
    }

    let hdrColor = warpedColor + bloom;
    let toneMapExp = mix(0.5, 2.0, u.zoom_params.z);
    let ldrColor = toneMapACES(hdrColor * toneMapExp);

    let luma = dot(ldrColor, vec3<f32>(0.299, 0.587, 0.114));
    let warpAlpha = mix(0.8, 1.0, mouse_effect + warp_amp * 10.0);
    let alpha = mix(warpAlpha * 0.85, warpAlpha, luma);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let finalAlpha = mix(alpha * 0.8, alpha, depth);

    textureStore(writeTexture, coord, vec4<f32>(ldrColor, finalAlpha));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, max(0.0, max(hdrColor.r, max(hdrColor.g, hdrColor.b)) - 1.0)));

    let depthOut = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
