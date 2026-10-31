// ═══════════════════════════════════════════════════════════════════
//  Long Exposure Light Painting
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-30
//  Ideas: reciprocity-law fade; highlight-only plate mix; light-trail tangent; reciprocity color
//  A packing: raw HDR exposure RGB (C is previous accumulation); A.a = exposure density
// ═══════════════════════════════════════════════════════════════════
//  zoom_params: x=accumulation_speed, y=decay_rate, z=glow_radius, w=threshold
//  KEEP: positional eraser, ripple flashes, 4-tap C glow, FFT band decay

#include "_prelude.wgsl"

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res   = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv    = vec2<f32>(gid.xy) / res;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let time   = u.config.x;
    let aspect = res.x / max(res.y, 1.0);

    let current  = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let curRGB   = current.rgb * (1.0 + bass * 0.4);

    let prevAccum = textureLoad(dataTextureC, coord, 0);
    let prevRGB   = prevAccum.rgb;

    let threshold  = 0.05 + u.zoom_params.w * 0.35;
    let luma       = luminance(curRGB);
    let aboveThresh = clamp((luma - threshold) / max(1.0 - threshold, 0.001), 0.0, 1.0);

    let accumSpeed = 0.04 + u.zoom_params.x * 0.20;
    let contribution = curRGB * aboveThresh * accumSpeed * (1.0 + treble * 0.25);

    let bandIdx   = clamp(u32(uv.y * 8.0), 0u, 7u) + 1u;
    let bandDrift = plasmaBuffer[bandIdx].x * 0.002;
    let decayRate = 0.97 + u.zoom_params.y * 0.029 + bandDrift;
    // Idea 1 — reciprocity-law fade: dim trails die faster than hot ones.
    let prevLuma = luminance(prevRGB);
    let recip = mix(0.92, 1.0, smoothstep(0.05, 0.85, prevLuma));
    // ── Idea 2: reciprocity color ───────────────────────────────────
    // Dim latent image shifts cool; the hot core keeps its color.
    // Amount rides the existing decay slider.
    let cool = vec3<f32>(0.82, 0.92, 1.08);
    let coolMix = (1.0 - smoothstep(0.05, 0.7, prevLuma)) * u.zoom_params.y * 0.35;
    let decayed   = prevRGB * clamp(decayRate * recip, 0.90, 0.999) * mix(vec3<f32>(1.0), cool, coolMix);

    let mouseDown  = u.zoom_config.w;
    let mUV        = u.zoom_config.yz;
    let brushDist  = length(vec2<f32>((uv.x - mUV.x) * aspect, uv.y - mUV.y));
    let brush      = 1.0 - smoothstep(0.0, 0.25, brushDist);
    let resetMix   = clamp(mouseDown * (0.015 + brush * 0.985), 0.0, 1.0);
    let afterReset = mix(decayed, vec3<f32>(0.0), resetMix);

    var accumulated = clamp(afterReset + contribution, vec3<f32>(0.0), vec3<f32>(1.5));

    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple  = u.ripples[i];
        let elapsed = time - ripple.z;
        let live = f32(elapsed > 0.0 && elapsed < 1.5);
        let rDist = length(vec2<f32>((uv.x - ripple.x) * aspect, uv.y - ripple.y));
        let blob  = smoothstep(0.25, 0.0, rDist) * exp(-max(elapsed, 0.0) * 2.0) * live;
        let warm  = vec3<f32>(1.0, 0.9, 0.75);
        accumulated = clamp(accumulated + warm * blob * 0.6, vec3<f32>(0.0), vec3<f32>(1.5));
    }

    let glowR  = max(0.002, u.zoom_params.z * 0.008) * res.x;
    let gStep  = clamp(i32(glowR), 1, 64);
    let gMax   = vec2<i32>(res) - vec2<i32>(1);
    var glow   = accumulated;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(gStep, 0), vec2<i32>(0), gMax), 0).rgb;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(-gStep, 0), vec2<i32>(0), gMax), 0).rgb;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, gStep), vec2<i32>(0), gMax), 0).rgb;
    glow += textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -gStep), vec2<i32>(0), gMax), 0).rgb;
    let glowAmt  = (0.1 + mids * 0.3) * u.zoom_params.z;
    let glowBlend = glow * (1.0 / 5.0) * glowAmt;
    accumulated   = clamp(accumulated + glowBlend, vec3<f32>(0.0), vec3<f32>(1.5));

    // ── Idea 1: light-trail tangent ─────────────────────────────────
    // The plate's own luminance gradient points along the stroke. One
    // extra exact load continues the streak in that direction.
    let trailStep = max(gStep / 2, 1);
    let lumXp = luminance(textureLoad(dataTextureC, clamp(coord + vec2<i32>(trailStep, 0), vec2<i32>(0), gMax), 0).rgb);
    let lumXm = luminance(textureLoad(dataTextureC, clamp(coord - vec2<i32>(trailStep, 0), vec2<i32>(0), gMax), 0).rgb);
    let lumYp = luminance(textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, trailStep), vec2<i32>(0), gMax), 0).rgb);
    let lumYm = luminance(textureLoad(dataTextureC, clamp(coord - vec2<i32>(0, trailStep), vec2<i32>(0), gMax), 0).rgb);
    let grad = vec2<f32>(lumXp - lumXm, lumYp - lumYm);
    let gradLen = length(grad);
    let trailDir = grad / max(gradLen, 0.001);
    let trailCoord = clamp(
        coord + vec2<i32>(i32(round(trailDir.x * f32(trailStep))), i32(round(trailDir.y * f32(trailStep)))),
        vec2<i32>(0), gMax);
    let trailCol = textureLoad(dataTextureC, trailCoord, 0).rgb;
    let trailAmt = smoothstep(0.02, 0.2, gradLen) * u.zoom_params.z * aboveThresh;
    accumulated = clamp(accumulated + trailCol * trailAmt * 0.35, vec3<f32>(0.0), vec3<f32>(1.5));

    let sparkleMask = smoothstep(0.9, 1.4, luminance(accumulated));
    let shimmer     = 0.5 + 0.5 * sin(time * 9.0 + uv.x * 61.0 + uv.y * 47.0);
    accumulated     = clamp(accumulated + accumulated * sparkleMask * shimmer * treble * 0.15, vec3<f32>(0.0), vec3<f32>(1.5));

    // Idea 2 — highlight-only plate: live frame prints through the hottest traces.
    let plateMix = aboveThresh * 0.22;
    let plateRGB = mix(accumulated, max(accumulated, curRGB), plateMix);

    let mapped = plateRGB / (plateRGB + vec3<f32>(1.0));
    let finalRGB = aces(mapped);
    let accumLuma = luminance(finalRGB);
    let alpha     = clamp(accumLuma * 1.4 + bass * 0.08 + aboveThresh * 0.15, 0.0, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(accumulated, clamp(luminance(accumulated), 0.0, 1.0)));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
