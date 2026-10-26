// ═══════════════════════════════════════════════════════════════════
//  Emergent Script Gardens
//  Category: generative
//  Features: upgraded-rgba, temporal, audio-reactive, mouse-driven,
//            golden-ratio-branching, phyllotaxis, overgrowth-trails
//  Complexity: Medium-High
//  Upgraded: 2026-10-10, 2026-10-25
//  Ideas: Fibonacci parastichy veins on the opposing spiral family; ligature bridges to +X neighbor; serif terminals; ink bleed; dry-brush bristle gaps along the stroke tangent (kasure); capillary meniscus fillet from exact-C.a curvature (§12.2D surface tension)
//  A packing: pre-ACES color RGB + totalInk in A.a; ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const GOLDEN: f32 = 1.6180339887;
const PHYLLOTAXIS: f32 = 2.3999632297; // 137.5° in radians = 360° / φ²

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn smoothNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), w.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), w.x),
        w.y
    );
}

fn ruleAngle(p: vec2<f32>, t: f32, bass: f32, mids: f32, treble: f32, curvature: f32) -> f32 {
    let slow = smoothNoise(p * 2.0 + vec2<f32>(t * 0.06, -t * 0.04));
    let local = smoothNoise(p * (4.0 + mids * 3.0) + vec2<f32>(-t * 0.11, t * 0.09));
    let script = smoothNoise(p * 9.0 + vec2<f32>(t * 0.21, t * 0.17));
    return (slow - 0.5) * TAU + (local - 0.5) * PI * curvature + (script - 0.5) * treble * PI + bass * 0.4;
}

fn brushStroke(uv: vec2<f32>, seed: vec2<f32>, lengthScale: f32, inkWidth: f32, angle: f32, bend: f32, dry: f32) -> f32 {
    let d = uv - seed;
    let ca = cos(angle);
    let sa = sin(angle);
    let along = d.x * ca + d.y * sa;
    let across = -d.x * sa + d.y * ca;
    // Exact support box: body is zero outside [0, len+0.02] and the width is zero once
    // |across| >= inkWidth + the 1.6*inkWidth wobble. Same output, skips pow/sin per miss.
    if (along <= 0.0 || along >= lengthScale + 0.02 || abs(across) >= inkWidth * 2.6) { return 0.0; }
    let curvedAcross = across + sin(along * 22.0 + bend) * inkWidth * 1.6;
    let body = smoothstep(0.0, 0.018, along) * smoothstep(lengthScale + 0.02, lengthScale, along);
    let tn = clamp(along / max(lengthScale, 0.001), 0.0, 1.0);
    let taper = pow(sin(tn * PI), 0.65);
    var width = smoothstep(inkWidth, 0.0, abs(curvedAcross)) * taper;
    // ── Idea 1: dry-brush bristle gaps (kasure) ──────────────────────────
    // A loaded brush runs dry toward the tail: hairs part and paper shows through in
    // streaks that run along the stroke tangent (noise is fast across, slow along).
    let bristle = smoothNoise(vec2<f32>(curvedAcross / max(inkWidth, 1e-4) * 1.9 + seed.x * 61.0,
                                        along * 35.0 + seed.y * 47.0));
    let gap = smoothstep(0.3, 0.62, bristle);
    width = width * mix(1.0, gap, dry * smoothstep(0.4, 1.0, tn));
    return body * width;
}

fn glyphGarden(uv: vec2<f32>, cluster: vec2<f32>, t: f32, bass: f32, mids: f32, treble: f32,
               strokeDensity: f32, curvature: f32, inkWidth: f32, dry: f32) -> f32 {
    var ink = 0.0;
    // Bass drives number of growth iterations (phyllotactic spiral density)
    let count = i32(clamp(4.0 + strokeDensity * 8.0 + bass * 6.0, 4.0, 20.0));
    let clusterHash = hash22(cluster * 13.7 + 0.4);
    let bloom = smoothstep(0.0, 0.45, fract(t * 0.06 + clusterHash.x));

    for (var i: i32 = 0; i < count; i++) {
        let fi = f32(i);
        // Phyllotaxis spiral: r = sqrt(n) * scale, theta = n * 137.5°
        let goldenR = sqrt(fi + 1.0) * 0.032 * (1.0 + mids * 0.3);
        let goldenTheta = fi * PHYLLOTAXIS + clusterHash.x * TAU;
        let orbit = vec2<f32>(cos(goldenTheta), sin(goldenTheta)) * goldenR;
        let h = hash22(cluster + vec2<f32>(fi * 0.71, fi * 1.37));
        let seed = cluster + orbit;
        // Branching angle enriched by golden-ratio harmonic
        let angle = ruleAngle(seed, t + fi * 0.3, bass, mids, treble, curvature)
                    + (h.x - 0.5) * PI * 0.7 + fi * (PHYLLOTAXIS * 0.05);
        let len = (0.028 + h.y * 0.07 + bass * 0.025) * bloom;
        let bend = t * (0.5 + mids) + fi + h.x * TAU;
        ink += brushStroke(uv, seed, len, inkWidth * (0.65 + h.x * 0.8), angle, bend, dry);
        // Idea: serif terminal — a short crossbar at the end of the primary stroke.
        let tip = seed + vec2<f32>(cos(angle), sin(angle)) * len;
        ink += brushStroke(uv, tip, len * 0.22, inkWidth * 0.85, angle + PI * 0.5, 0.0, 0.0) * 0.75;

        // Idea 1 — Fibonacci parastichy veins: opposing spiral family (τ − 137.5°)
        let oppositeTheta = fi * (TAU - PHYLLOTAXIS) + clusterHash.y * TAU;
        let orbit2 = vec2<f32>(cos(oppositeTheta), sin(oppositeTheta)) * goldenR * 0.92;
        ink += brushStroke(uv, cluster + orbit2, len * 0.45, inkWidth * 0.38,
                           oppositeTheta + PI * 0.5, bend, 0.0) * 0.55;
    }

    return clamp(ink, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / res.y;
    let p = vec2<f32>(uv.x * aspect, uv.y);
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let strokeDensity = u.zoom_params.x;
    let curvature = mix(0.2, 1.8, u.zoom_params.y) * (1.0 + mids * 0.35);
    let gardenScale = mix(4.0, 11.0, u.zoom_params.z);
    let palette = u.zoom_params.w;
    let inkWidth = mix(0.0035, 0.014, strokeDensity) * (1.0 + mids * 0.25);
    // Paper ink runs drier than neon tubing (Ink / Neon keeps its role as the look selector).
    let dryBrush = mix(0.9, 0.45, palette);

    let mouse = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);
    let mouseDown = step(0.5, u.zoom_config.w);
    let mouseDist = length(p - mouse);
    var clickSeed = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 4.5) {
            let rp = vec2<f32>(ripple.x * aspect, ripple.y);
            let front = abs(length(p - rp) - age * 0.09 * GOLDEN);
            clickSeed += (1.0 - smoothstep(0.0, 0.016, front)) * (1.0 - age / 4.5);
        }
    }
    clickSeed = min(clickSeed, 2.0);
    // Mouse click plants new seed with golden-ratio intensity boost
    let plantedSeed = exp(-mouseDist * mouseDist * 70.0)
                      * (0.35 + bass * 0.65)
                      * select(0.35, 1.0 + GOLDEN * 0.2, mouseDown > 0.5)
                      + clickSeed * 0.45;

    let grid = p * gardenScale;
    let cell = floor(grid);
    var totalInk = 0.0;
    var chroma = vec3<f32>(0.0);

    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            let neighbor = cell + vec2<f32>(f32(x), f32(y));
            let jitter = (hash22(neighbor + 2.17) - 0.5) * 0.35;
            let cluster = (neighbor + 0.5 + jitter) / gardenScale;
            let mouseBoost = exp(-length(cluster - mouse) * length(cluster - mouse) * 24.0) * 0.55;
            let ink = glyphGarden(p, cluster, time, bass, mids, treble,
                                  clamp(strokeDensity + mouseBoost, 0.0, 1.0), curvature, inkWidth, dryBrush);
            // Idea 2 — ligature bridges: a short brush toward the +X neighbor
            let nextCluster = (neighbor + vec2<f32>(1.0, 0.0) + 0.5 + jitter) / gardenScale;
            let ligDelta = nextCluster - cluster;
            let ligLen = length(ligDelta);
            let ligAngle = atan2(ligDelta.y, ligDelta.x);
            let ligature = brushStroke(p, cluster, ligLen * 0.55, inkWidth * 0.32, ligAngle, 0.0, dryBrush * 0.6) * 0.42;
            let inkAll = ink + ligature;
            if (inkAll > 0.0) {
                let h = hash22(neighbor * 0.23 + 0.5);
                let hue = h.x + time * 0.018 + bass * 0.1;
                let clusterColor = vec3<f32>(
                    0.5 + 0.5 * cos(hue * TAU),
                    0.5 + 0.5 * cos(hue * TAU + 2.094),
                    0.5 + 0.5 * cos(hue * TAU + 4.189)
                );
                chroma += clusterColor * inkAll;
                totalInk += inkAll;
            }
        }
    }

    let prev = textureLoad(dataTextureC, coord, 0);
    // ── Idea 2: capillary meniscus (§12.2D surface tension) ──────────────
    // Wet ink pulls into a fillet where strokes meet. κ = div(∇a/|∇a|) of last frame's
    // ink field (exact C.a taps, spacing ≈ stroke half-width); concave interface (κ<0)
    // is filled. Self-limiting: a filled crotch is no longer concave next frame.
    let hpx = i32(clamp(round(inkWidth * res.y * 0.8), 1.0, 6.0));
    let cmax = vec2<i32>(i32(res.x) - 1, i32(res.y) - 1);
    let a0 = prev.a;
    let aE = textureLoad(dataTextureC, clamp(coord + vec2<i32>(hpx, 0), vec2<i32>(0), cmax), 0).a;
    let aW = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-hpx, 0), vec2<i32>(0), cmax), 0).a;
    let aN = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -hpx), vec2<i32>(0), cmax), 0).a;
    let aS = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, hpx), vec2<i32>(0), cmax), 0).a;
    let aNE = textureLoad(dataTextureC, clamp(coord + vec2<i32>(hpx, -hpx), vec2<i32>(0), cmax), 0).a;
    let aNW = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-hpx, -hpx), vec2<i32>(0), cmax), 0).a;
    let aSE = textureLoad(dataTextureC, clamp(coord + vec2<i32>(hpx, hpx), vec2<i32>(0), cmax), 0).a;
    let aSW = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-hpx, hpx), vec2<i32>(0), cmax), 0).a;
    let gx = (aE - aW) * 0.5;
    let gy = (aS - aN) * 0.5;
    let gxx = aE + aW - 2.0 * a0;
    let gyy = aS + aN - 2.0 * a0;
    let gxy = (aSE - aNE - aSW + aNW) * 0.25;
    let g2 = gx * gx + gy * gy;
    let kappaIn = (gxx * gy * gy - 2.0 * gx * gy * gxy + gyy * gx * gx) / max(g2 * sqrt(g2), 1e-4);
    let iface = smoothstep(0.03, 0.2, sqrt(g2));
    let fillet = clamp(kappaIn * f32(hpx) * 0.6, 0.0, 1.0) * iface;
    let meniscus = fillet * 0.12 * mix(1.0, 0.5, palette);
    // Temporal feedback creates "overgrowth" trails
    let persistence = mix(0.76, 0.93, palette) + bass * 0.04;
    totalInk = clamp(max(totalInk + plantedSeed + meniscus, prev.a * persistence), 0.0, 1.0);

    let normalizedChroma = chroma / max(dot(chroma, vec3<f32>(0.3333)), 0.001);
    let paper = vec3<f32>(0.94, 0.91, 0.84) + hash12(p * 260.0) * 0.025;
    let night = vec3<f32>(0.012, 0.014, 0.035);
    let background = mix(paper, night, palette);
    let inkColor = mix(vec3<f32>(0.055, 0.045, 0.065), normalizedChroma * 0.75 + vec3<f32>(0.16, 0.09, 0.22), palette);
    var color = mix(background, inkColor, smoothstep(0.02, 0.72, totalInk));
    color += normalizedChroma * totalInk * palette * (0.35 + treble * 0.55);
    color += vec3<f32>(0.7, 0.55, 1.0) * plantedSeed * palette;
    // Idea: ink bleed — a feather wider than the stroke, into the paper or the neon.
    let bleed = smoothstep(0.0, 0.16, totalInk) * (1.0 - smoothstep(0.16, 0.5, totalInk));
    color = mix(color, vec3<f32>(0.42, 0.3, 0.16), bleed * 0.4 * (1.0 - palette));
    color += normalizedChroma * bleed * palette * 0.28;

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass);
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

    // ACES tone mapping + semantic alpha
    let finalColor = acesToneMap(color * 1.1);
    let alpha = clamp(totalInk * 0.82 + plantedSeed * 0.22, 0.04, 0.96);

    textureStore(dataTextureA, gid.xy, vec4<f32>(color, totalInk));
    textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(totalInk, 0.0, 0.0, 0.0));
}
