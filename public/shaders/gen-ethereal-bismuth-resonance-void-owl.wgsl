// ═══════════════════════════════════════════════════════════════════
//  Ethereal Bismuth-Resonance Void-Owl
//  Category: generative
//  Features: mouse-driven, audio-reactive, click-reactive, raymarched, upgraded-rgba
//  Upgraded: 2026-10-17
//  Ideas: gravitational singularity under the pointer (smooth-falloff lens
//         twist centred on it + gaze follow); bass resonance (stateless,
//         scaled by Audio Reactivity) sweeps oxide growth bands outward across
//         the bismuth shell film; stepped hopper-crystal owl eyes flanking the
//         core, pupils tracking the singularity and flaring with resonance.
//         2nd pass: hopper terraces (film thickness quantized into hard stair
//         steps with bright risers); facial-disc ruff (concave stepped nested
//         rings around the eyes, own film phase); lattice-snapped debris
//         (90-degree locked tumbling, hopper tips that grow with resonance).
//         3rd pass: hopper-stair wing mantle (folded primaries as stacked
//         recessed bismuth plates that fan open with the resonance);
//         owl head swivel (facial disc snaps toward the pointer and to idle
//         glance angles, then holds)
//  A packing: HDR display history RGB (tonemapped on output) + semantic
//             alpha (surface/luma/shock coverage); exact C read feedback
//  State: none (no extraBuffer persistence)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Crystal Complexity, y=Audio Reactivity, z=Iridescence Shift, w=Debris Density

const PI: f32 = 3.14159265359;
const MAX_DIST: f32 = 20.0;

// Per-frame values shared with sdf() (set once in main before marching)
var<private> gMouse: vec2<f32> = vec2<f32>(0.5, 0.5);
var<private> gResonance: f32 = 0.0;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// 3D hash
fn hash31(p: vec3<f32>) -> f32 {
    let q = fract(p * vec3<f32>(17.173, 29.771, 33.319));
    return fract(dot(q, q.yzx + 19.19));
}

// Simple 3D noise
fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let v0 = mix(hash31(i + vec3<f32>(0.0,0.0,0.0)), hash31(i + vec3<f32>(1.0,0.0,0.0)), w.x);
    let v1 = mix(hash31(i + vec3<f32>(0.0,1.0,0.0)), hash31(i + vec3<f32>(1.0,1.0,0.0)), w.x);
    let v2 = mix(hash31(i + vec3<f32>(0.0,0.0,1.0)), hash31(i + vec3<f32>(1.0,0.0,1.0)), w.x);
    let v3 = mix(hash31(i + vec3<f32>(0.0,1.0,1.0)), hash31(i + vec3<f32>(1.0,1.0,1.0)), w.x);
    return mix(mix(v0, v1, w.y), mix(v2, v3, w.y), w.z);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn box(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// Thin-film interference: iridescent bismuth oxide layer.
// dot_nv = cos of view angle, film = relative film thickness, shift = slider hue offset.
fn thinFilm(dot_nv: f32, film: f32, shift: f32) -> vec3<f32> {
    let optical = (1.0 - dot_nv) * 3.0 + film * 4.0 + shift * 6.0;
    let r = 0.5 + 0.5 * cos(optical * 2.0 + 0.0);
    let g = 0.5 + 0.5 * cos(optical * 2.3 + 2.094);
    let b = 0.5 + 0.5 * cos(optical * 2.7 + 4.188);
    // Bias toward the classic bismuth stair-step palette (magenta/cyan/gold)
    return mix(vec3<f32>(r, g, b), vec3<f32>(1.0, 0.25, 0.85), 0.25) * vec3<f32>(0.85, 1.0, 1.25);
}

// Idea 1 lens twist, shared by sdf() and the surface-pattern lookups so
// eye/ruff patterns stay registered on the twisted geometry.
fn lensP(p_in: vec3<f32>) -> vec3<f32> {
    var p = p_in;
    let sing = vec2<f32>(gMouse.x * 2.0 - 1.0, 1.0 - gMouse.y * 2.0) * 5.0;
    let toSing = p.xy - sing;
    let mouseDist = length(toSing);
    if (mouseDist < 3.0) {
        let fall = 1.0 - mouseDist / 3.0;
        let twistAmount = fall * fall * (0.5 + gResonance * 0.4);
        p = vec3<f32>(sing + rot(twistAmount) * toSing, p.z);
    }
    return p;
}

// Idea: owl head swivel. The facial disc (eyes, pupils, ruff) turns about the
// vertical axis in quick snaps and long holds: it follows the pointer in
// coarse steps and, between moves, glances to a new random angle every ~6 s.
fn hash11(x: f32) -> f32 { return fract(sin(x * 127.1) * 43758.5453); }
fn headP(p: vec3<f32>) -> vec3<f32> {
    let time = u.config.x;
    let st = 0.32;
    let mx = clamp(gMouse.x - 0.5, -0.5, 0.5) * 2.4 / st;
    let follow = (floor(mx) + smoothstep(0.7, 1.0, fract(mx))) * st;
    let gph = time * 0.17;
    let k = floor(gph);
    let glance = mix(hash11(k) - 0.5, hash11(k + 1.0) - 0.5, smoothstep(0.88, 1.0, fract(gph))) * 1.1;
    let a = follow + glance;
    return vec3<f32>(rot(a) * p.xz, p.y).xzy;
}

fn sdf(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;
    let time = u.config.x;

    let audioBass = plasmaBuffer[0].x;
    let complexity = u.zoom_params.x;          // Crystal Complexity (fold iterations)
    let audioReactivityScale = u.zoom_params.y; // Audio Reactivity Scale

    // Idea 1: gravitational singularity under the pointer (mouse y=0 is the
    // top, world +y is up, so y is flipped). The lens twist now rotates about
    // the singularity itself with a smooth quadratic falloff (HEAD twisted
    // about the world origin by up to 1.5 rad).
    p = lensP(p);

    var d = 1000.0;
    var matId = 0.0;

    let debrisDensity = u.zoom_params.w; // Orbital Debris Density

    // Orbital debris (floating monoliths) in modular space
    var p_debris = p;
    let r = length(p.xz);
    p_debris = vec3<f32>(rot(time * 0.2 + r * 0.1) * p_debris.xz, p_debris.y).xzy;
    let spacing = mix(6.0, 2.0, debrisDensity);
    let id_debris = floor(p_debris / spacing);
    p_debris = p_debris - (id_debris + 0.5) * spacing;

    let hashDebris = hash31(id_debris);
    if (hashDebris > 0.8 - debrisDensity * 0.3) {
        // Idea: lattice-snapped debris. Each monolith tumbles in 90-degree
        // steps of the bismuth lattice (quick turn, long hold), and grows
        // stepped hopper tips on both ends with the resonance.
        let ph = time * 0.25 + hashDebris * 7.0;
        let snapA = (floor(ph) + smoothstep(0.8, 1.0, fract(ph))) * (PI * 0.5);
        let ph2 = time * 0.17 + hashDebris * 13.0;
        let snapB = (floor(ph2) + smoothstep(0.85, 1.0, fract(ph2))) * (PI * 0.5);
        var q = p_debris;
        q = vec3<f32>(rot(snapA) * q.xy, q.z);
        q = vec3<f32>(q.x, rot(snapB) * q.yz);
        var debris_d = box(q, vec3<f32>(0.2, 0.8, 0.2));
        // tips top out at 1.0 so they stay inside the densest (2.0) cell
        let tipG = 0.55 + clamp(gResonance, 0.0, 1.0) * 0.45;
        let qy = vec3<f32>(q.x, abs(q.y), q.z);
        let tip1 = box(qy - vec3<f32>(0.0, 0.8 + 0.07 * tipG, 0.0), vec3<f32>(0.15, 0.07, 0.15) * tipG);
        let tip2 = box(qy - vec3<f32>(0.0, 0.8 + 0.16 * tipG, 0.0), vec3<f32>(0.09, 0.04, 0.09) * tipG);
        debris_d = min(debris_d, min(tip1, tip2));
        if (debris_d < d) {
            d = debris_d;
            matId = 3.0; // Debris material
        }
    }

    // --- The Owl ---
    var p_owl = p;

    // Core singularity (heart/eyes)
    let heartSize = 0.3 + audioBass * 0.2 * audioReactivityScale;
    let heart = length(p_owl - vec3<f32>(0.0, 1.0, 0.0)) - heartSize;
    if (heart < d) {
        d = heart;
        matId = 2.0; // Core material
    }

    // Idea 3: stepped hopper-crystal eyes flanking the core; pupils glance
    // toward the eased singularity and swell with the resonance envelope.
    // Gaze x is mirrored with the eye so both pupils look the same way.
    let gazeRaw = clamp((gMouse - 0.5) * vec2<f32>(0.24, -0.18), vec2<f32>(-0.12), vec2<f32>(0.12));
    let p_face = headP(p_owl);
    let gaze = vec2<f32>(gazeRaw.x * select(-1.0, 1.0, p_face.x >= 0.0), gazeRaw.y);
    var p_eye = vec3<f32>(abs(p_face.x), p_face.y, p_face.z) - vec3<f32>(0.62, 1.15, 0.55);

    // Idea: facial-disc ruff. A plate behind each eye with a stepped concave
    // funnel subtracted (three nested square rings, deeper toward the eye),
    // notched around the heart so the core stays visible. matId 4 = ruff.
    let plate = box(p_eye - vec3<f32>(0.0, 0.0, -0.05), vec3<f32>(0.6, 0.6, 0.14));
    let step1 = box(p_eye - vec3<f32>(0.0, 0.0, 1.03), vec3<f32>(0.5, 0.5, 1.0));
    let step2 = box(p_eye - vec3<f32>(0.0, 0.0, 0.97), vec3<f32>(0.39, 0.39, 1.0));
    let step3 = box(p_eye - vec3<f32>(0.0, 0.0, 0.91), vec3<f32>(0.29, 0.29, 1.0));
    let funnel = min(step1, min(step2, step3));
    let heartNotch = length(p_face.xy - vec2<f32>(0.0, 1.0)) - 0.38;
    let ruff = max(max(plate, -funnel), -heartNotch);
    if (ruff < d) {
        d = ruff;
        matId = 4.0;
    }
    let socketOuter = box(p_eye, vec3<f32>(0.26, 0.26, 0.08));
    let socketStep = box(p_eye - vec3<f32>(0.0, 0.0, 0.05), vec3<f32>(0.17, 0.17, 0.08));
    let socket = max(socketOuter, -socketStep);
    if (socket < d) {
        d = socket;
        matId = 1.0;
    }
    let pupil = length(p_eye - vec3<f32>(gaze, 0.04)) - (0.09 + gResonance * 0.05);
    if (pupil < d) {
        d = pupil;
        matId = 2.0;
    }

    // Bismuth step-growth geometry: domain folding + hollow square frames
    p_owl.x = abs(p_owl.x);

    // Horn-like ear tufts: tapered stepped pyramids above the brow
    // tufts sit on the head, so they turn with the swivel
    var p_tuft = vec3<f32>(abs(p_face.x), p_face.y, p_face.z) - vec3<f32>(0.55, 2.0, 0.0);
    p_tuft = vec3<f32>(rot(-0.45) * p_tuft.xy, p_tuft.z);
    var tuftD = 1000.0;
    var tScale = 1.0;
    var p_t = p_tuft;
    for (var i = 0; i < 3; i++) {
        p_t.y -= 0.45 * tScale;
        let frame = box(p_t, vec3<f32>(0.28, 0.12, 0.10) * tScale);
        let notch = box(p_t - vec3<f32>(0.0, 0.10 * tScale, 0.0), vec3<f32>(0.18, 0.08, 0.14) * tScale);
        tuftD = min(tuftD, max(frame, -notch));
        tScale *= 0.72;
    }
    let tuftMask = box(p_tuft, vec3<f32>(0.6, 1.2, 0.5)) - 0.1;
    tuftD = max(tuftD, tuftMask);
    if (tuftD < d) {
        d = tuftD;
        matId = 1.0; // Tufts share the bismuth shell material
    }

    // Idea: hopper-stair wing mantle. Five folded primaries hang from each
    // shoulder as stacked plates, each a recessed hopper frame, stepping
    // outward/back like bismuth stairs; the resonance mantles them open.
    let wingBound = box(p_owl - vec3<f32>(1.9, -0.35, -0.35), vec3<f32>(1.3, 1.9, 0.85));
    if (wingBound < d) {
        let shoulder = vec3<f32>(1.3, 0.95, -0.1);
        let spread = 0.16 + clamp(gResonance, 0.0, 1.5) * 0.16;
        var wingD = 1000.0;
        for (var k = 0; k < 5; k++) {
            let fk = f32(k);
            var q = p_owl - shoulder - vec3<f32>(fk * 0.06, 0.0, -fk * 0.13);
            q = vec3<f32>(rot(spread + fk * 0.09) * q.xy, q.z);
            let len = 0.55 + fk * 0.1;
            q.y += len + 0.15;
            let wdt = 0.36 - fk * 0.03;
            let plate = box(q, vec3<f32>(0.05, len, wdt));
            let recess = box(q - vec3<f32>(0.05, 0.0, 0.0), vec3<f32>(0.025, len - 0.09, wdt - 0.08));
            wingD = min(wingD, max(plate, -recess));
        }
        if (wingD < d) {
            d = wingD;
            matId = 1.0; // primaries share the bismuth film + terraces
        }
    }

    let iterations = i32(mix(2.0, 6.0, complexity));
    var scale = 1.0;
    var d_bismuth = 1000.0;
    var p_b = p_owl;

    for (var i = 0; i < iterations; i++) {
        p_b = p_b - vec3<f32>(0.5, 0.2, 0.1) * scale;
        p_b = vec3<f32>(rot(0.2) * p_b.xy, p_b.z);
        p_b = vec3<f32>(p_b.x, rot(0.1) * p_b.yz);
        p_b = abs(p_b);

        let stepBox = box(p_b, vec3<f32>(0.8, 0.8, 0.1) * scale);
        let hole = box(p_b, vec3<f32>(0.6, 0.6, 0.2) * scale);
        let part = max(stepBox, -hole);

        d_bismuth = smin(d_bismuth, part, 0.1 * scale);
        scale *= 0.7;
    }

    // Audio-reactive quantum feather ripple across the folded lattice
    let featherDistortion = sin(p_b.y * 10.0 - time * 2.0) * cos(p_b.x * 10.0 + time) * 0.1 * audioBass * audioReactivityScale;
    d_bismuth += featherDistortion;

    let owlMask = box(p_owl, vec3<f32>(2.0, 2.5, 1.5)) - 0.5;
    d_bismuth = max(d_bismuth, owlMask);

    if (d_bismuth < d) {
        d = d_bismuth;
        matId = 1.0; // Bismuth material
    }

    return vec2<f32>(d * 0.6, matId);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let h = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        sdf(p + h.xyy).x - sdf(p - h.xyy).x,
        sdf(p + h.yxy).x - sdf(p - h.yxy).x,
        sdf(p + h.yyx).x - sdf(p - h.yyx).x
    ));
}

// Soft shadow toward the key light (8-step march, penumbra factor k)
fn softShadow(ro: vec3<f32>, rd: vec3<f32>, k: f32) -> f32 {
    var res = 1.0;
    var t = 0.05;
    for (var i = 0; i < 8; i++) {
        let h = sdf(ro + rd * t).x;
        res = min(res, k * h / t);
        t += clamp(h, 0.05, 0.6);
        if (res < 0.02 || t > 8.0) { break; }
    }
    return clamp(res, 0.0, 1.0);
}

// Cheap 3-tap ambient occlusion along the normal
fn calcAO(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0;
    var sc = 1.0;
    for (var i = 1; i < 4; i++) {
        let h = 0.08 * f32(i);
        occ += (h - sdf(p + n * h).x) * sc;
        sc *= 0.7;
    }
    return clamp(1.0 - 1.6 * occ, 0.0, 1.0);
}

// Stepped-crystal (hopper) 2D inlay: recursive square-fold pattern that
// evokes bismuth stair geometry, drawn into the void ether behind the owl.
fn bismuthInlay2D(uv: vec2<f32>, folds: f32, time: f32) -> f32 {
    var q = uv * 3.0;
    var acc = 0.0;
    var sc = 1.0;
    for (var i = 0; i < 4; i++) {
        q = abs(rot(0.35 + time * 0.02) * q) - 0.75 * sc;
        // Square-ring distance: nested stepped frames, the bismuth stair motif
        let dSq = abs(max(abs(q.x), abs(q.y)) - 0.5 * sc);
        acc += (1.0 - smoothstep(0.0, 0.04 * sc, dSq)) * (0.4 + 0.6 * sc);
        q *= 1.6;
        sc *= 0.62;
    }
    return acc * folds;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let pixel = vec2<i32>(id.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let time = u.config.x;
    // Pixel-centre uv with +y up (pixel rows grow downward)
    let uvRaw = ((vec2<f32>(id.xy) + 0.5) * 2.0 - res) / min(res.x, res.y);
    let uv = vec2<f32>(uvRaw.x, -uvRaw.y);

    // Audio
    let audioBass = plasmaBuffer[0].x * 0.5 + 0.5;
    let audioMids = plasmaBuffer[0].y;
    let audioTreble = plasmaBuffer[0].z;
    let audioReactivityScale = u.zoom_params.y;

    // Idea 1+2 (stateless): HEAD kept a spring + envelope in extraBuffer
    // [133..138], which the engine re-uploads every frame, so it never ran.
    // The singularity follows the pointer directly; resonance is the bass
    // scaled by Audio Reactivity.
    gMouse = u.zoom_config.yz;
    gResonance = clamp(plasmaBuffer[0].x, 0.0, 1.5) * audioReactivityScale * 2.0;

    let spectralSpark = clamp(audioTreble * 0.75 + audioMids * 0.25, 0.0, 2.0);

    // Pointer-orbit camera; held input moves into the resonance field.
    // Pointer up raises the camera (mouse y=0 is the top of the canvas).
    let mouseOrbit = vec2<f32>(u.zoom_config.y - 0.5, 0.5 - u.zoom_config.z) * vec2<f32>(6.28318, 1.6);
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let camRadius = 8.0 - held * 1.1;
    let camPos = vec3<f32>(sin(mouseOrbit.x) * cos(mouseOrbit.y), sin(mouseOrbit.y), cos(mouseOrbit.x) * cos(mouseOrbit.y)) * camRadius;
    let lookAt = vec3<f32>(0.0, 0.0, 0.0);
    let fw = normalize(lookAt - camPos);
    // Right-handed basis: at the default view (camera on +z) right = +x and
    // up = +y, so the ear tufts point up (HEAD had ri = -x with screen y down,
    // which rendered the owl rotated 180 degrees).
    let ri = normalize(cross(fw, vec3<f32>(0.0, 1.0, 0.0)));
    let up = cross(ri, fw);
    let rd = normalize(uv.x * ri + uv.y * up + 1.5 * fw);
    let ro = camPos;

    var t = 0.0;
    var matId = 0.0;
    var d = 0.0;
    var p = ro;
    var glow = vec3<f32>(0.0);
    var hit = false;

    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        let res2 = sdf(p);
        d = res2.x;
        matId = res2.y;
        if (d < 0.005) { hit = true; break; }
        if (d < 0.5) {
            let g = 0.02 / (0.01 + d * d);
            glow += select(vec3<f32>(0.0), vec3<f32>(0.1, 0.8, 1.0) * g * 0.1, matId == 2.0);
            glow += select(vec3<f32>(0.0), vec3<f32>(1.0, 0.2, 0.8) * g * 0.02, matId == 1.0 || matId == 4.0);
            glow += select(vec3<f32>(0.0), vec3<f32>(0.9, 0.8, 0.2) * g * 0.05, matId == 3.0);
        }
        t += d;
        if (t > MAX_DIST) { break; }
    }

    var col = vec3<f32>(0.0);

    // Volumetric void-ether fog + stepped bismuth tessellation inlay
    var fogCol = vec3<f32>(0.0);
    for (var i = 1; i < 5; i++) {
        let fi = f32(i);
        let fogP = ro + rd * (t * (fi / 5.0));
        let n = noise3D(fogP * 0.2 + vec3<f32>(0.0, time * -0.5, time * 0.2));
        let fogColor = mix(vec3<f32>(0.0, 0.2, 0.5), vec3<f32>(0.8, 0.0, 0.5), n);
        fogCol += fogColor * n * 0.05 * (1.0 - (fi / 5.0));
    }
    col += fogCol;

    // 2D stepped-crystal inlay shimmering in the void (fade behind a hit)
    let inlay = bismuthInlay2D(uv, 1.0, time);
    let inlayCol = thinFilm(fract(inlay * 0.7 + uv.x * 0.2), inlay, u.zoom_params.z);
    col += inlayCol * inlay * 0.10 * (1.0 + audioTreble * audioReactivityScale) * select(1.0, 0.25, hit);

    var depth = 0.0;
    var nrm = vec3<f32>(0.0);

    if (hit) {
        let n = calcNormal(p);
        nrm = n;
        let v = -rd;
        let dot_nv = clamp(dot(n, v), 0.0, 1.0);
        let shift = u.zoom_params.z; // Iridescence Shift

        // Per-facet variation: quantize hit position into crystal cells
        let facetSeed = hash31(floor(p * 5.0) + floor(n * 2.0 + 0.5));
        // Idea 2: oxide growth bands radiate from the core; the resonance
        // envelope pushes the stair-stepped front outward and thickens it.
        let coreR = length(p - vec3<f32>(0.0, 1.0, 0.0));
        let band = floor((coreR * 3.0 - time * 0.4 - gResonance * 2.5) * 2.0) / 2.0;
        let growth = fract(band * 0.37) * (0.35 + gResonance * 0.9);
        // Idea: hopper terraces. Chebyshev distance from the owl's core is
        // cut into hard square stair steps; film thickness is quantized per
        // step, and each riser gets a bright gold edge.
        let cheb = max(max(abs(p.x), abs(p.y - 0.4) * 0.8), abs(p.z) * 1.2);
        let terrF = cheb * 5.0 - gResonance * 0.5;
        let terrStep = floor(terrF);
        let riser = 1.0 - smoothstep(0.0, 0.07, fract(terrF));
        let filmThickness = floor((0.5 + facetSeed * 1.5 + growth + terrStep * 0.22) * 4.0) / 4.0;

        // 3-point lighting rig
        let keyL = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let fillL = normalize(vec3<f32>(-1.0, -0.5, -1.0));
        let backL = normalize(vec3<f32>(0.0, 0.6, -1.0));
        let shadow = softShadow(p + n * 0.01, keyL, 8.0);
        let ao = calcAO(p, n);
        let diffKey = clamp(dot(n, keyL), 0.0, 1.0) * shadow;
        let diffFill = clamp(dot(n, fillL), 0.0, 1.0) * ao;
        let diffBack = clamp(dot(n, backL), 0.0, 1.0) * ao;

        if (matId == 1.0 || matId == 4.0) {
            // Bismuth shell: thin-film iridescence modulated per facet. The
            // ruff (matId 4) uses its own phase per nested ring.
            var filmT = filmThickness;
            if (matId == 4.0) {
                let pl = headP(lensP(p));
                let pe = vec2<f32>(abs(pl.x) - 0.62, pl.y - 1.15);
                let ring = floor(max(abs(pe.x), abs(pe.y)) / 0.11);
                filmT = 1.7 + ring * 0.31 + gResonance * 0.2;
            }
            let film = thinFilm(dot_nv, filmT, shift);
            col += film * diffKey * 0.85;                          // key (warm sheen)
            col += film.zyx * diffFill * 0.30;                     // fill (swapped channels)
            col += vec3<f32>(1.0, 0.85, 0.4) * diffBack * 0.20;    // golden back scatter
            col += vec3<f32>(1.0, 0.8, 0.35) * riser * select(0.35, 0.0, matId == 4.0) * (0.4 + diffKey); // terrace risers
            // Facet-edge sparkle driven by FFT band
            let edge = smoothstep(0.75, 0.95, facetSeed);
            col += vec3<f32>(0.9, 1.0, 1.0) * edge * spectralSpark * audioReactivityScale * 0.6;
            // Blinn-Phong specular glints on the metallic stair facets
            let halfDir = normalize(keyL + v);
            let spec = pow(clamp(dot(n, halfDir), 0.0, 1.0), 48.0) * shadow;
            col += vec3<f32>(1.0, 0.95, 0.85) * spec * (0.6 + facetSeed * 0.6);
            // Fresnel rim
            let rim = 1.0 - dot_nv;
            col += vec3<f32>(0.5, 1.0, 1.0) * pow(rim, 4.0) * (0.5 + audioMids * 0.3);
        } else if (matId == 2.0) {
            // Core singularity: hot pulsing heart with Fresnel halo
            let pulse = 0.5 + 0.5 * sin(time * 5.0);
            col += vec3<f32>(0.0, 1.0, 1.0) * 2.0 * pulse * (0.6 + audioBass * 0.6);
            col += vec3<f32>(0.4, 0.2, 1.0) * pow(1.0 - dot_nv, 2.0);
        } else if (matId == 3.0) {
            // Debris monoliths: gold key light + orange rim, per-cell tint
            let tint = mix(vec3<f32>(1.0, 0.8, 0.2), vec3<f32>(0.6, 0.9, 1.0), facetSeed);
            col += tint * diffKey;
            col += tint * diffFill * 0.3;
            col += vec3<f32>(1.0, 0.5, 0.0) * pow(1.0 - dot_nv, 2.0);
        }


        depth = clamp(1.0 - t / MAX_DIST, 0.0, 1.0);
    }

    col += glow;

    // Click ripples: expanding iridescent shockwave rings in the void
    var shock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age > 0.0 && age < 3.0) {
            let ringR = age * 0.6;
            let rpUv = vec2<f32>(rp.x * 2.0 - 1.0, 1.0 - rp.y * 2.0) * vec2<f32>(res.x / res.y, 1.0);
            let ringD = abs(length(uv - rpUv) - ringR);
            let ringGlow = (1.0 - smoothstep(0.0, 0.08, ringD)) * (1.0 - age / 3.0);
            shock = max(shock, ringGlow);
            col += thinFilm(ringGlow, age, u.zoom_params.z) * ringGlow * 0.5;
        }
    }

    // Exact display-history feedback; A owns the same HDR history C reads.
    let prev = textureLoad(dataTextureC, pixel, 0);
    let hdr = max(mix(prev.rgb * 0.93, col, 0.28 + audioTreble * 0.03), vec3<f32>(0.0));
    col = acesToneMap(hdr * 1.25);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    // Semantic alpha from luminance + surface presence
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.75 + select(0.0, 0.35, hit) + shock * 0.2, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(hdr, alpha));
}
