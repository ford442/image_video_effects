// ═══════════════════════════════════════════════════════════════════
//  chromatic-crawler-structure
//  Category: advanced-hybrid
//  Features: chromatic-crawler, structure-tensor-flow, temporal
//  Complexity: Very High
//  Chunks From: chromatic-crawler, conv-structure-tensor-flow
//  Created: 2026-04-18
//  By: Agent CB-12 — Chroma & Spectral Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Color-swapping crawling infection guided by image structure tensor
//  eigenvectors. Tendrils grow along dominant image orientations instead
//  of random directions, creating organic texture-following chroma vines.
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

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.9))
    );
    p3 = fract(sin(p3) * 43758.5453);
    return p3;
}

fn sampleLuma(uv: vec2<f32>, pixelSize: vec2<f32>, dx: i32, dy: i32) -> f32 {
    let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
    return dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
}

fn smoothTensor(uv: vec2<f32>, pixelSize: vec2<f32>) -> vec4<f32> {
    var sum = vec4<f32>(0.0);
    for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let gx =
                -1.0 * sampleLuma(uv + offset, pixelSize, -1, -1) +
                -2.0 * sampleLuma(uv + offset, pixelSize, -1,  0) +
                -1.0 * sampleLuma(uv + offset, pixelSize, -1,  1) +
                 1.0 * sampleLuma(uv + offset, pixelSize,  1, -1) +
                 2.0 * sampleLuma(uv + offset, pixelSize,  1,  0) +
                 1.0 * sampleLuma(uv + offset, pixelSize,  1,  1);
            let gy =
                -1.0 * sampleLuma(uv + offset, pixelSize, -1, -1) +
                -2.0 * sampleLuma(uv + offset, pixelSize,  0, -1) +
                -1.0 * sampleLuma(uv + offset, pixelSize,  1, -1) +
                 1.0 * sampleLuma(uv + offset, pixelSize, -1,  1) +
                 2.0 * sampleLuma(uv + offset, pixelSize,  0,  1) +
                 1.0 * sampleLuma(uv + offset, pixelSize,  1,  1);
            let Ix2 = gx * gx;
            let Iy2 = gy * gy;
            let Ixy = gx * gy;
            sum += vec4<f32>(Ix2, Iy2, Ixy, 0.0);
        }
    }
    return sum / 9.0;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;

    let crawlSpeed = u.zoom_params.x * 2.0 + 0.5;
    let swapIntensity = u.zoom_params.y;
    let feedbackMix = u.zoom_params.z * 0.4 + 0.2;
    let flashRate = u.zoom_params.w * 20.0 + 5.0;

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Structure tensor for flow-guided crawling
    let tensor = smoothTensor(uv, pixelSize);
    let Jxx = tensor.x;
    let Jyy = tensor.y;
    let Jxy = tensor.z;
    let trace = Jxx + Jyy;
    let det = Jxx * Jyy - Jxy * Jxy;
    let diff = sqrt(max((Jxx - Jyy) * (Jxx - Jyy) + 4.0 * Jxy * Jxy, 0.0));
    let lambda1 = (trace + diff) * 0.5;
    let lambda2 = (trace - diff) * 0.5;
    var eigenvec = vec2<f32>(1.0, 0.0);
    if (abs(Jxy) > 0.0001 || abs(Jxx - lambda1) > 0.0001) {
        eigenvec = normalize(vec2<f32>(lambda1 - Jyy, Jxy));
    }
    let coherency = select(0.0, (lambda1 - lambda2) / (lambda1 + lambda2 + 0.0001), lambda1 + lambda2 > 0.0001);

    // Flow-guided crawling offset
    let t = time * crawlSpeed;
    let flowAngle = atan2(eigenvec.y, eigenvec.x);
    let crawlOffset = vec2<f32>(
        sin(flowAngle + t * 5.0 + uv.x * 20.0) * 0.06 * coherency,
        cos(flowAngle + t * 3.0 + uv.y * 15.0) * 0.06 * coherency
    );

    let crawledUV = uv + crawlOffset;
    let region = floor(crawledUV * vec2<f32>(10.0, 8.0));
    let hash = hash3(vec3<f32>(region.x * 100.0, region.y * 100.0, time * 2.0));
    let swapPattern = u32(hash.x * 6.0);

    var result = src;
    if (swapPattern == 0u) { result = vec3<f32>(src.b, src.r, src.g); }
    else if (swapPattern == 1u) { result = vec3<f32>(src.g, src.b, src.r); }
    else if (swapPattern == 2u) { result = vec3<f32>(1.0) - src; }
    else if (swapPattern == 3u) { result = vec3<f32>(src.g, src.r, src.b); }
    else if (swapPattern == 4u) {
        let channel = u32(hash.y * 3.0);
        if (channel == 0u) { result = vec3<f32>(src.r * 2.0, src.g, src.b); }
        else if (channel == 1u) { result = vec3<f32>(src.r, src.g * 2.0, src.b); }
        else { result = vec3<f32>(src.r, src.g, src.b * 2.0); }
    } else {
        let gray = dot(src, vec3<f32>(0.299, 0.587, 0.114));
        result = vec3<f32>(gray, gray, gray);
    }
    var swappedColor = mix(src, result, swapIntensity * coherency);

    // Feedback
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let animatedMix = feedbackMix + sin(time * 3.0 + uv.x * 5.0) * 0.1;
    swappedColor = mix(swappedColor, prev, animatedMix);

    // Flow-colored LIC tint
    let flowNorm = flowAngle * 0.15915 + 0.5;
    let flowColor = palette(flowNorm, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67));
    swappedColor = mix(swappedColor, flowColor * 0.4 + swappedColor * 0.6, coherency * 0.5);

    // Flash
    let flash = step(0.95, fract(time * flashRate + region.x * 10.0 + region.y * 7.0));
    let flashColor = vec3<f32>(flash, flash * 0.5, flash * 0.8);
    let flashIntensity = 0.15;
    var finalColor = mix(swappedColor, flashColor, flash * flashIntensity);

    let crawlGlow = length(crawledUV - uv) * 5.0 * 0.1;
    let glowColor = vec3<f32>(0.8, 0.4, 1.0) * crawlGlow;
    finalColor = finalColor + glowColor;

    textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, 1.0));
    textureStore(dataTextureA, gid.xy, vec4<f32>(finalColor, 1.0));

    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
