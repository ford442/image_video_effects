// ═══════════════════════════════════════════════════════════════════
//  particle-dreams-hdr
//  Category: advanced-hybrid
//  Features: multi-pass-accumulation, hdr-bloom, mouse-driven, depth-aware
//  Complexity: Very High
//  Chunks From: particle_dreams_alpha (layer accumulation, flow noise), alpha-hdr-bloom-chain (HDR bloom, ACES tone map)
//  Created: 2026-04-18
//  By: Agent CB-6 — Alpha & Post-Process Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Particle Dreams with HDR Bloom Chain
//  Accumulates 5 depth-layered samples with flow noise and vortex
//  distortion, then applies HDR bloom based on per-layer exposure.
//  Final output is ACES tone mapped with bloom composited.
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

fn ping_pong(a: f32) -> f32 {
    return 1.0 - abs(fract(a * 0.5) * 2.0 - 1.0);
}

fn ping_pong_v2(v: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(ping_pong(v.x), ping_pong(v.y));
}

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 = p3 + dot(p3, p3 + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u2 = f * f * (vec2<f32>(3.0) - 2.0 * f);
    return mix(
        mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
        u2.y
    );
}

// ═══ CHUNK: ACES tone map (from alpha-hdr-bloom-chain.wgsl) ═══
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(gid.x) >= resolution.x || f32(gid.y) >= resolution.y) { return; }

    let uv = vec2<f32>(gid.xy) / resolution;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;
    let zoom_time = u.zoom_config.x;
    let zoom_center = u.zoom_config.yz;
    let mousePos = vec2<f32>(u.zoom_config.y / resolution.x, u.zoom_config.z / resolution.y);

    let bloomRadius = mix(0.01, 0.08, u.zoom_params.x);
    let bloomIntensity = u.zoom_params.y * 2.0;
    let toneMapExp = mix(0.5, 2.0, u.zoom_params.z);
    let fogDensity = u.zoom_params.w;

    // ═══ CHUNK: Layer accumulation (from particle_dreams_alpha.wgsl) ═══
    var accumulatedColor = vec3<f32>(0.0);
    var accumulatedDepth = 0.0;
    var totalWeight = 0.0;

    for (var i: i32 = 0; i < 5; i = i + 1) {
        let layerDepth = f32(i) / f32(5 - 1);
        let layerSpeed = mix(u.zoom_params.x, u.zoom_params.y, layerDepth);
        let layerZoom = 1.0 + fract(zoom_time * layerSpeed) * 4.0;
        let toCenter = uv - zoom_center;
        let angle = atan2(toCenter.y, toCenter.x);
        let dist = length(toCenter);
        let vortexStrength = 0.3 / (dist + 0.1);
        let spinAngle = vortexStrength * layerDepth * (1.0 - layerDepth);
        let rotatedUV = vec2<f32>(
            cos(spinAngle) * toCenter.x - sin(spinAngle) * toCenter.y,
            sin(spinAngle) * toCenter.x + cos(spinAngle) * toCenter.y
        ) + zoom_center;
        let flowUV = rotatedUV + vec2<f32>(noise(rotatedUV * 6.0 + vec2<f32>(time * 0.15, 0.0)), noise(rotatedUV * 6.0 + vec2<f32>(0.0, time * 0.15))) * 0.015 * layerDepth;
        let transformed = (flowUV - zoom_center) / vec2<f32>(layerZoom) + zoom_center;
        let sampleColor = textureSampleLevel(readTexture, u_sampler, ping_pong_v2(transformed), 0.0).xyz;
        let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, ping_pong_v2(transformed), 0.0).x;
        let density = exp(-layerDepth * 1.5);
        let weight = density * (1.0 + sampleDepth * 0.5);
        accumulatedColor += sampleColor * weight;
        accumulatedDepth += sampleDepth * weight;
        totalWeight += weight;
    }

    let baseColor = accumulatedColor / vec3<f32>(max(totalWeight, 0.0001));
    let baseDepth = accumulatedDepth / max(totalWeight, 0.0001);

    // ═══ CHUNK: HDR bloom (from alpha-hdr-bloom-chain.wgsl) ═══
    let maxChannel = max(baseColor.r, max(baseColor.g, baseColor.b));
    let exposure = max(0.0, maxChannel - 1.0);

    var bloom = vec3<f32>(0.0);
    var bloomWeight = 0.0;
    let bloomSamples = 16;
    for (var i: i32 = 0; i < bloomSamples; i = i + 1) {
        let angle = f32(i) * 6.283185307 / f32(bloomSamples);
        let radius = bloomRadius * (1.0 + f32(i % 4) * 0.5);
        let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
        let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
        let neighbor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let neighborMax = max(neighbor.r, max(neighbor.g, neighbor.b));
        let neighborExposure = max(0.0, neighborMax - 1.0);
        let weight = exp(-f32(i % 4) * 0.5);
        bloom += neighbor * neighborExposure * weight;
        bloomWeight += neighborExposure * weight;
    }
    if (bloomWeight > 0.001) {
        bloom /= bloomWeight;
    }
    bloom *= bloomIntensity;

    // Depth-based chromatic aberration (from particle_dreams_alpha)
    let chroma = 0.02;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(chroma * baseDepth, 0.0), 0.0).x;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).y;
    let b = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(chroma * baseDepth, 0.0), 0.0).z;
    let chromaticColor = vec3<f32>(r, g, b);

    let hdrColor = chromaticColor + bloom;

    // Mouse bloom boost
    let mouseDist = length(uv - mousePos);
    let mouseDown = u.zoom_config.w;
    let mouseGlow = smoothstep(0.2, 0.0, mouseDist) * mouseDown * 2.0;
    hdrColor += vec3<f32>(mouseGlow * 0.5, mouseGlow * 0.3, mouseGlow * 0.1);

    // Ripple flash
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 0.5 && rDist < 0.1) {
            let flash = smoothstep(0.1, 0.0, rDist) * max(0.0, 1.0 - age * 2.0);
            hdrColor += vec3<f32>(flash * 2.0, flash * 1.5, flash);
        }
    }

    // Edge glow from depth gradient
    let ps = vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y);
    let depthX = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(ps.x, 0.0), 0.0).x;
    let depthY = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, ps.y), 0.0).x;
    let depthGrad = length(vec2<f32>(depthX - baseDepth, depthY - baseDepth));
    let edgeGlow = exp(-depthGrad * 30.0) * baseDepth * 2.0;
    let finalColor = hdrColor + vec3<f32>(edgeGlow, edgeGlow * 0.8, edgeGlow * 0.6);

    // Fog
    let fog = exp(-baseDepth * fogDensity * 3.0);
    let fogColor = vec3<f32>(0.02, 0.05, 0.1);
    let outColor = mix(finalColor, fogColor, 1.0 - fog);

    // Tone map
    let ldrColor = toneMapACES(outColor * toneMapExp);

    // Store HDR state
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, exposure));
    textureStore(writeTexture, coord, vec4<f32>(ldrColor, exposure + 0.1));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
