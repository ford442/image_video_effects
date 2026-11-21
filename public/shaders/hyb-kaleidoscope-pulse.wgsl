// ═══════════════════════════════════════════════════════════════════
//  hyb-kaleidoscope-pulse  (RETRY expanded upgrade)
//  Category: hybrid
//  Features: kaleidoscope, radial-pulse, image-remix, upgraded-rgba,
//            depth-aware, aces-tone-map, domain-warp, ign-dither,
//            sdf-primitives, strange-attractor, chromatic-split
//  Upgraded: 2026-11-21
//  Ideas: mirror-bounce fold-count material (§12.2E); object-cell twist (§12.2E)
//  Rescue: wedge count snapped to an integer (a fractional count left an angular seam on the left axis)
//  A packing: none (A/B not written, C not read); display RGBA in writeTexture
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}
fn fbmWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
    // Two-layer domain warp: FBM displaces the domain of a second FBM pass.
    var q = vec2<f32>(fbm(p + vec2<f32>(0.0, 0.0), 3),
                      fbm(p + vec2<f32>(5.2, 1.3), 3));
    q += t * 0.15;
    var r = vec2<f32>(fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2), 3),
                      fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8), 3));
    return r;
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    let f = fract(p * vec2<f32>(0.06711056, 0.00583715));
    return fract(f.x * f.y * 52.9829189);
}
fn kaleido(uv: vec2<f32>, segs: f32, phase: f32) -> vec2<f32> {
    let r = length(uv);
    var a = atan2(uv.y, uv.x) + phase;
    let seg = TAU / max(segs, 1.0);
    a = abs(((a % seg) + seg) % seg - seg * 0.5);
    return vec2<f32>(cos(a), sin(a)) * r;
}
// ── Idea 1 support (fold-count as material, §12.2E): the same fold as kaleido(), but it also
// hands back how many mirror reflections the wedge has taken (the shorter way round the tube)
// and the true distance to the nearest mirror line (every crease of the |.| fold is a mirror).
fn kaleidoFold(uv: vec2<f32>, segs: f32, phase: f32) -> vec4<f32> {
    let r = length(uv);
    let a0 = atan2(uv.y, uv.x) + phase;
    let seg = TAU / max(segs, 1.0);
    let halfSeg = seg * 0.5;
    let a = abs(((a0 % seg) + seg) % seg - halfSeg);
    let m = floor(a0 / halfSeg);
    let M = 2.0 * max(floor(segs + 0.5), 1.0);
    let mw = m - M * floor(m / M);
    let bounces = min(mw, M - mw);
    let mirrorDist = min(a, halfSeg - a) * r;
    return vec4<f32>(cos(a) * r, sin(a) * r, bounces, mirrorDist);
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
fn sdfStar(p: vec2<f32>, rays: f32, radius: f32, inner: f32) -> f32 {
    let a = atan2(p.y, p.x);
    let seg = TAU / max(rays, 1.0);
    let folded = abs(((a % seg) + seg) % seg - seg * 0.5);
    let r = length(p);
    let starR = mix(inner * radius, radius, folded / (seg * 0.5));
    return r - starR;
}
fn attractorOrbit(p: vec2<f32>, t: f32) -> f32 {
    // Pickover / Clifford strange-attractor orbit-trap distance.
    var z = p * 3.0;
    var d = 1000.0;
    for (var i = 0; i < 12; i = i + 1) {
        let nx = sin(z.x * 1.8) - cos(z.y * 1.2 + t * 0.3);
        let ny = sin(z.x * 1.1 + t * 0.2) - cos(z.y * 2.1);
        z = vec2<f32>(nx, ny);
        d = min(d, length(z - p * 2.0));
    }
    return smoothstep(0.0, 1.5, d);
}
fn rdPulse(p: vec2<f32>, t: f32, speed: f32, width: f32) -> f32 {
    let d = length(p);
    let phase = d * 8.0 - t * speed * 4.0;
    let wave = sin(phase) * 0.5 + 0.5;
    let envelope = exp(-d * d * 2.0) * (1.0 - smoothstep(0.0, 1.5, d));
    let glow = exp(-d * d / (max(width, 0.001) * max(width, 0.001)));
    return wave * envelope * glow;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coord = vec2<i32>(gid.xy);
    if (any(coord >= vec2<i32>(dims))) { return; }

    let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let time = u.config.x;
    // Rescue: a fractional wedge count cannot close the 2π wrap, leaving a seam on the left axis.
    let segments = floor(mix(3.0, 16.0, clamp(u.zoom_params.x, 0.0, 1.0)) + 0.5);
    let pulseSpeed = mix(0.2, 3.0, clamp(u.zoom_params.y, 0.0, 1.0));
    let pulseWidth = mix(0.05, 0.6, clamp(u.zoom_params.z, 0.0, 1.0));
    let effectMix = clamp(u.zoom_params.w, 0.0, 1.0);

    let centered = uv - 0.5;
    let warpStr = 0.06 + effectMix * 0.14;
    // Richer domain warp with two-layer FBM feedback.
    let warp = fbmWarp(centered * 6.0 + time * 0.2, time) * warpStr;
    // Phase-animated kaleidoscope gives a slow rotational drift.
    let kPhase = time * 0.04;
    let kf = kaleidoFold(centered + warp, segments, kPhase);
    // ── Idea 2: object-cell twist (additive domain twist, §12.2E). The already-folded point is
    // rotated by an angle that grows with radius and breathes at the existing pulse speed, before
    // the texture lookup. Mirror-related pixels share the folded point, so symmetry and the
    // straight mirrors are exact; only the picture inside the cell swirls (centre stays crisp).
    let twistAng = effectMix * 0.35 * sin(time * pulseSpeed * 0.35) * dot(kf.xy, kf.xy) * 4.0;
    let tsn = sin(twistAng);
    let tcs = cos(twistAng);
    let kUV = vec2<f32>(kf.x * tcs - kf.y * tsn, kf.x * tsn + kf.y * tcs);
    let sampleUV = clamp(kUV + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    let kaleidoCol = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Secondary inner kaleidoscope ring for extra depth.
    let innerUV = kaleido(centered * 1.7 + warp * 0.5, segments * 2.0, -kPhase);
    let innerSample = clamp(innerUV + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
    let innerCol = textureSampleLevel(readTexture, u_sampler, innerSample, 0.0);
    var outRGB = mix(kaleidoCol.rgb, innerCol.rgb, 0.25 * effectMix);

    // ── Idea 1: mirror-bounce material (fold-count as material, §12.2E). Each reflection off the
    // silvering loses a little energy and drifts warm: tint^bounces (per channel). Where two
    // mirrors meet there is a hairline groove, a constant ~1.5 px wide.
    let pxUV = 1.0 / f32(min(dims.x, dims.y));
    let mirrorTint = pow(mix(vec3<f32>(1.0), vec3<f32>(0.99, 0.982, 0.965), effectMix), vec3<f32>(kf.z));
    let mirrorSeam = (1.0 - smoothstep(0.0, 1.5 * pxUV, kf.w)) * smoothstep(0.02, 0.10, length(kf.xy));
    let mirrorGain = mirrorTint * (1.0 - 0.20 * effectMix * mirrorSeam);
    outRGB = outRGB * mirrorGain;

    // Radial pulse with SDF star primitive blended in via smooth-min.
    let pulse = rdPulse(centered, time, pulseSpeed, pulseWidth);
    let starD = sdfStar(centered, segments, 0.35 + 0.1 * sin(time), 0.45);
    let starMask = 1.0 - smoothstep(0.0, 0.08, starD);
    let starGlow = exp(-max(starD, 0.0) * 8.0) * (0.5 + 0.5 * sin(time * 3.0));
    let combinedPulse = smin(pulse * 2.0, starGlow * 0.6, 0.25);
    let orbit = attractorOrbit(centered, time);
    let pulseColor = combinedPulse * mix(vec3<f32>(0.5, 0.85, 1.0), vec3<f32>(1.0, 0.6, 0.9), orbit);

    outRGB = mix(outRGB, outRGB + pulseColor, effectMix);
    outRGB = acesToneMap(outRGB * (1.0 + combinedPulse * 0.35));

    // Chromatic split along the kaleidoscope radius.
    let radial = normalize(centered + vec2<f32>(0.0001));
    let caAmt = 0.008 * effectMix * (1.0 + pulse);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + radial * caAmt, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - radial * caAmt, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    outRGB = mix(outRGB, vec3<f32>(r * mirrorGain.r, outRGB.g, b * mirrorGain.b), 0.35 * effectMix);

    let luma = dot(outRGB, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = mix(src.a, clamp(luma * 0.7 + combinedPulse * 0.45 + depth * 0.15, 0.0, 1.0), effectMix);
    let dither = (ign(vec2<f32>(coord)) - 0.5) / 255.0;
    outRGB = outRGB + vec3<f32>(dither);

    textureStore(writeTexture, coord, vec4<f32>(outRGB, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
