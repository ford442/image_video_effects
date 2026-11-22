// ═══════════════════════════════════════════════════════════════════
//  Ink Dispersion RGBA
//  Category: artistic
//  Features: rgba, halftone, ink-wicking, alpha-density
//  Upgraded: 2026-11-01, 2026-11-22
//  Ideas: pigment granulation (static paper-fibre grain settles ink in valleys); coffee-ring dot rims (pigment pools at the boundary, thin translucent centre); wet-bleed dot edges (noise-warped boundary that spreads with ink amount); fibre-guided capillary wick (exact C: ink creeps into darker-neighbour halos along the paper fibres); dye chromatography fringe (chromaticity low-passed over a wider C ring so dye runs ahead of the pigment)
//  A packing: display RGBA (ink colour, ink coverage) — C is read back with the same meaning
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
    // The two crossed octaves are kept separate: octave V is long in y (vertical fibres),
    // octave H is long in x (horizontal fibres). Their sum is the HEAD granulation (unchanged);
    // each one is also the wicking weight of its own axis in Idea 4 below.
    let fibV = vnoise(vec2<f32>(pix.x * 0.45, pix.y * 0.06));
    let fibH = vnoise(vec2<f32>(pix.x * 0.07, pix.y * 0.38));
    let fibre = 0.6 * fibV + 0.4 * fibH;

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

    // ── Idea 4: fibre-guided capillary wick (exact C) ────────────────────
    // Ink on paper creeps along the fibres. Each pixel looks at the previous frame's
    // 4-neighbours (A is display RGBA, so C reads back as colour + coverage), pulls
    // from the one that pulls hardest (a neighbour that is DARKER than this pixel, scaled
    // by the fibre octave running along that axis) and takes a wick-weighted step toward
    // its colour and coverage. Dots grow a feathered, fibre-streaked halo and never erode.
    // Fresh source is mixed in every frame (step <= wick < 1), so a still image settles.
    let cc = vec2<i32>(global_id.xy);
    let cmax = vec2<i32>(resolution) - vec2<i32>(1);
    let pL = textureLoad(dataTextureC, clamp(cc + vec2<i32>(-1, 0), vec2<i32>(0), cmax), 0);
    let pR = textureLoad(dataTextureC, clamp(cc + vec2<i32>(1, 0), vec2<i32>(0), cmax), 0);
    let pU = textureLoad(dataTextureC, clamp(cc + vec2<i32>(0, -1), vec2<i32>(0), cmax), 0);
    let pD = textureLoad(dataTextureC, clamp(cc + vec2<i32>(0, 1), vec2<i32>(0), cmax), 0);
    let aH = (0.35 + fibH) / 0.85;                      // mean ~1: horizontal fibres carry L/R
    let aV = (0.35 + fibV) / 0.85;                      // vertical fibres carry U/D
    let ownL0 = getLuma(finalColor);
    // empty C (first frame / another shader's data, coverage ~0) pulls nothing
    let pullL = aH * smoothstep(0.01, 0.12, ownL0 - getLuma(pL.rgb)) * step(0.05, pL.a);
    let pullR = aH * smoothstep(0.01, 0.12, ownL0 - getLuma(pR.rgb)) * step(0.05, pR.a);
    let pullU = aV * smoothstep(0.01, 0.12, ownL0 - getLuma(pU.rgb)) * step(0.05, pU.a);
    let pullD = aV * smoothstep(0.01, 0.12, ownL0 - getLuma(pD.rgb)) * step(0.05, pD.a);
    var bestPull = pullL;
    var nbCol = pL.rgb;
    var nbCov = pL.a;
    let useR = step(bestPull, pullR);
    bestPull = mix(bestPull, pullR, useR); nbCol = mix(nbCol, pR.rgb, useR); nbCov = mix(nbCov, pR.a, useR);
    let useU = step(bestPull, pullU);
    bestPull = mix(bestPull, pullU, useU); nbCol = mix(nbCol, pU.rgb, useU); nbCov = mix(nbCov, pU.a, useU);
    let useD = step(bestPull, pullD);
    bestPull = mix(bestPull, pullD, useD); nbCol = mix(nbCol, pD.rgb, useD); nbCov = mix(nbCov, pD.a, useD);
    let wick = 0.40 + 0.35 * inkDensity;                // more ink, more wicking (same role as the wet-bleed)
    let wet = clamp(wick * bestPull, 0.0, 0.85);

    // ── Idea 5: dye chromatography fringe (wider C ring) ─────────────────
    // The dye in a coloured ink outruns the dark pigment (paper chromatography): where the
    // +-3 px ring of the same C history holds darker ink than this pixel but the short-range
    // wick above has not reached it, the pixel takes on the ring's chromaticity, pushed
    // more saturated. Luma is untouched (chromaticity is colour / luma), so the dark pigment
    // keeps its short range and a coloured, light halo runs ahead of it.
    let qL = textureLoad(dataTextureC, clamp(cc + vec2<i32>(-3, 0), vec2<i32>(0), cmax), 0);
    let qR = textureLoad(dataTextureC, clamp(cc + vec2<i32>(3, 0), vec2<i32>(0), cmax), 0);
    let qU = textureLoad(dataTextureC, clamp(cc + vec2<i32>(0, -3), vec2<i32>(0), cmax), 0);
    let qD = textureLoad(dataTextureC, clamp(cc + vec2<i32>(0, 3), vec2<i32>(0), cmax), 0);
    let outCol = (qL.rgb + qR.rgb + qU.rgb + qD.rgb) * 0.25;
    let outSeen = step(0.05, (qL.a + qR.a + qU.a + qD.a) * 0.25);
    let ringInk = smoothstep(0.01, 0.15, ownL0 - getLuma(outCol)) * (1.0 - wet) * outSeen;
    let dye = clamp(wick * 1.6, 0.0, 0.9) * ringInk;

    // apply the short-range wick first, then move the chromaticity of the result toward the ring's
    finalColor = mix(finalColor, nbCol, wet);
    ink_alpha = mix(ink_alpha, max(ink_alpha, nbCov), wet);
    let wL = max(getLuma(finalColor), 0.0);
    let ownChrom = finalColor / max(wL, 0.08) - vec3<f32>(1.0);   // luma-neutral by construction
    let outChrom = outCol / max(getLuma(outCol), 0.08) - vec3<f32>(1.0);
    finalColor = clamp(vec3<f32>(wL) * (vec3<f32>(1.0) + mix(ownChrom, outChrom * 1.8, dye)), vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, ink_alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(ink_alpha, 0.0, 0.0, ink_alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, ink_alpha));
}
