// ═══════════════════════════════════════════════════════════════════
//  fractal-noise-dissolve-nlm
//  Category: advanced-hybrid
//  Features: fractal-dissolve, non-local-means, self-similarity-map
//  Complexity: Very High
//  Chunks From: fractal-noise-dissolve.wgsl, conv-non-local-means.wgsl
//  Created: 2026-04-18
//  By: Agent CB-21 — Distortion & Material Enhancer
// ═══════════════════════════════════════════════════════════════════
//  A fractal noise dissolve where the NLM self-similarity map drives
//  edge behavior — unique texture regions dissolve slower while
//  repetitive regions dissolve faster. Creates organic erosion
//  patterns with artistic patch-based smoothing on remaining areas.
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(hash22(i + vec2<f32>(0.0, 0.0)), f - vec2<f32>(0.0, 0.0)),
                   dot(hash22(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0)), u.x),
               mix(dot(hash22(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0)),
                   dot(hash22(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn patchDistance(uv1: vec2<f32>, uv2: vec2<f32>, patchRadius: i32, pixelSize: vec2<f32>) -> f32 {
    var dist = 0.0;
    for (var dy = -patchRadius; dy <= patchRadius; dy++) {
        for (var dx = -patchRadius; dx <= patchRadius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let p1 = textureSampleLevel(readTexture, u_sampler, uv1 + offset, 0.0).rgb;
            let p2 = textureSampleLevel(readTexture, u_sampler, uv2 + offset, 0.0).rgb;
            let diff = p1 - p2;
            dist += dot(diff, diff);
        }
    }
    return dist;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let aspect = res.x / res.y;

    // Parameters
    let noiseScale = u.zoom_params.x * 20.0 + 5.0;
    let radius = u.zoom_params.y * 0.5;
    let edgeWidth = u.zoom_params.z * 0.2;
    let nlmMix = u.zoom_params.w;

    // Noise generation for dissolve
    var n = noise(uv * noiseScale + time);
    n += noise(uv * noiseScale * 2.0 - time) * 0.5;
    n = n * 0.5 + 0.5;

    // NLM self-similarity computation
    let patchRadius = 1;
    let searchRadius = 4;
    let hParam = 0.02;
    let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    var similaritySum = 0.0;
    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;

    for (var dy = -searchRadius; dy <= searchRadius; dy++) {
        for (var dx = -searchRadius; dx <= searchRadius; dx++) {
            if (dx == 0 && dy == 0) { continue; }
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let neighborUV = uv + offset;
            let pd = patchDistance(uv, neighborUV, patchRadius, pixelSize);
            let weight = exp(-pd / hParam);
            let neighborColor = textureSampleLevel(readTexture, u_sampler, neighborUV, 0.0).rgb;
            accumColor += neighborColor * weight;
            accumWeight += weight;
            similaritySum += weight;
        }
    }

    accumColor += center;
    accumWeight += 1.0;
    similaritySum += 1.0;

    let avgSimilarity = similaritySum / f32(searchRadius * searchRadius * 4 + 1);
    // High similarity = repetitive texture = dissolves faster
    // Low similarity = unique texture = dissolves slower
    let dissolveBias = avgSimilarity * 0.15;

    var nlmResult = center;
    if (accumWeight > 0.001) {
        nlmResult = mix(center, accumColor / accumWeight, nlmMix);
    }

    // Dissolve mask: distance from mouse + noise + similarity bias
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mousePos * vec2<f32>(aspect, 1.0));
    let mask = smoothstep(radius, radius + edgeWidth, dist + (n * 0.2 - 0.1) - dissolveBias);

    // Burn effect at edge
    let edge = 1.0 - smoothstep(radius, radius + edgeWidth * 2.0, dist + (n * 0.2 - 0.1) - dissolveBias);
    let burn = vec3<f32>(1.0, 0.5, 0.2) * edge * 2.0 * (1.0 - mask);

    // Apply NLM smoothing to remaining pixels, dissolve to black
    var finalColor = nlmResult * mask + burn;

    // Importance map in alpha: unique textures = high alpha = survive longer
    let importance = 1.0 - avgSimilarity;

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, importance * mask));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
