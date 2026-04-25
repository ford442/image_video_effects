// ═══════════════════════════════════════════════════════════════════
//  Double Exposure HDR
//  Category: advanced-hybrid
//  Features: double-exposure, HDR-bloom, tone-mapping, mouse-driven
//  Complexity: High
//  Chunks From: double-exposure.wgsl, alpha-hdr-bloom-chain.wgsl
//  Created: 2026-04-18
//  By: Agent CB-22 — Artistic & Texture Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Blends the image with a zoomed and rotated version of itself,
//  then applies HDR bloom to the composite. The double exposure
//  creates ghostly overlays while the bloom chain adds luminous
//  halos around bright overlap regions with ACES tone mapping.
//  Mouse position sets the pivot point for the zoom/rotation.
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

fn rotate2d(uv: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    var uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(gid.xy);
    let time = u.config.x;

    // Double exposure params
    let zoomParam = u.zoom_params.x;
    let zoom = 0.5 + zoomParam * 2.5;
    let rotParam = u.zoom_params.y;
    let angle = (rotParam - 0.5) * 1.57;
    let opacity = u.zoom_params.z;
    let saturation = u.zoom_params.w;

    // Mouse pivot
    var mouse = u.zoom_config.yz;
    let aspect = res.x / res.y;

    // Sample 1: Base Image
    let c1 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Sample 2: Transformed Image
    var p = uv - mouse;
    p.x *= aspect;
    p = rotate2d(p, angle);
    p = p / zoom;
    p.x /= aspect;
    let uv2 = p + mouse;
    let c2 = textureSampleLevel(readTexture, u_sampler, uv2, 0.0);

    // Screen Blend: 1 - (1-a)*(1-b)
    var blended = 1.0 - (1.0 - c1.rgb) * (1.0 - c2.rgb * opacity);

    // Saturation adjustment
    let gray = dot(blended, vec3<f32>(0.299, 0.587, 0.114));
    blended = mix(vec3<f32>(gray), blended, 0.5 + saturation * 0.5);

    // ═══ HDR BLOOM CHAIN ═══
    let bloomRadius = mix(0.01, 0.06, 0.4);
    let bloomIntensity = 1.5;
    let bloomSamples = 12;

    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;

    for (var i = 0; i < bloomSamples; i = i + 1) {
        let a = f32(i) * 6.283185307 / f32(bloomSamples);
        let radius = bloomRadius * (1.0 + f32(i % 4) * 0.5);
        let offset = vec2<f32>(cos(a), sin(a)) * radius;
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

    // Composite HDR
    var hdrColor = blended + bloom;

    // Mouse bloom boost
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mouse);
    let mouseGlow = smoothstep(0.2, 0.0, mouseDist) * mouseDown * 2.0;
    hdrColor += vec3<f32>(mouseGlow * 0.5, mouseGlow * 0.3, mouseGlow * 0.1);

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
    let toneMapExp = mix(0.5, 2.0, 0.5);
    let ldrColor = toneMapACES(hdrColor * toneMapExp);
    let exposure = max(0.0, max(hdrColor.r, max(hdrColor.g, hdrColor.b)) - 1.0);

    // Store HDR state
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, exposure));

    // Write display
    textureStore(writeTexture, coord, vec4<f32>(ldrColor, exposure + 0.1));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
