// ═══════════════════════════════════════════════════════════════════
//  Bismuth Singularity-Loom Engine
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: self-assembling sectors (each of the six cubes at its own fractional carve stage); gravitational time dilation (proper-time lag of the twist + assembly clock, dilated fringe frequency); singularity shadow (lensed rays captured inside rs go black)
//  A packing: HDR linear RGB (pre-ACES) + semantic alpha; C read back as HDR trail memory (ACES only on writeTexture)
// ═══════════════════════════════════════════════════════════════════
//  Kept from HEAD: six-fold angular repeat, pointer twist/pitch, boolean
//  subtraction loop, step-wise gravitational lensing, proximity glow,
//  step-count AO, cosine iridescence on n.v, FFT band-split flux veins,
//  click rings, gravitational-memory feedback trails, real hit depth.
//  Pointer note: the extraBuffer[133..138] "spring" is inert (the engine
//  zeroes that scratch every frame), so sm == raw pointer. Left as-is.
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// --- CORE LOGIC ---
const MAX_STEPS: i32 = 120;
const MAX_DIST: f32 = 50.0;
const SURF_DIST: f32 = 0.001;

// Idea 2: seconds of proper-time lag a clock at rest would show at tau = 0.
const DILATION_LAG: f32 = 25.0;

struct MarchResult {
    col: vec3<f32>,
    glow: f32,
    depth: f32,
    hitF: f32,
    ao: f32,
    minR: f32,
    capturedF: f32,
};

fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    let t = 1.0 - c;
    let x = axis.x; let y = axis.y; let z = axis.z;
    return mat3x3<f32>(
        t*x*x + c,   t*x*y - s*z, t*x*z + s*y,
        t*x*y + s*z, t*y*y + c,   t*y*z - s*x,
        t*x*z - s*y, t*y*z + s*x, t*z*z + c
    );
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn mod_f32(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 2 + 3: one Schwarzschild radius, set by the Mass slider, drives both
// the clock dilation and the capture (shadow) radius.
fn schwarzschildR() -> f32 {
    return 0.15 + 0.45 * u.zoom_params.x;
}

// Idea 2: gravitational time dilation factor d(tau)/dt = sqrt(1 - rs/r).
fn dilation(r: f32, rs: f32) -> f32 {
    return sqrt(max(1.0 - rs / max(r, 1e-3), 0.0));
}

fn map(p: vec3<f32>, sm: vec2<f32>, bassAmp: f32, midsAmp: f32) -> vec2<f32> {
    let time = u.config.x;

    // Idea 2: local proper time. The lag is bounded (never grows with time),
    // and r is floored at 2.5 rs so the shear stays Lipschitz near the core.
    let rs = schwarzschildR();
    let tauLocal = dilation(max(length(p), 2.5 * rs), rs);
    let tProper = time - DILATION_LAG * (1.0 - tauLocal);

    var pos = p;

    // Angular repetition
    let angle = atan2(pos.z, pos.x);
    let radius = length(vec2<f32>(pos.x, pos.z));
    let sector = 6.28318 / 6.0;

    let a_mod = mod_f32(angle + sector * 0.5, sector) - sector * 0.5;
    // Idea 1: which of the six cubes this point belongs to (0..5, wrapped at ±pi)
    let sectorId = mod_f32(floor((angle + sector * 0.5) / sector), 6.0);

    pos = vec3<f32>(radius * cos(a_mod), pos.y, radius * sin(a_mod));

    // Shift outwards to create space for singularity
    pos = pos - vec3<f32>(2.5, 0.0, 0.0);

    // Twist driven by the sprung pointer; mids accelerate the weave.
    // Idea 2: the twist runs on proper time, so the core-facing side of each
    // cube lags behind its outer side (a static gravitational shear).
    pos = rot3D(vec3<f32>(0.0, 1.0, 0.0), tProper * (0.1 + midsAmp * 0.15) + sm.x * 2.0) * pos;
    pos = rot3D(vec3<f32>(1.0, 0.0, 0.0), sm.y * 2.0) * pos;

    // Implementation of stepped Bismuth hopper-crystal logic via repeated boolean subtractions
    var q = abs(pos) - vec3<f32>(1.0);
    var d = sdBox(q, vec3<f32>(1.0)); // Placeholder base shape

    let iters = i32(u.zoom_params.y);
    var scale = 1.0;

    // Idea 1: self-assembling sectors. Each cube runs its own assembly clock
    // (golden-angle phase per sector, on proper time so the carve front
    // sweeps outward from the singularity) and carves to a fractional stage
    // in [0.38, 0.76] * Iterations: seed blocks -> terraced shards -> dust.
    // Near a sector edge the phase blends toward the neighbour's, reaching the
    // same 50/50 value from both sides, so the per-sector stage is continuous
    // across the boundary and does not tear the SDF.
    let side = select(-1.0, 1.0, a_mod > 0.0);
    let nbId = mod_f32(sectorId + side, 6.0);
    let edgeW = 0.5 * smoothstep(0.35, 1.0, abs(a_mod) / (sector * 0.5));
    let assembly = mix(0.5 - 0.5 * cos(tProper * 0.13 + sectorId * 2.39996),
                       0.5 - 0.5 * cos(tProper * 0.13 + nbId * 2.39996), edgeW);
    let stage = f32(iters) * mix(0.38, 0.76, assembly);

    // Extrusion: rest extrusion grows with the stage (terraces thicken as the
    // hopper deepens, capped at the dust threshold ~2.1) and is scaled by the
    // Extrusion slider; bass rides on top (HEAD's bassAmp * w, softened to 0.4
    // because the lattice is very extrusion-sensitive once it exists).
    // HEAD's ext = bassAmp * w left the lattice fully carved away -- no
    // surface anywhere (min SDF ~ +0.095) -- at audio 0.
    let ext = bassAmp * u.zoom_params.w * 0.4
        + min(0.2 + 0.5 * stage, 2.1) * (0.75 + 0.25 * u.zoom_params.w);

    for (var i: i32 = 0; i < 10; i++) {
        if (i >= iters) { break; }
        // Idea 1: fractional carve of the stage's last iteration
        let carve = clamp(stage - f32(i), 0.0, 1.0);
        if (carve <= 0.0) { break; }

        q = abs(q) - vec3<f32>(0.5 / scale) - vec3<f32>(ext * 0.1 / scale);
        q = rot3D(normalize(vec3<f32>(1.0, 1.0, 1.0)), 0.1) * q;

        // carve = 1 is HEAD's cut; carve -> 0 shrinks the cut to a point
        let sub_box = sdBox(q, vec3<f32>(0.6 / scale)) + (1.0 - carve) * 0.6 / scale;
        d = max(d, -sub_box);

        scale *= 1.3;
    }

    return vec2<f32>(d, 1.0); // dist, material_id
}

fn getNormal(p: vec3<f32>, sm: vec2<f32>, bassAmp: f32, midsAmp: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e.x, e.y, e.y), sm, bassAmp, midsAmp).x - map(p - vec3<f32>(e.x, e.y, e.y), sm, bassAmp, midsAmp).x,
        map(p + vec3<f32>(e.y, e.x, e.y), sm, bassAmp, midsAmp).x - map(p - vec3<f32>(e.y, e.x, e.y), sm, bassAmp, midsAmp).x,
        map(p + vec3<f32>(e.y, e.y, e.x), sm, bassAmp, midsAmp).x - map(p - vec3<f32>(e.y, e.y, e.x), sm, bassAmp, midsAmp).x
    ));
}

fn raymarching(ro: vec3<f32>, rd_in: vec3<f32>, sm: vec2<f32>, bassAmp: f32, midsAmp: f32, trebleAmp: f32) -> MarchResult {
    var dO: f32 = 0.0;
    var col: vec3<f32> = vec3<f32>(0.0);
    var p = ro;
    var rd = rd_in;

    var hit = false;
    var glow = 0.0;
    var iter_count = 0;

    // Idea 3: closest approach to the singularity along the bent ray
    let rs = schwarzschildR();
    var minR = 1e9;
    var captured = false;

    for(var i: i32 = 0; i < MAX_STEPS; i++) {
        iter_count = i;
        // Gravitational lensing: pointer y + bass deepen the gravity well
        let dist_to_center = length(p);
        let pull_str = (u.zoom_params.x + sm.y * 0.5 + bassAmp * 0.35) / (dist_to_center * dist_to_center + 0.1);
        rd = normalize(rd - normalize(p) * pull_str * 0.05); // Bend ray

        let map_res = map(p, sm, bassAmp, midsAmp);
        let dS = map_res.x;

        glow += 0.01 / (0.01 + abs(dS));

        if(dS < SURF_DIST) {
            hit = true;
            break;
        }
        if(dO > MAX_DIST) {
            break;
        }

        // Idea 3: test the whole step segment (steps are long near the empty
        // core, so a point test would tunnel through the horizon).
        let tSeg = clamp(-dot(p, rd), 0.0, dS);
        let segR = length(p + rd * tSeg);
        minR = min(minR, segR);
        if (segR < rs) {
            captured = true;
            break;
        }

        p += rd * dS;
        dO += dS;
    }

    var ao = 0.0;
    // Shade based on hit normal + iridescence
    if (hit) {
        let normal = getNormal(p, sm, bassAmp, midsAmp);
        let view_dir = -rd;
        let ndotv = max(dot(normal, view_dir), 0.0);

        // treble tightens the iridescent interference bands
        // Idea 2: a distant observer sees the fringe frequency redshifted by
        // tau at the hit point, so bands broaden on core-facing facets.
        let tauHit = dilation(length(p), rs);
        let freq = u.zoom_params.z * (1.0 + trebleAmp * 0.25) * mix(0.35, 1.0, tauHit);
        let a = vec3<f32>(0.5);
        let b = vec3<f32>(0.5);
        let c = vec3<f32>(freq);
        let d = vec3<f32>(0.0, 0.33, 0.67);

        let base_col = palette(ndotv, a, b, c, d);
        ao = 1.0 - f32(iter_count) / f32(MAX_STEPS);

        col = base_col * ao;
    }

    var result: MarchResult;
    result.col = col;
    result.glow = glow;
    result.depth = select(0.0, clamp(1.0 - dO / MAX_DIST, 0.0, 1.0), hit);
    result.hitF = select(0.0, 1.0, hit);
    result.ao = ao;
    result.minR = minR;
    result.capturedF = select(0.0, 1.0, captured);
    return result;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);
    if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }

    let resF = vec2<f32>(dims);
    let aspect = f32(dims.x) / f32(dims.y);
    let time = u.config.x;
    let uv = (vec2<f32>(coords) - 0.5 * resF) / f32(dims.y);
    let uv01 = (vec2<f32>(coords) + 0.5) / resF;

    // --- Audio truth: real bands + guarded FFT bins only ---
    let bassAmp = plasmaBuffer[0].x;
    let midsAmp = plasmaBuffer[0].y;
    let trebleAmp = plasmaBuffer[0].z;
    var fftLow = 0.0;
    var fftMid = 0.0;
    var fftHigh = 0.0;
    if (arrayLength(&extraBuffer) > 13u) {
        fftLow = extraBuffer[6];   // engine FFT bin 1
        fftMid = extraBuffer[9];   // engine FFT bin 4
        fftHigh = extraBuffer[12]; // engine FFT bin 7
    }

    // --- Pointer (HEAD spring kept; inert because [133..138] is zeroed per frame) ---
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var sm = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var smVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) { sm = rawMouse; smVel = vec2<f32>(0.0); }
    let sdt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let omega = 6.0 + midsAmp * 3.0; // mids stiffen the follow
    smVel += ((rawMouse - sm) * omega * omega - smVel * 2.0 * omega) * sdt;
    sm += smVel * sdt;
    if (global_id.x == 0u && global_id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = sm.x; extraBuffer[134] = sm.y;
        extraBuffer[135] = smVel.x; extraBuffer[136] = smVel.y;
        extraBuffer[137] = 1.0; extraBuffer[138] = time;
    }
    let smCentered = (sm - 0.5) * 2.0; // y=0 top → negative pitch up top (no flip of source)

    // Subtle pointer-parallax camera sway.
    // Camera pulled back 5 -> 6.2 (focal 1 -> 1.24 keeps the framing): at r=5
    // the camera sat inside the cubes' reach (map(ro) < 0 for solid stages /
    // pointer corners). At 6.2 it clears every cube's bounding sphere.
    let ro = vec3<f32>(smCentered.x * 0.6, -smCentered.y * 0.6, -6.2);
    let rd = normalize(vec3<f32>(uv.x, uv.y, 1.24));

    let march = raymarching(ro, rd, sm, bassAmp, midsAmp, trebleAmp);
    var col = march.col;

    // FFT multi-band color split on the emissive flux veins
    var veinCol = vec3<f32>(0.1, 0.4, 1.0);
    veinCol.r += fftLow * 0.35;
    veinCol.g += fftMid * 0.25;
    veinCol.b += fftHigh * 0.15;
    col += veinCol * march.glow * 0.015 * (1.0 + bassAmp * 3.0);

    // --- Click rings (2D glow rings; age = time - ripple.z, .w unused) ---
    var shock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleAge = time - ripple.z;
        if (rippleAge >= 0.0 && rippleAge < 2.0) {
            let delta = (uv01 - ripple.xy) * vec2<f32>(aspect, 1.0);
            let ring = exp(-abs(length(delta) - rippleAge * 0.35) * 24.0) * exp(-rippleAge * 1.6);
            shock = max(shock, ring);
        }
    }
    col += vec3<f32>(0.9, 0.75, 1.1) * shock * (0.35 + bassAmp * 0.4);

    // Idea 3: singularity shadow. Captured rays are black; rays grazing just
    // outside rs fade into it. Crystal hits in front of the hole are untouched.
    let rs = schwarzschildR();
    let graze = smoothstep(rs, rs * 1.35, march.minR);
    let shadowMask = select(graze * (1.0 - march.capturedF), 1.0, march.hitF > 0.5);
    col *= shadowMask;

    // --- Emergent gravitational memory: history-dependent glow trails ---
    // The lattice's wake lingers off-surface; bass lengthens persistence;
    // shockwaves and fresh surface hits overwrite the memory.
    // C holds last frame's HDR colour (A packing), so no re-bounding here.
    let prev = textureLoad(dataTextureC, coords, 0);
    let persistence = clamp(0.3 + bassAmp * 0.12 + min(march.glow * 0.004, 0.3), 0.0, 0.85)
        * (1.0 - march.hitF * 0.85) * (1.0 - clamp(shock, 0.0, 1.0) * 0.5)
        * shadowMask; // Idea 3: the horizon swallows the trail memory too
    col = mix(col, prev.rgb * 0.96, persistence);
    col = max(col, vec3<f32>(0.0));

    // Semantic alpha: crystal coverage (AO-weighted) on hit; translucent veil
    // off-surface; the horizon is fully opaque.
    let veil = clamp(0.25 + march.glow * 0.02 + shock * 0.2, 0.0, 0.85);
    let alpha = select(mix(1.0, veil, shadowMask), mix(0.9, 1.0, march.ao), march.hitF > 0.5);
    // Generated depth: real raymarch hit depth (near-is-one), shock lifts the veil
    let depth = clamp(march.depth + shock * 0.15 * (1.0 - march.hitF) * shadowMask, 0.0, 1.0);

    textureStore(writeTexture, coords, vec4<f32>(acesToneMap(col), alpha));
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(col, alpha));
}
