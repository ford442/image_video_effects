// ═══════════════════════════════════════════════════════════════════
//  fractal-noise-dissolve-nlm
//  Category: advanced-hybrid
//  Features: fractal-dissolve, non-local-means, self-similarity-map, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-11-20
//  Ideas: similarity-scaled edge; NLM residual; ash
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  A fractal noise dissolve where the NLM self-similarity map drives
//  edge behavior — unique texture regions dissolve slower while
//  repetitive regions dissolve faster. Creates organic erosion
//  patterns with artistic patch-based smoothing on remaining areas.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

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

@compute @workgroup_size(16, 16, 1)
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

    // ── Idea 1: similarity-scaled edge ────────────────────────────
    // Repetitive patches burn on a tighter front. Edge Width is the base.
    let edgeScale = mix(1.4, 0.62, clamp(dissolveBias / 0.15, 0.0, 1.0));
    let edgeW = max(edgeWidth * edgeScale, 0.001);
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mousePos * vec2<f32>(aspect, 1.0));
    let front = dist + (n * 0.2 - 0.1) - dissolveBias;
    let mask = smoothstep(radius, radius + edgeW, front);

    // Burn effect at edge. Bass flares the existing fire.
    let bass = plasmaBuffer[0].x;
    let edge = 1.0 - smoothstep(radius, radius + edgeW * 2.0, front);
    let burn = vec3<f32>(1.0, 0.5, 0.2) * edge * (2.0 + bass * 0.5) * (1.0 - mask);

    // ── Idea 2: NLM residual ──────────────────────────────────────
    // Detail the filter removed, put back on the surviving side.
    // NLM Mix still owns how smooth that side is.
    let residual = (center - nlmResult) * (1.0 - nlmMix) * mask * 0.85;
    // ── Idea 3: ash ───────────────────────────────────────────────
    // The dissolved side keeps a dark remainder under the burn.
    let ash = nlmResult * 0.07 * (1.0 - mask);
    var finalColor = nlmResult * mask + residual + ash + burn;
    finalColor = aces(max(finalColor, vec3<f32>(0.0)));

    // Importance map in alpha: unique textures = high alpha = survive longer
    let importance = 1.0 - avgSimilarity;
    let alpha = clamp(importance * mask + edge * 0.35, 0.0, 1.0);
    let pixel = vec2<i32>(global_id.xy);

    textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(finalColor, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
