// ═══════════════════════════════════════════════════════════════════
//  Reaction Convolution
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven, audio-reactive, depth-aware, temporal
//  Convolution Type: gray-scott-reaction-diffusion-filter
//  Complexity: High
//  Upgraded: 2026-09-08, 2026-11-09
//  Ideas: C.rg chemical persistence; Pearson F/k from feed slider; isotropic 9-point Laplacian of the stored chemicals (§12.2D); luma-painted Pearson regime
//  A packing: A, B, mixed-blue, activity (C.rg = chemicals)
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    R: Chemical A concentration (needs f32 precision for stable PDE integration)
//    G: Chemical B concentration
//    B: Filtered image mixed with R-D pattern
//    Alpha: Reaction activity — how vigorously the pattern is evolving here
//
//  Runs 1 step of Gray-Scott reaction-diffusion per frame as a FILTER on
//  the input image, using image luminance to seed the A/B concentrations.
//
//  MOUSE INTERACTIVITY:
//    Mouse position injects chemical B (creating pattern nucleation).
//    Mouse down increases feed rate locally. Ripples create traveling
//    reaction fronts across the image.
//
//  UPGRADES: ACES tone mapping, chromatic aberration on pattern edges,
//    plasmaBuffer bass-driven reaction rate, dataTextureC temporal pattern
//    evolution, depth-based pattern scale, semantic alpha.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Stored chemicals (A,B) at a clamped texel — exact load, never filtered.
fn chemAt(p: vec2<i32>, hi: vec2<i32>) -> vec2<f32> {
    return clamp(textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0).rg, vec2<f32>(0.0), vec2<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let pixel = vec2<i32>(global_id.xy);

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Depth for pattern scale modulation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFactor = smoothstep(0.0, 1.0, depth);

    // Parameters
    let diffA = mix(0.8, 1.0, u.zoom_params.x);
    let diffB = mix(0.2, 0.5, u.zoom_params.y);
    let feedBase = mix(0.01, 0.09, u.zoom_params.z) * (1.0 + bass * 0.8);
    let mouseInfluence = u.zoom_params.w;

    // Depth-based pattern scale: smaller patterns in foreground
    let patternScale = mix(1.0, 0.4, depthFactor);
    let scaledPixelSize = pixelSize * patternScale;

    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let inputLuma = dot(inputColor, vec3<f32>(0.299, 0.587, 0.114));

    let prevChem = textureLoad(dataTextureC, pixel, 0);
    let centerA = mix(inputLuma, clamp(prevChem.r, 0.0, 1.0), 0.82);
    let dx = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(scaledPixelSize.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let dy = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, scaledPixelSize.y), 0.0).rgb;
    let edge = length(dx - inputColor) + length(dy - inputColor);
    let centerB = mix(edge * 2.0, clamp(prevChem.g, 0.0, 1.0), 0.82);

    let n = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, scaledPixelSize.y), 0.0);
    let s = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -scaledPixelSize.y), 0.0);
    let e = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(scaledPixelSize.x, 0.0), 0.0);
    let w = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-scaledPixelSize.x, 0.0), 0.0);

    let nLuma = dot(n.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let sLuma = dot(s.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let eLuma = dot(e.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let wLuma = dot(w.rgb, vec3<f32>(0.299, 0.587, 0.114));

    let nEdge = length(n.rgb - inputColor) + length(n.rgb - textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, scaledPixelSize.y * 2.0), 0.0).rgb);
    let sEdge = length(s.rgb - inputColor) + length(s.rgb - textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -scaledPixelSize.y * 2.0), 0.0).rgb);
    let eEdge = length(e.rgb - inputColor) + length(e.rgb - textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(scaledPixelSize.x * 2.0, 0.0), 0.0).rgb);
    let wEdge = length(w.rgb - inputColor) + length(w.rgb - textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-scaledPixelSize.x * 2.0, 0.0), 0.0).rgb);

    let lapAImg = (nLuma + sLuma + eLuma + wLuma) * 0.25 - inputLuma;
    let lapBImg = (nEdge + sEdge + eEdge + wEdge) * 0.25 - edge * 2.0;

    // ── Idea 1: isotropic 9-point Laplacian of the STORED chemicals (§12.2D) ──
    // HEAD's Laplacians only see the photo, so the chemicals in C.rg never
    // diffused: the "PDE" was a relaxation toward the picture and fronts could
    // not travel. The same operator on the stored state (weights 0.2 edges /
    // 0.05 corners, no 5-point axis bias) lets fronts actually propagate; it is
    // blended with the image term so the photo still seeds and steers the
    // pattern. Weights sum to 1, so this is the same avg − centre scale.
    let hiPix = vec2<i32>(i32(res.x) - 1, i32(res.y) - 1);
    let chemEdge = chemAt(pixel + vec2<i32>(1, 0), hiPix) + chemAt(pixel + vec2<i32>(-1, 0), hiPix)
                 + chemAt(pixel + vec2<i32>(0, 1), hiPix) + chemAt(pixel + vec2<i32>(0, -1), hiPix);
    let chemCorner = chemAt(pixel + vec2<i32>(1, 1), hiPix) + chemAt(pixel + vec2<i32>(-1, 1), hiPix)
                   + chemAt(pixel + vec2<i32>(1, -1), hiPix) + chemAt(pixel + vec2<i32>(-1, -1), hiPix);
    let lapChem = 0.2 * chemEdge + 0.05 * chemCorner - clamp(prevChem.rg, vec2<f32>(0.0), vec2<f32>(1.0));
    let lapA = mix(lapAImg, lapChem.x, 0.55);
    let lapB = mix(lapBImg, lapChem.y, 0.55);

    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 15.0) * mouseInfluence;
    let mouseB = mouseFactor * (1.0 + mouseDown * 2.0);

    var rippleFeed = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(uv - rPos);
            let wave = exp(-pow((rDist - rElapsed * 0.2) * 12.0, 2.0));
            rippleFeed = rippleFeed + wave * (1.0 - rElapsed / 3.0) * 0.05;
        }
    }

    // ── Idea 2: luma-painted Pearson regime ──
    // Pearson's map: F (with k on the same line) decides spots vs stripes vs
    // mitosis. A single global F gives one regime for the whole frame; scaling
    // the local F by the source luma paints bright areas toward spots and dark
    // areas toward labyrinth stripes. Feed Rate keeps its role (global F).
    let feedLocal = feedBase * mix(0.80, 1.20, inputLuma);
    let effectiveFeed = feedLocal + rippleFeed + mouseFactor * 0.03;
    let pearsonK = mix(effectiveFeed + 0.04, effectiveFeed * 0.5, u.zoom_params.z);
    let kill = pearsonK + mouseFactor * 0.02;
    let reaction = centerA * centerB * centerB;

    let newA = centerA + (diffA * lapA - reaction + effectiveFeed * (1.0 - centerA)) * 0.5;
    let newB = centerB + (diffB * lapB + reaction - (kill + effectiveFeed) * centerB + mouseB) * 0.5;

    let clampedA = clamp(newA, 0.0, 1.0);
    let clampedB = clamp(newB, 0.0, 1.0);

    let pattern = clampedA - clampedB;
    var rdColor = vec3<f32>(
        pattern * 0.8 + clampedB * 0.5,
        pattern * 0.5 + clampedA * 0.3,
        clampedB * 0.8 + 0.1
    );
    let mixFactor = 0.5 + mouseFactor * 0.3;
    var finalColor = mix(inputColor, rdColor, mixFactor);

    // Chromatic aberration on pattern edges
    let caStrength = edge * 0.015 + treble * 0.003;
    let caDir = normalize(uv - vec2<f32>(0.5) + 0.001);
    let rUV = uv + caDir * caStrength;
    let bUV = uv - caDir * caStrength;
    let rSample = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let bSample = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let chromatic = vec3<f32>(rSample, finalColor.g, bSample);
    finalColor = mix(finalColor, chromatic, clamp(caStrength * 30.0, 0.0, 0.4));

    // Temporal feedback: blend with previous frame
    let temporalDecay = mix(0.5, 0.85, depthFactor);
    finalColor = mix(finalColor, vec3<f32>(prevChem.r, prevChem.g, prevChem.b), temporalDecay * 0.12);

    // ACES tone mapping
    finalColor = acesToneMap(finalColor * (1.0 + mids * 0.25));

    // Semantic alpha: reaction activity = how fast things are changing
    let reactionActivity = clamp(abs(newA - centerA) + abs(newB - centerB) * 2.0, 0.0, 1.0);
    let semanticAlpha = mix(reactionActivity, 0.15, depthFactor * 0.3);

    let packed = vec4<f32>(clampedA, clampedB, finalColor.b, semanticAlpha);
    textureStore(writeTexture, pixel, packed);
    textureStore(dataTextureA, pixel, packed);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
