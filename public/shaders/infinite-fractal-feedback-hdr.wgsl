// ═══════════════════════════════════════════════════════════════════
//  Infinite Fractal Feedback HDR
//  Category: advanced-hybrid
//  Features: fractal-feedback, HDR-bloom, accumulative-alpha, temporal
//  Complexity: Very High
//  Chunks From: infinite-fractal-feedback, alpha-hdr-bloom-chain
//  Created: 2026-04-18
//  By: Agent CB-26
// ═══════════════════════════════════════════════════════════════════
//  Perpetual fractal zoom with HDR bloom accumulation. Combines
//  infinite polar feedback looping with radial HDR bloom kernels
//  and ACES tone mapping. Temporal feedback creates ever-deepening
//  luminous fractal tunnels.
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

// ═══ CHUNK: toneMapACES (from alpha-hdr-bloom-chain) ═══
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: accumulativeAlpha (from infinite-fractal-feedback) ═══
fn accumulativeAlpha(
    newColor: vec3<f32>,
    newAlpha: f32,
    prevColor: vec3<f32>,
    prevAlpha: f32,
    accumulationRate: f32
) -> vec4<f32> {
    let accumulatedAlpha = prevAlpha * (1.0 - accumulationRate * 0.08) + newAlpha * accumulationRate;
    let totalAlpha = min(accumulatedAlpha, 1.0);
    let blendFactor = select(newAlpha * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    let color = mix(prevColor, newColor, blendFactor);
    return vec4<f32>(color, totalAlpha);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));

    // Parameters
    let zoomRate = u.zoom_params.x * 0.5 + 0.1;
    let spiralTightness = u.zoom_params.y * 4.0;
    let colorShift = u.zoom_params.z;
    let feedbackStrength = u.zoom_params.w;
    let accumulationRate = zoomRate;

    // Mouse
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Audio reactivity
    let audioOverall = u.zoom_config.x;
    let audioReactivity = 1.0 + audioOverall * 0.3;

    // Polar coordinates from center (mouse focal point)
    let centered = uv - 0.5;
    let focalOffset = centered - (mousePos - vec2<f32>(0.5)) * 0.5;
    var polar = vec2<f32>(length(focalOffset), atan2(focalOffset.y, focalOffset.x));

    // Perpetual zoom and rotation
    polar.x = fract(polar.x + time * zoomRate * audioReactivity * 0.05);
    polar.y = polar.y + time * audioReactivity * 0.2 + polar.x * spiralTightness;

    // Convert back to cartesian
    let newUV = vec2<f32>(polar.x * cos(polar.y), polar.x * sin(polar.y));
    let sampleUV = newUV * 0.5 + 0.5;

    // Multi-layered spiral sampling
    var finalColor = vec3<f32>(0.0);
    for (var i: u32 = 0u; i < 3u; i = i + 1u) {
        let fi = f32(i);
        let layerUV = sampleUV + vec2<f32>(sin(time + fi), cos(time + fi)) * 0.1;
        let color = textureSampleLevel(readTexture, u_sampler, fract(layerUV), 0.0).rgb;
        let hueShift = colorShift + fi * 0.33;
        finalColor += color * (1.0 + sin(time * 2.0 * audioReactivity + hueShift)) * 0.5;
    }

    // Kaleidoscopic symmetry
    let angle = atan2(newUV.y, newUV.x);
    let segments = 6.0 + floor(sin(time * 0.5 * audioReactivity) * 3.0);
    let kaleidoAngle = floor(angle * segments / (2.0 * 3.14159)) * (2.0 * 3.14159) / segments;
    let symUV = vec2<f32>(cos(kaleidoAngle), sin(kaleidoAngle)) * length(newUV);
    let symColor = textureSampleLevel(readTexture, u_sampler, symUV * 0.5 + 0.5, 0.0).rgb;
    finalColor = mix(finalColor, symColor, 0.6);

    // === HDR BLOOM KERNEL ===
    let bloomRadius = mix(0.01, 0.06, u.zoom_params.x);
    let bloomIntensity = u.zoom_params.y * 2.0;
    let bloomSamples = 16;

    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;

    for (var i = 0; i < bloomSamples; i = i + 1) {
        let angle_b = f32(i) * 6.283185307 / f32(bloomSamples);
        let radius = bloomRadius * (1.0 + f32(i % 4) * 0.5);
        let offset = vec2<f32>(cos(angle_b), sin(angle_b)) * radius;
        let sampleUV_b = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
        let neighbor = textureSampleLevel(readTexture, u_sampler, sampleUV_b, 0.0).rgb;
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

    let hdrColor = finalColor + bloom;

    // Mouse bloom boost
    let mouseDist = length(uv - mousePos);
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

    // Tone map for display
    let toneMapExp = mix(0.5, 2.0, colorShift);
    let ldrColor = toneMapACES(hdrColor * toneMapExp);

    // === ACCUMULATIVE ALPHA FEEDBACK ===
    let prev = textureSampleLevel(dataTextureC, u_sampler, fract(sampleUV), 0.0);
    let luma = dot(ldrColor, vec3<f32>(0.299, 0.587, 0.114));
    let newAlpha = luma;

    let accumulated = accumulativeAlpha(ldrColor, newAlpha, prev.rgb, prev.a, accumulationRate);
    let finalResult = mix(accumulated, vec4<f32>(ldrColor, newAlpha), feedbackStrength);

    // Store HDR state
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, newAlpha));

    // Write display
    textureStore(writeTexture, coord, finalResult);

    // Depth feedback
    let depth = 1.0 - clamp(length(newUV), 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
