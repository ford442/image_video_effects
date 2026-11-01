// ═══════════════════════════════════════════════════════════════════
//  Ink Dispersion RGBA
//  Category: artistic
//  Features: rgba, fluid-sim, curl-noise, advection, alpha-density, mouse-spawn
//  Upgraded: 2026-11-01
//  Ideas: pigment granulation (static paper-fibre grain settles ink in valleys); coffee-ring dot rims (pigment pools at the boundary, thin translucent centre); wet-bleed dot edges (noise-warped boundary that spreads with ink amount)
//  A packing: display RGBA (ink colour, ink coverage)
//  By: Codex
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: 4 user params mapped 0..1

fn getLuma(color_1: vec3<f32>) -> f32 {
    return dot(color_1, vec3<f32>(0.299, 0.587, 0.114));
}

fn hash12_(p: vec2<f32>) -> f32 {
    var p3_ = fract(vec3<f32>(p.xyx) * 0.1031);
    p3_ = p3_ + dot(p3_, p3_.yzx + 33.33);
    return fract((p3_.x + p3_.y) * p3_.z);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12_(i), hash12_(i + vec2<f32>(1.0, 0.0)), w.x),
               mix(hash12_(i + vec2<f32>(0.0, 1.0)), hash12_(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let dotSize = u.zoom_params.x * 20.0 + 2.0;
    let edgeThresh = max(0.01, (1.0 - u.zoom_params.y) * 0.5);
    let levels = floor(u.zoom_params.z * 10.0) + 2.0;
    let inkDensity = u.zoom_params.w;
    let pixelSize = vec2<f32>(1.0) / resolution;
    let pix = vec2<f32>(global_id.xy);

    var gx = vec3<f32>(0.0);
    var gy = vec3<f32>(0.0);
    for (var i: i32 = -1; i <= 1; i = i + 1) {
        for (var j: i32 = -1; j <= 1; j = j + 1) {
            let offset = vec2<f32>(f32(i), f32(j)) * pixelSize;
            let s = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).xyz;
            let l = getLuma(s);
            var wx = 0.0;
            var wy = 0.0;
            if (i == -1) { wx = -1.0; }
            if (i == 1) { wx = 1.0; }
            if (j == -1) { wy = -1.0; }
            if (j == 1) { wy = 1.0; }
            if (j == 0) { wx = wx * 2.0; }
            if (i == 0) { wy = wy * 2.0; }
            gx = gx + vec3<f32>(l * wx);
            gy = gy + vec3<f32>(l * wy);
        }
    }
    // Sobel magnitude (luma is replicated across channels; the old length(gx+gy) only saw diagonals)
    let edge = length(vec2<f32>(gx.x, gy.x));
    let isEdge = select(0.0, 1.0, edge > edgeThresh);

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0).xyz;
    let luma = getLuma(src);
    let color = floor(src * levels) / vec3<f32>(levels);

    // IDEA 3: wet-bleed. The dot boundary is warped by low-frequency noise; more ink = more spread.
    let gridPos = pix / vec2<f32>(dotSize);
    let gridCenter = floor(gridPos) + vec2<f32>(0.5);
    let bleed = 0.08 + 0.35 * inkDensity;
    let warp = (vnoise(gridPos * 2.3 + vec2<f32>(7.1, 3.7)) - 0.5) * bleed;
    let dist = length(gridPos - gridCenter) + warp;
    let dotRadius = (1.0 - luma) * 0.7;
    let isDot = select(0.0, 1.0, dist < dotRadius);

    // IDEA 1: granulation. Static anisotropic paper fibre (two crossed octaves); pigment
    // settles in the valleys so dark ink is grainier than the paper.
    let fibre = 0.6 * vnoise(vec2<f32>(pix.x * 0.45, pix.y * 0.06)) + 0.4 * vnoise(vec2<f32>(pix.x * 0.07, pix.y * 0.38));

    var finalColor = color;
    var ink_alpha = 0.0;

    if (isEdge > 0.5) {
        ink_alpha = inkDensity * 0.9 + 0.05;
        finalColor = mix(finalColor, vec3<f32>(0.02, 0.02, 0.04), isEdge * inkDensity);
        ink_alpha = ink_alpha * mix(0.8, 1.2, fibre);
    }
    if (isDot > 0.5) {
        // IDEA 2: coffee ring. rim = 0 at the dot centre, 1 at the boundary.
        let rim = smoothstep(dotRadius * 0.45, max(dotRadius, 0.001), dist);
        let dot_coverage = smoothstep(0.0, 0.7, 1.0 - luma);
        let dot_alpha = dot_coverage * inkDensity * 0.85 * mix(0.6, 1.0, rim) * mix(0.75, 1.25, fibre);
        finalColor = mix(finalColor, finalColor * mix(0.85, 0.5, rim), 0.8);
        ink_alpha = max(ink_alpha, dot_alpha);
    }
    if (ink_alpha < 0.01) {
        ink_alpha = mix(0.15, 0.45, luma * inkDensity);
    }

    ink_alpha = clamp(ink_alpha * (0.95 + 0.05 * fibre), 0.0, 1.0);

    if (mousePos.x >= 0.0) {
        let d = length(uv - mousePos);
        let vignette = smoothstep(0.8, 0.2, d * 0.5);
        finalColor = finalColor * vignette;
        ink_alpha = mix(ink_alpha, min(1.0, ink_alpha * 1.2), vignette * 0.5);
    }

    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, ink_alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(ink_alpha, 0.0, 0.0, ink_alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, ink_alpha));
}
