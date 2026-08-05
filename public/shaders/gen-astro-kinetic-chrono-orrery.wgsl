// ═══════════════════════════════════════════════════════════════════
//  Astro Kinetic Chrono Orrery
//  Category: generative
//  Features: orbital, mechanical, cosmic, audio-orbit, mouse-gravity
//  Complexity: High
//  Updated: 2026-05-31 — Grok (audio orbit modulation + mouse gravity)
//  Upgraded: 2026-08-05 — Batch 35 (Optimizer)
//    · Kepler solves + mouse rotations hoisted out of the raymarch loop
//      (var<private> per-pixel cache: was ~6 bodies × 6 Newton iters PER STEP)
//    · analytic bounding-sphere cull skips the march on sky rays
//    · slab cull before the expensive accretion-disk density eval
//    · all 4 sliders LIVE (Complexity → body count, Glow → near-miss bloom,
//      Audio Reactivity → global audio drive), tan() removed, real hit depth,
//      temporal history via dataTextureA
// ═══════════════════════════════════════════════════════════════════
//  Physics: Keplerian orbits, blackbody radiation, accretion disk
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
    config: vec4<f32>,       // x = time, y = rippleCount, zw = resolution
    zoom_config: vec4<f32>,  // x = time, yz = mouse_uv (y=0 top), w = mouse_down
    zoom_params: vec4<f32>,  // x = Complexity, y = Speed, z = Glow Intensity, w = Audio Reactivity
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const MAX_STEPS: i32 = 96;          // bounded march budget
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 14.0;         // scene fits in |z| ≤ 10 from the camera
const BOUND_RADIUS: f32 = 4.4;      // analytic sky cull sphere
const MAX_BODIES: i32 = 10;         // hard cap for the body cache
const FOG_COLOR: vec3<f32> = vec3<f32>(0.02, 0.015, 0.04);
const GLOW_COLOR: vec3<f32> = vec3<f32>(1.0, 0.75, 0.45);

// ── Per-pixel caches (computed once in main, read by map) ─────────
var<private> g_bodies: array<vec4<f32>, MAX_BODIES>;   // xyz = position, w = radius
var<private> g_bodyProps: array<vec2<f32>, MAX_BODIES>; // x = temp (K), y = metalness
var<private> g_numBodies: i32;
var<private> g_rotXZ: mat2x2<f32>;                     // mouse orbit, hoisted
var<private> g_rotYZ: mat2x2<f32>;
var<private> g_fftTurb: f32;                           // guarded FFT drive for disk turbulence

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}
fn keplerOrbit(theta: f32, a: f32, e: f32) -> f32 {
    return a * (1.0 - e * e) / (1.0 + e * cos(theta));
}
fn meanAnomalyToEccentric(M: f32, e: f32) -> f32 {
    var E = M;
    for (var i: i32 = 0; i < 6; i++) {
        let sinE = sin(E);
        let cosE = cos(E);
        let f = E - e * sinE - M;
        let fp = 1.0 - e * cosE;
        E = E - f / fp;
    }
    return E;
}
fn blackbodyColor(temp: f32) -> vec3<f32> {
    let t = temp / 1000.0;
    var c = vec3<f32>(1.0);
    if (t >= 6.6) {
        c.x = clamp(1.29 * pow(t - 6.6, -0.133), 0.0, 1.0);
        c.y = c.x;
    } else {
        c.x = 1.0;
        c.y = clamp(0.39 * log(max(t - 2.0, 0.001)) + 0.5, 0.0, 1.0);
        c.z = clamp(0.54 * log(max(t - 4.0, 0.001)) + 0.7, 0.0, 1.0);
        if (t <= 4.0) { c.z = 0.0; }
        if (t <= 2.0) { c.y = 0.0; c.x = clamp(t / 2.0, 0.0, 1.0); }
    }
    return c;
}
fn accretionDiskDensity(r: f32, theta: f32, t: f32, turbDrive: f32) -> f32 {
    let inner = 0.6;
    let outer = 3.0;
    if (r < inner || r > outer) { return 0.0; }
    let radial = exp(-(r - 1.5) * (r - 1.5) * 2.0);
    let spiral = sin(theta * 3.0 + r * 4.0 - t * 0.5) * 0.5 + 0.5;
    let turb = hash12(vec2<f32>(r * 7.0 + theta * 2.0, t * 0.1)) * (0.2 + turbDrive * 0.4);
    return radial * (0.5 + spiral * 0.5 + turb);
}
fn spiralArmOffset(r: f32, armIndex: f32, numArms: f32, t: f32) -> vec2<f32> {
    let armAngle = (armIndex / numArms) * 2.0 * PI;
    let twist = log(r + 1.0) * 2.0 - t * 0.1;
    let angle = armAngle + twist;
    return vec2<f32>(cos(angle) * r * 0.15, sin(angle) * r * 0.15);
}
fn particlePosition(id: f32, t: f32, innerR: f32, outerR: f32) -> vec3<f32> {
    let a = mix(innerR, outerR, fract(id * 0.618034));
    let e = 0.05 + fract(id * 0.3718) * 0.25;
    let incline = fract(id * 0.2171) * 0.3;
    let M = fract(id * 0.9137) * 2.0 * PI + t * (0.1 + fract(id * 0.517) * 0.2);
    let E = meanAnomalyToEccentric(M, e);
    // tan() is not in WGSL — clamped sin/cos quotient (E/2 never near π/2 here).
    let halfE = E * 0.5;
    let tanHalf = clamp(sin(halfE) / cos(halfE), -1000.0, 1000.0);
    let trueAnomaly = 2.0 * atan(sqrt((1.0 + e) / (1.0 - e)) * tanHalf);
    let r = keplerOrbit(trueAnomaly, a, e);
    let basePos = vec2<f32>(r * cos(trueAnomaly), r * sin(trueAnomaly));
    let armOffset = spiralArmOffset(a, fract(id * 0.97) * 3.0, 3.0, t);
    let pos2d = basePos + armOffset;
    let moonR = 0.08 + fract(id * 0.333) * 0.12;
    let moonAngle = t * (1.0 + fract(id * 0.777) * 2.0) + id * 10.0;
    let moonPos = vec2<f32>(cos(moonAngle) * moonR, sin(moonAngle) * moonR);
    let z = sin(incline) * r + (hash12(vec2<f32>(id, 0.0)) - 0.5) * 0.1;
    return vec3<f32>(pos2d.x + moonPos.x, pos2d.y + moonPos.y, z);
}
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}
fn map(p: vec3<f32>, time: f32) -> vec4<f32> {
    var d = MAX_DIST;
    var temp = 1000.0;
    var metal = 0.0;
    var density = 0.0;
    var q = p;
    // Hoisted mouse-orbit rotations (identical transform as the original).
    let rot_yz = g_rotYZ * q.yz;
    q.y = rot_yz.x; q.z = rot_yz.y;
    let rot_xz = g_rotXZ * q.xz;
    q.x = rot_xz.x; q.z = rot_xz.y;
    // Central singularity.
    let centralDist = sdSphere(q, 0.25);
    if (centralDist < d) {
        d = centralDist; temp = 8000.0; metal = 0.9; density = 1.0;
    }
    // Accretion disk — coarse annular-slab cull before the density eval.
    let diskR = length(q.xz);
    let slab = max(abs(q.y) - 0.25, max(0.6 - diskR, diskR - 3.0));
    if (slab < 0.25) {
        let diskTheta = atan2(q.z, q.x);
        let diskDensity = accretionDiskDensity(diskR, diskTheta, time, g_fftTurb);
        let diskVertical = abs(q.y) - 0.05 - diskDensity * 0.08;
        let diskOuter = diskR - 3.0;
        let diskInner = 0.6 - diskR;
        let diskSdf = max(max(diskVertical, diskOuter), diskInner);
        if (diskSdf < d) {
            d = diskSdf; temp = 4000.0 + diskDensity * 4000.0;
            metal = 0.5 + diskDensity * 0.4; density = diskDensity;
        }
    } else {
        d = min(d, slab); // conservative SDF outside the slab
    }
    // Orbiting bodies — positions cached once per pixel (Complexity slider).
    for (var i: i32 = 0; i < g_numBodies; i++) {
        let body = g_bodies[i];
        let bodyDist = sdSphere(q - body.xyz, body.w);
        if (bodyDist < d) {
            d = bodyDist; temp = g_bodyProps[i].x;
            metal = g_bodyProps[i].y; density = 1.0;
        }
    }
    return vec4<f32>(d, temp, metal, density);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let pixel = vec2<i32>(gid.xy);
    let res = vec2<f32>(u.config.zw);
    // Bounds guard — mandatory.
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = (vec2<f32>(pixel) * 2.0 - res) / res.y;

    // ── Sliders — all four LIVE ─────────────────────────────────────
    let complexity = u.zoom_params.x;  // → orbiting body count
    let speed = u.zoom_params.y;       // → simulation time rate
    let glowGain = u.zoom_params.z;    // → near-miss bloom integral gain
    let audioAmt = u.zoom_params.w;    // → global audio drive

    let time = u.config.x * speed;

    // ── Audio: canonical bands scaled by Audio Reactivity + guarded FFT ──
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0)) * audioAmt;
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;
    var fft = 0.0;
    if (arrayLength(&extraBuffer) > 12u) {
        for (var bin = 1u; bin <= 8u; bin++) { fft += extraBuffer[4u + bin]; }
        fft *= 0.125 * audioAmt;
    }
    g_fftTurb = fft;

    // ── Per-pixel precompute (the Optimizer's hoist) ────────────────
    g_rotYZ = rot2D(u.zoom_config.z * PI);
    g_rotXZ = rot2D(u.zoom_config.y * PI);
    g_numBodies = clamp(i32(round(complexity)) + 2, 3, MAX_BODIES);
    for (var i: i32 = 0; i < g_numBodies; i++) {
        let fi = f32(i + 1);
        g_bodies[i] = vec4<f32>(
            particlePosition(fi, time, 0.8, 3.5),
            0.04 + fract(fi * 0.618) * 0.03
        );
        g_bodyProps[i] = vec2<f32>(2000.0 + fract(fi * 0.419) * 4000.0, fract(fi * 0.731));
    }

    // ── Ray setup + analytic bounding-sphere cull ───────────────────
    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));
    let halfB = dot(ro, rd);
    let cTerm = dot(ro, ro) - BOUND_RADIUS * BOUND_RADIUS;
    let disc = halfB * halfB - cTerm;

    var t = 0.0;
    var hit = false;
    var glowAcc = 0.0;
    var surf = vec4<f32>(0.0);
    if (disc > 0.0) {
        t = max(-halfB - sqrt(disc), 0.0); // start at sphere entry, not the camera
        for (var i: i32 = 0; i < MAX_STEPS; i++) {
            let p = ro + rd * t;
            surf = map(p, time);
            if (surf.x < SURF_DIST) { hit = true; break; }
            if (t > MAX_DIST) { break; }
            // Near-miss glow integral — one exp per step, gain applied later.
            glowAcc += exp(-max(surf.x, 0.0) * 6.0) * 0.015;
            t += surf.x;
        }
    }

    // ── Shading (blackbody + audio pulse, HDR-ready) ────────────────
    var col = vec3<f32>(0.0);
    var alpha = 0.0;
    if (hit) {
        let bb = blackbodyColor(surf.y);
        col.r = clamp(surf.y / 9000.0, 0.0, 1.0);
        col.g = surf.z * (0.9 + mids * 0.2);
        col.b = dot(bb, vec3<f32>(0.299, 0.587, 0.114)) * (0.85 + treble * 0.3);
        // Audio-reactive pulsing on the central body and hot areas.
        let tempPulse = 1.0 + bass * 0.25 * sin(time * 4.0);
        col *= tempPulse;
        alpha = clamp(surf.w, 0.0, 1.0);
    }

    // Near-miss bloom driven by the Glow Intensity slider (HDR values ok).
    col += GLOW_COLOR * glowAcc * glowGain * (1.0 + bass * 0.5);
    alpha = max(alpha, clamp(glowAcc * glowGain * 0.25, 0.0, 0.6));

    // Starfield fallback (FFT-twinkled).
    if (alpha < 0.01) {
        let starHash = hash12(uv * 100.0 + vec2<f32>(time * 0.01, 0.0));
        if (starHash > 0.995) {
            let starBright = (starHash - 0.995) * 200.0;
            col = vec3<f32>(0.85, 0.9, 1.0) * starBright * (0.9 + treble * 0.2 + fft * 0.3);
            alpha = clamp(starBright, 0.0, 1.0);
        }
    }

    // Atmospheric depth fog.
    let fog = 1.0 - exp(-t * 0.08);
    col = mix(col, FOG_COLOR, fog * 0.6);

    // ── Temporal history (kinetic trails) + real hit depth ──────────
    let prev = textureLoad(dataTextureC, pixel, 0);
    let smoothed = mix(col, prev.rgb * 0.88, 0.4);
    textureStore(dataTextureA, pixel, vec4<f32>(smoothed, alpha));
    textureStore(writeTexture, pixel, vec4<f32>(max(smoothed, vec3<f32>(0.0)), alpha));
    // Real generated depth: nearer hits → nearer one. Sky rays stay 0.
    let depth = select(0.0, clamp(1.0 - (t - 0.5) / 9.0, 0.0, 1.0), hit);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
