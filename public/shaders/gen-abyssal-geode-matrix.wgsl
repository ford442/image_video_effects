// ----------------------------------------------------------------
// Abyssal Geode Matrix
// Category: generative
// Features: raymarching, audio-reactive, mouse-driven, upgraded-rgba
// Upgraded: 2026-11-15
// Ideas: orbit-trap mineral veins (§12.2E); Beer–Lambert deep-water absorption (§12.2F); step-count AO (§12.2E)
// A packing: ACES display RGBA (nothing reads C)
// ----------------------------------------------------------------
#include "_prelude.wgsl"

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

// Rescue 5: the gravity well sits a fixed distance AHEAD of the camera (HEAD anchored it at world z = 0,
// which the fly-through camera leaves behind after ~10 s — the pointer stopped doing anything).
var<private> gWell: vec3<f32>;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let p_abs = abs(p);
    return (p_abs.x + p_abs.y + p_abs.z - s) * 0.57735027;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let xc = max(x, vec3<f32>(0.0));
    return clamp((xc * (2.51 * xc + 0.03)) / (xc * (2.43 * xc + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Gravity well pull + domain repetition, shared by map() and trapAt() so they always see the same point.
fn foldedStart(p_in: vec3<f32>) -> vec3<f32> {
    var p = p_in;

    // Mouse Interaction (Gravity Well)
    if (u.zoom_config.w > 0.5) {
        let d2 = length(p - gWell);
        if (d2 < 2.0) {
            let force = (2.0 - d2) * u.zoom_params.x * 2.0;
            p = mix(p, gWell, force * 0.1);
        }
    }

    // Domain Repetition
    let c = 4.0;
    return (fract(p/c + 0.5) - 0.5) * c;
}

fn map(p_in: vec3<f32>) -> f32 {
    var p = foldedStart(p_in);

    // Fractal Fold
    var s = 1.0;
    let t = u.config.x * u.zoom_params.y;
    let iters = max(1.0, 4.0 * u.zoom_params.w);
    for(var i=0; i<i32(iters); i++) {
        p = abs(p) - vec3<f32>(1.0, 0.5, 0.2) * s;
        let r_mat = rot(t * 0.2 + f32(i));
        p = vec3<f32>(r_mat * p.xy, p.z);
        p = vec3<f32>(p.x, r_mat * p.yz);
        s *= 0.5;
    }

    let d1 = sdOctahedron(p, 1.5 * s);
    return d1;
}

// ── Idea 1: orbit-trap mineral veins (§12.2E) ──────────────────────────
// A geode is mineral: veins and inclusions are what you read first. The same fold loop as map(), run ONCE at the
// hit (not on every march step), tracking how close the orbit passes the x = y fold diagonal, normalised by the
// iteration's own scale. Keep the fold body identical to map().
fn trapAt(p_in: vec3<f32>) -> f32 {
    var p = foldedStart(p_in);
    var s = 1.0;
    let t = u.config.x * u.zoom_params.y;
    let iters = max(1.0, 4.0 * u.zoom_params.w);
    var trap = 1.0e9;
    for(var i=0; i<i32(iters); i++) {
        p = abs(p) - vec3<f32>(1.0, 0.5, 0.2) * s;
        let r_mat = rot(t * 0.2 + f32(i));
        p = vec3<f32>(r_mat * p.xy, p.z);
        p = vec3<f32>(p.x, r_mat * p.yz);
        trap = min(trap, abs(p.x - p.y) / (s * 2.0 + 0.1));
        s *= 0.5;
    }
    return trap;
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = map(p);
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        map(p - e.xyy),
        map(p - e.yxy),
        map(p - e.yyx)
    );
    return normalize(n);
}

// ── Idea 3 / Rescue 1: step-count ambient occlusion (§12.2E, snippet E2) ─
// HEAD's "fake AO" was `1.0 - MAX_STEPS/100` — exactly 0 — so the lit crystal
// surface multiplied to black. Five taps along the normal, on the file's own map().
fn aoFive(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for (var i = 1; i <= 5; i = i + 1) {
        let h = 0.01 + 0.18 * f32(i) / 5.0;
        occ += (h - map(p + n * h)) * sca;
        sca *= 0.5;
    }
    return clamp(1.0 - 3.4 * occ, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = vec2<f32>(u.config.zw);
    let coord = vec2<f32>(f32(id.x), f32(id.y));
    if (coord.x >= dimensions.x || coord.y >= dimensions.y) {
        return;
    }

    let uv = (coord - 0.5 * dimensions) / dimensions.y;

    // Camera
    var ro = vec3<f32>(0.0, 0.0, -3.0 + u.config.x * 0.5); // move forward
    let rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // Audio Reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // Rescue 5: the well sits 3 units down the ray through the cursor (same +y-down convention as `uv`).
    let mouseUv = vec2<f32>((u.zoom_config.y - 0.5) * dimensions.x / max(dimensions.y, 1.0), u.zoom_config.z - 0.5);
    gWell = ro + vec3<f32>(mouseUv * 3.0, 3.0);

    // Raymarching
    var dO = 0.0;
    var p = vec3<f32>(0.0);
    var glow = 0.0;
    for(var i=0; i<MAX_STEPS; i++) {
        p = ro + rd * dO;
        let dS = map(p);
        dO += dS;
        // Accumulate glow near surfaces; far glow is dimmer (the water is not clear).
        glow += 0.01 / (0.01 + dS*dS) * max(1.0 - dO * 0.05, 0.12);
        if(dO > MAX_DIST || dS < SURF_DIST) { break; }
    }
    let hit = dO < MAX_DIST;

    // ── Idea 2: Beer–Lambert deep-water absorption (§12.2F) ────────────
    // Red dies first, then green: far crystals sink teal → black. Per-channel
    // transmittance along the ray; in-scatter fog is added below.
    let sigma = vec3<f32>(0.30, 0.09, 0.04);
    let absorb = exp(-min(dO, 24.0) * sigma);
    let absorbGlow = exp(-min(dO, 14.0) * sigma);

    var col = vec3<f32>(0.0);
    var vein = 0.0;
    if(hit) {
        let n = getNormal(p);
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let ao = aoFive(p, n);

        let baseCol = vec3<f32>(0.05, 0.15, 0.25); // Deep sea
        // Idea 1: warm quartz/amber veins against the cold base; treble makes them shimmer.
        vein = 1.0 - smoothstep(0.0, 0.025, trapAt(p));
        let veinCol = vec3<f32>(1.0, 0.62, 0.22) * vein * (0.55 + treble * 0.9);
        col = (baseCol * (0.15 + diff) + veinCol * (0.4 + 0.6 * diff)) * ao * absorb;
    }

    // Bioluminescence based on audio and proximity.
    // ── Rescue 2: idle floor — HEAD's emissive was cyan*bass + magenta*mids, exactly 0 at silence, so the whole
    // frame was black and glowIntensity did nothing without audio. ──
    // ── Rescue 3: glow normalisation — `glow` sums up to ~100 steps of <= 1 each; HEAD added it raw (meanL 12.8
    // with audio, a white frame). The 0.04 factor puts default exposure mid-range. ──
    let emissiveColor = vec3<f32>(0.0, 1.0, 1.0) * (0.25 + bass) + vec3<f32>(1.0, 0.0, 1.0) * (0.10 + mids);
    col += glow * 0.04 * emissiveColor * u.zoom_params.z * absorbGlow;
    // In-scatter: the abyss is a faint teal, not void.
    col += vec3<f32>(0.0, 0.03, 0.06) * (1.0 - exp(-min(dO, 40.0) * 0.15));

    // ── Rescue 4: output floor — HEAD wrote only writeTexture, raw HDR, alpha a bare 1.0, no depth, no A. ──
    // ACES on display, semantic alpha (surface coverage + glow), depth (near = 1), A = display RGBA.
    let mapped = acesToneMap(col);
    let glowLum = clamp(dot(col, vec3<f32>(0.299, 0.587, 0.114)), 0.0, 1.0);
    let coverage = select(0.0, 1.0, hit);
    let alpha = clamp(0.10 + coverage * 0.72 + glowLum * 0.18, 0.10, 0.98);
    let depthOut = coverage * exp(-dO * 0.12);
    let outCol = vec4<f32>(mapped, alpha);
    textureStore(writeTexture, vec2<i32>(id.xy), outCol);
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(id.xy), outCol);
}
