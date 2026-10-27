// ═══════════════════════════════════════════════════════════════════
//  Torus Knot Rainbow — Algorithmist Upgrade
//  Category: generative
//  Features: audio-reactive, temporal-feedback, analytic-sdf-tube,
//            smooth-union-capsules, multi-orbit-julia-trap,
//            fbm-domain-warp, psychedelic-halo, depth-output, aces-tone-map
//  Complexity: High
//  Created: 2026-05-23
//  Upgraded: 2026-10-19
//  Ideas: Kelvin wave packets along the knot; braid-crossing flare bursts; magnetic flux tube core; plasma pinch instabilities;
//         over/under crossing breaks (knot-diagram occlusion from the projected strand depth);
//         Cauchy-dispersed flux core (§12.2F: n(λ)=A+B/λ² splits the core light into R/G/B bands across the tube)
//  A packing: ACES display RGBA in A (trails blended in display space; alpha = 0.85 field + knot coverage)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const SEGMENTS: i32 = 128;
const JULIA_ITERS: i32 = 32;

// ── Hash & noise ──────────────────────────────────────────────────
fn hashf(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

fn domainWarp(p: vec2<f32>, strength: f32, octaves: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, octaves), fbm(p + vec2<f32>(5.2, 1.3), octaves));
    return p + strength * q;
}

// ── Color utilities ───────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let c = hsv.z * hsv.y;
    let h = hsv.x * 6.0;
    let x = c * (1.0 - abs(fract(h / 2.0) * 2.0 - 1.0));
    let m = hsv.z - c;
    var rgb: vec3<f32>;
    if (h < 1.0)       { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0)  { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0)  { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0)  { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0)  { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(m);
}

fn psychedelicPalette(t: f32) -> vec3<f32> {
    let hue = fract(t);
    let saturation = clamp(0.72 + 0.28 * sin(TAU * (t * 0.137 + 0.19)), 0.45, 1.0);
    let value = 1.0 + 0.18 * sin(TAU * (t * 0.071 + 0.43));
    let rgb = clamp(abs(fract(vec3<f32>(hue) + vec3<f32>(0.0, 0.6666667, 0.3333333)) * 6.0 - vec3<f32>(3.0)) - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
    let smoothRgb = rgb * rgb * (vec3<f32>(3.0) - 2.0 * rgb);
    return mix(vec3<f32>(value), smoothRgb * value, saturation);
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ── Geometry helpers ──────────────────────────────────────────────
fn rot2(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// x = distance to the segment, y = parameter h of the closest point (for depth interpolation)
fn sdSegmentH(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-8), 0.0, 1.0);
    return vec2<f32>(length(pa - ba * h), h);
}

// Cauchy index n(λ) = A + B/λ² (λ in µm), crown-glass-like coefficients.
fn cauchyN(lambdaUm: f32) -> f32 {
    return 1.5 + 0.0042 / (lambdaUm * lambdaUm);
}

fn torusKnotPoint(t: f32, pWind: f32, qWind: f32, R: f32, r: f32) -> vec3<f32> {
    let phi = t * pWind;
    let theta = t * qWind;
    let x = (R + r * cos(theta)) * cos(phi);
    let y = (R + r * cos(theta)) * sin(phi);
    let z = r * sin(theta);
    return vec3<f32>(x, y, z);
}

// rotY(rotX(v, ax), ay) with the angles' cos/sin hoisted out of the segment loop
fn tumble3(v: vec3<f32>, cs: vec4<f32>) -> vec3<f32> {
    let w = vec3<f32>(v.x, cs.x * v.y - cs.y * v.z, cs.y * v.y + cs.x * v.z);
    return vec3<f32>(cs.z * w.x + cs.w * w.z, w.y, -cs.w * w.x + cs.z * w.z);
}

// Focal length tracks the camera distance (dolly-zoom), normalised to the
// cam = 4 framing: pointer-y changes the perspective strength, not the size.
fn project(pt: vec3<f32>, camDist: f32) -> vec2<f32> {
    let w = 1.0 / (camDist - pt.z);
    return pt.xy * w * (camDist * 0.25);
}

// ── Fractal: multi-orbit Julia trap ───────────────────────────────
fn juliaOrbitTrap(z0: vec2<f32>, c: vec2<f32>) -> f32 {
    var z = z0;
    var acc = 0.0;
    for (var i: i32 = 0; i < JULIA_ITERS; i = i + 1) {
        let x = z.x * z.x - z.y * z.y + c.x;
        let y = 2.0 * z.x * z.y + c.y;
        z = vec2<f32>(x, y);

        let d1 = length(z - vec2<f32>(0.3, 0.0));
        let d2 = length(z - vec2<f32>(-0.5, 0.2));
        let d3 = length(z - vec2<f32>(0.0, 0.55));
        let minTrap = min(min(d1, d2), d3);

        acc += exp(-minTrap * 5.0);
        if (dot(z, z) > 16.0) { break; }
    }
    return acc / f32(JULIA_ITERS);
}

// ═══════════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let p1 = u.zoom_params.x;
    let p2 = u.zoom_params.y;
    let p3 = u.zoom_params.z;
    let p4 = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depthIn = textureLoad(readDepthTexture, pixel, 0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    // ── Parameter mapping ──────────────────────────────────────────
    let spinSpeed = mix(0.05, 1.8, p1);
    let pWind = floor(mix(2.0, 7.0, p2));
    let qWind = floor(mix(3.0, 8.0, p3));
    let baseRad = mix(0.045, 0.012, p4);
    // Blend radius kept below the strand spacing: HEAD's 0.035–0.12 summed over
    // 128 overlapping capsules drove dMin negative across the whole knot disc.
    let smoothK = mix(0.03, 0.008, p4);

    // ── Screen-space setup ─────────────────────────────────────────
    // HEAD scaled uv (already aspect-correct) by aspect again and by 2.8, so the
    // projected knot (radius ~0.25) covered ~18% of the frame and was squashed on
    // wide canvases. Frame the knot at ~75% of the short side; the Julia trap
    // keeps its original coordinate scale.
    let rot = time * spinSpeed * 0.25 + mouse.x * TAU;
    let p2d = rot2(rot) * (uv * 0.68);
    let pJulia = rot2(rot) * (uv * 2.8);

    // Audio-driven wind modulation preserves the original soul
    let qAudio = qWind + bass * 1.2;
    let R = 0.72;
    let r = 0.30;
    // HEAD's range 3..5; with the dolly-zoom projection the knot stays inside
    // the frame over the full pointer range (a plain zoom overflowed at y≈0.2).
    let cam = 4.0 + (mouse.y - 0.5) * 2.0;
    let tumble = time * spinSpeed * 0.08;

    // Organic domain warp for tube modulation and background
    let warp = domainWarp(uv * 3.0 + vec2<f32>(time * 0.07, -time * 0.05), 0.35, 3);

    // ── Analytic torus-knot SDF (smooth union of capsules) ─────────
    var dMin = 1e5;
    var halo = 0.0;
    var bestT = 0.0;
    var bestD = 1e5;
    var crossing = 0.0;
    // Idea 5: front-most strand covering this pixel, and front-most strand within
    // the break width (projected depth: larger z = nearer the camera).
    var frontZ = -1e5;
    var frontS = -1e5;
    var frontT = 0.0;
    var frontD = 1e5;
    var frontR = baseRad;
    var nearZ = -1e5;
    let gapW = baseRad * 0.4 + 0.004;
    let invN = 1.0 / f32(SEGMENTS);

    // Each vertex is shared by two capsules: carry it across iterations instead
    // of evaluating (and tumbling) every knot point twice.
    let tcs = vec4<f32>(cos(tumble * 0.7), sin(tumble * 0.7), cos(tumble), sin(tumble));
    var ra = tumble3(torusKnotPoint(0.0, pWind, qAudio, R, r), tcs);
    var pa = project(ra, cam);
    for (var i: i32 = 0; i < SEGMENTS; i = i + 1) {
        let t0 = f32(i) * invN * TAU;
        let t1 = f32(i + 1) * invN * TAU;

        let b = torusKnotPoint(t1, pWind, qAudio, R, r);

        // Gentle 3D tumble for parallax
        let rb = tumble3(b, tcs);
        let pb = project(rb, cam);

        let dh = sdSegmentH(p2d, pa, pb);
        let dseg = dh.x;
        let zSeg = mix(ra.z, rb.z, dh.y);

        // Harmonic tube-radius modulation
        // Idea 2: plasma pinch instabilities
        // (evaluated at the closest point, so the radius is continuous along the
        // strand instead of stepping per capsule into a string of beads)
        let tC = mix(t0, t1, dh.y);
        let pinch = 0.5 + 0.5 * cos(tC * 15.0 - time * 2.0);
        let rad = baseRad * (1.0 + 0.22 * sin(tC * 5.0 - time * 0.4) + 0.12 * bass) * (0.8 + 0.4 * pinch);

        // Smooth-min union creates a continuous analytic tube
        dMin = smin(dMin, dseg - rad, smoothK);

        // ── Idea 5: over/under crossing breaks ──
        // The strand nearest the camera owns the pixel; any deeper strand that
        // passes within gapW of a nearer one is cut, as in a knot diagram.
        // Rank by depth minus a small in-strand distance penalty, so along one
        // strand the closest capsule wins (no end-cap rings) while strands at a
        // crossing (depth gap > 0.09) still order by depth.
        let score = zSeg - 0.09 * dseg / rad;
        let covers = dseg < rad && score > frontS;
        frontS = select(frontS, score, covers);
        frontZ = select(frontZ, zSeg, covers);
        frontT = select(frontT, f32(i) * invN, covers);
        frontD = select(frontD, dseg, covers);
        frontR = select(frontR, rad, covers);
        nearZ = select(nearZ, max(nearZ, zSeg), dseg < rad + gapW);

        // Layered halo for glow and depth
        // Tighter than HEAD's 1/12 falloff: the halo hue is keyed to the nearest
        // strand, and a wide halo carried that key's flat wedges across the void.
        halo += exp(-dseg * (38.0 + treble * 16.0)) * (1.0 + mids * 0.5);
        crossing += exp(-dseg * 38.0);

        // Branchless closest-segment tracking for color mapping
        let closer = dseg < bestD;
        bestD = select(bestD, dseg, closer);
        bestT = select(bestT, f32(i) * invN, closer);
        ra = rb;
        pa = pb;
    }

    // ── Fractal orbit trap in the halo field ───────────────────────
    let jCoord = pJulia * (2.0 + bass) + warp * 0.5;
    let jc = vec2<f32>(cos(time * 0.13) * 0.55, sin(time * 0.17) * 0.38) + (mouse - 0.5) * 0.4;
    let jTrap = juliaOrbitTrap(jCoord, jc);

    // ── Knot color (rainbow along arc + fractal iridescence) ───────
    let covered = frontZ > -1e4;
    // Over-strand owns the colour at a crossing (HEAD: nearest centreline, which
    // flips between strands along the diagonal of every crossing).
    let ownT = select(bestT, frontT, covered);
    let ownD = select(bestD, frontD, covered);
    let hue = fract(ownT + time * spinSpeed * 0.08 + treble * 0.12 + jTrap * 0.15);
    let sat = clamp(0.78 + mids * 0.2 + jTrap * 0.25, 0.0, 1.0);
    var knotCol = hsv2rgb(vec3<f32>(hue, sat, 1.0));
    // Idea 1: Kelvin wave packets propagating along the knot arc.
    let kelvin = pow(0.5 + 0.5 * sin(ownT * TAU * 11.0 - time * (4.0 + bass * 3.2)), 4.0);
    knotCol += vec3<f32>(0.35, 0.95, 1.0) * kelvin * (0.2 + mids * 0.25);

    let haloCol = psychedelicPalette(ownT * 3.0 + time * 0.06 + jTrap);
    // HEAD's 1/8-unit falloff spread the knot colour over the whole knot disc.
    let field = exp(-max(dMin, 0.0) * (110.0 + treble * 40.0));
    // (capped lower than HEAD's 0.55 so the tube keeps its saturated arc hue)
    knotCol = mix(knotCol, haloCol, clamp(jTrap * 1.5, 0.0, 0.3));

    // Idea 5: depth shading, so the over-strand reads as nearer at each crossing.
    let zN = clamp(frontZ / (R + r) * 0.5 + 0.5, 0.0, 1.0);
    knotCol *= select(1.0, mix(0.55, 1.15, zN), covered);

    // Idea 1: Magnetic flux tube core
    // ── Idea 6: Cauchy-dispersed flux core ──
    // The tube is a glass sheath around the core light: each wavelength leaves
    // it at an offset set by n(λ) − n(550 nm), so the white core opens into
    // red→green→blue bands across the tube, non-linearly spaced (blue widest).
    let nG = cauchyN(0.55);
    let dispSpan = frontR * (0.5 + bass * 0.25) / (cauchyN(0.45) - nG);
    let bandOff = vec3<f32>(cauchyN(0.65) - nG, 0.0, cauchyN(0.45) - nG) * dispSpan + vec3<f32>(frontR * 0.35);
    let coreK = 11.0 / max(frontR, 1e-3);
    let fluxCore = exp(-abs(vec3<f32>(ownD) - bandOff) * coreK) * (0.5 + bass) * 0.9;
    knotCol += fluxCore;

    // ── Domain-warped background ───────────────────────────────────
    let bgP = domainWarp(uv * 2.5 + vec2<f32>(time * 0.04, time * 0.03), 0.5, 4);
    let bgNoise = fbm(bgP + warp * 0.3, 4);
    let bgCol = psychedelicPalette(bgNoise + time * 0.03 + bass * 0.1);
    let bgMask = smoothstep(0.25, 0.8, field);

    // Idea 5: the cut under-strand shows the background through the break.
    let gap = select(0.0, smoothstep(0.03, 0.12, nearZ - frontZ), covered);
    let knotCover = field * (1.0 - gap);
    var col = mix(bgCol * 0.25, knotCol, knotCover);
    col = col + bgCol * 0.05 * (1.0 - bgMask);
    col = col + haloCol * halo * 0.03 * (1.0 - gap);
    // Idea 2: braid-crossing flare bursts from local segment crowding.
    let crossingBurst = smoothstep(3.0, 10.0, crossing);
    col += vec3<f32>(1.0, 0.82, 0.42) * crossingBurst * (0.15 + treble * 0.25);

    // ── Chromatic shift (generative, no readTexture dependency) ─────
    let angle = atan2(uv01.y - 0.5, uv01.x - 0.5);
    let caStr = 0.025 * (1.0 + bass) + depthIn * 0.01;
    col = vec3<f32>(
        col.r * (1.0 + cos(angle) * caStr),
        col.g,
        col.b * (1.0 - sin(angle) * caStr * 0.5)
    );

    // ── Tone map, then temporal feedback in display space ──────────
    // HEAD mixed the ACES'd history back into HDR and tone-mapped it again every
    // frame; iterated ACES latches each channel to 0 or its fixed point, which
    // posterised the background into flat primary blobs.
    col = acesToneMap(max(col, vec3<f32>(0.0)) * (0.95 + mids * 0.15));
    let decay = 0.96 - p4 * 0.025;
    let trailW = 0.25 + bass * 0.12;
    col = col + max(prev.rgb * decay - col, vec3<f32>(0.0)) * (1.0 - trailW);
    let alpha = clamp(0.85 + 0.15 * knotCover + bass * 0.03, 0.0, 1.0);

    // ── Depth output ───────────────────────────────────────────────
    let depth = clamp(knotCover * (0.55 + 0.4 * zN) + halo * 0.01 + depthIn * 0.1, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
}
