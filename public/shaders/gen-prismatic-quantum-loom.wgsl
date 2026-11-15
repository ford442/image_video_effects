// ═══════════════════════════════════════════════════════════════════
//  Prismatic Quantum Loom
//  Category: generative
//  Features: raymarched, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: weave interlace (over/under parity offset per cell); Cauchy-dispersed glow halos (§12.2F)
//  A packing: display RGBA — ACES display RGB + semantic glow alpha (A = same display RGBA; nothing reads C)
//  Identity: a camera drifting through a domain-repeated lattice of glowing threads (three crossing
//            cylinder families, domain-warped, 64-step march); a held pointer bends rays toward it.
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

// Core parameters mapped from UI
// u.zoom_params.x = Thread Density
// u.zoom_params.y = Chromatic Shift
// u.zoom_params.z = Gravity Well Strength
// u.zoom_params.w = Quantum Fluctuation Speed

const PI: f32 = 3.14159265359;
// Idea 2 constant: Cauchy B coefficient (n(λ) = 1 + B/λ², λ in µm). Larger B = wider R↔B halo split.
const CAUCHY_B: f32 = 0.25;
const EXPOSURE: f32 = 0.5;   // ACES input gain (HEAD used c/(1+c); keeps the default frame near HEAD's brightness)

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let xc = max(x, vec3<f32>(0.0));
    return clamp((xc * (2.51 * xc + vec3<f32>(0.03))) / (xc * (2.43 * xc + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Relative refractive index n(650)/n(550), 1, n(450)/n(550): <1, 1, >1.
fn cauchyScale() -> vec3<f32> {
    let lam = vec3<f32>(0.650, 0.550, 0.450);
    let n = vec3<f32>(1.0) + vec3<f32>(CAUCHY_B) / (lam * lam);
    return n / n.y;
}

// Domain repetition. Rescue 2: WGSL `%` on f32 is a TRUNCATED remainder, so
// `(p + 0.5c) % c - 0.5c` was not centred for p + 0.5c < 0 (half of every axis).
fn opRep(p: vec3<f32>, c: vec3<f32>) -> vec3<f32> {
    return p - c * floor(p / c + vec3<f32>(0.5));
}

// Domain warp (HEAD's, unchanged) — shared by map() and the camera placement.
fn warpP(pos: vec3<f32>, time: f32) -> vec3<f32> {
    var p = pos;
    p.x += sin(p.z * 0.5 + time) * 0.2;
    p.y += cos(p.x * 0.5 + time * 0.8) * 0.2;
    return p;
}

// Map function
fn map(pos: vec3<f32>, threadRadius: f32) -> f32 {
    let time = u.config.x * u.zoom_params.w;
    // Apply domain warping based on time
    var p = warpP(pos, time);

    // Domain repetition (cell index kept for the weave parity)
    let spacing = vec3<f32>(1.5 / max(u.zoom_params.x, 0.05));
    let cell = floor(p / spacing + vec3<f32>(0.5));
    p = opRep(p, spacing);

    // ── Idea 1: weave interlace (native — a loom interlaces) ──────────
    // HEAD fused all three thread families at the cell centre. In a plain weave
    // warp and weft pass over and under each other: every thread is displaced
    // sideways by ± one thread-and-a-bit with a checker parity per cell, so along
    // its length it undulates (period 2 cells) and at every crossing one thread
    // goes in front of the other instead of through it. Offsets are cyclic
    // (z-thread → x, x-thread → y, y-thread → z) so no two families touch.
    let parity = 1.0 - 4.0 * fract((cell.x + cell.y + cell.z) * 0.5);   // ±1
    let amp = min(2.4 * threadRadius, 0.22 * spacing.x);
    let wz = parity * amp * cos(PI * p.z / spacing.z);
    let wx = parity * amp * cos(PI * p.x / spacing.x);
    let wy = parity * amp * cos(PI * p.y / spacing.y);

    // SDF of intersecting threads (HEAD's three cylinders, now offset)
    let d1 = length(vec2<f32>(p.x - wz, p.y)) - threadRadius;   // axis z
    let d2 = length(vec2<f32>(p.y - wx, p.z)) - threadRadius;   // axis x
    let d3 = length(vec2<f32>(p.z - wy, p.x)) - threadRadius;   // axis y

    // undulating cylinders are not exact SDFs: scale by 1/sqrt(1 + slope²)
    let slope = amp * PI / spacing.x;
    return min(min(d1, d2), d3) * inverseSqrt(1.0 + slope * slope);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<f32>(f32(global_id.x), f32(global_id.y));

    if (coord.x >= resolution.x || coord.y >= resolution.y) {
        return;
    }
    let pix = vec2<i32>(global_id.xy);
    let aspect = resolution.x / max(resolution.y, 1.0);

    // Rescue 1: audio is plasmaBuffer[0].xyz. HEAD read it from textureLoad(dataTextureC, …)
    // — C is history this shader never wrote, so the file was never audio-reactive.
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let threadRadius = 0.05 + 0.07 * bass;   // HEAD's `audioPulse` thread-radius pulse, now on bass

    // Normalized device coordinates (centred, ±0.5 vertical)
    let uv = (coord + vec2<f32>(0.5) - 0.5 * resolution) / resolution.y;

    // Camera setup. Rescue 5: HEAD's camera rode the lattice axis (0,0), so every crossing plane
    // put it INSIDE a thread — measured on the HEAD formula the camera is inside/touching a thread
    // 4–6 % of the time (whole frame black) and within 0.1 of one 30–44 % of the time (the thick
    // shaft filling the frame). Same forward drift, but the camera now follows the centre of the
    // warped gap channel (warped x,y = half a cell), so it threads the loom instead of through it.
    let z0 = -3.0 + u.config.x * 0.5;
    let wt = u.config.x * u.zoom_params.w;
    let half = 0.75 / max(u.zoom_params.x, 0.05);
    let ro = vec3<f32>(half - sin(z0 * 0.5 + wt) * 0.2,
                       half - cos(half * 0.5 + wt * 0.8) * 0.2,
                       z0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Gravity Interaction.
    // Rescue 3: HEAD built mousePos as (mouse*2-1)*aspect (±aspect) against a uv that spans only
    // ±aspect/2, so the well sat at twice the cursor's offset from centre (off-screen past 75 %).
    if (u.zoom_config.w > 0.5) {
        let mousePos = (u.zoom_config.yz - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
        let distToMouse = length(uv - mousePos);
        let pull = exp(-distToMouse * 3.0) * u.zoom_params.z;
        rd = normalize(vec3<f32>(rd.xy + (mousePos - uv) * pull, rd.z));
    }

    // ── Idea 2: Cauchy-dispersed glow halos (§12.2F) ─────────────────
    // Glass/prism dispersion is non-linear in wavelength: n(λ) = 1 + B/λ². Each channel's
    // halo gets a soft-core radius scaled by n(λ)/n(550): the red halo is tight and bright
    // at the thread, the blue one wide and soft, so every thread carries a spectral fringe
    // (warm core → cool skirt) instead of a single-colour glow. Same march, same step count.
    let disp = cauchyScale();
    let core = vec3<f32>(0.01) * disp * disp;

    // Raymarching loop
    var t = 0.0;
    var glow = vec3<f32>(0.0);

    for (var i = 0; i < 64; i++) {
        let p = ro + rd * t;
        let d = map(p, threadRadius);

        if (d < 0.001 || t > 10.0) {
            break;
        }

        t += d;
        // Accumulate chromatic glow (per channel — Idea 2)
        glow += vec3<f32>(0.02) / (core + vec3<f32>(d * d));
    }

    // Chromatic shifting based on depth and params (HEAD's hit-distance sine; mids drift the phase)
    let shift = u.zoom_params.y + mids * 0.8;
    let tint = vec3<f32>(
        sin(t * 1.0 + shift) * 0.5 + 0.5,
        sin(t * 1.2 + shift + 2.0) * 0.5 + 0.5,
        sin(t * 1.4 + shift + 4.0) * 0.5 + 0.5
    );
    let hdr = tint * glow * 0.05 * (1.0 + 0.35 * treble);

    // Display: ACES (HEAD used c/(1+c)); alpha = glow coverage
    let mapped = acesToneMap(hdr * EXPOSURE);
    let alpha = clamp(1.0 - exp(-dot(hdr, vec3<f32>(0.3333)) * 3.0), 0.04, 0.98);
    let out_color = vec4<f32>(mapped, alpha);

    textureStore(writeTexture, pix, out_color);
    textureStore(writeDepthTexture, pix, vec4<f32>(clamp(t / 10.0, 0.0, 1.0), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pix, out_color);
}
