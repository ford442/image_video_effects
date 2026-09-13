// ═══════════════════════════════════════════════════════════════════
//  Luminescent Chrono-Fluid Astrolabe
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-13
//  Ideas: engraved limb graduations on every ring; geared outer mater + radius-ratio gear train; rete star-chart plate (almucantars, azimuths, sidereal stars)
//  A packing: ACES display RGBA (C read back as colour history, exact textureLoad)
// ═══════════════════════════════════════════════════════════════════
// Batch 36 (Optimizer) base kept: coarse->refined SDF (fluid noise culled
// when far), bounding-sphere early out, spring mouse, audio/FFT, semantic
// alpha, generated depth.

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active), .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .x = Intensity, .y = Speed, .z = Scale, .w = Mouse Influence (UI slider order)
  ripples: array<vec4<f32>, 50>, // .xy = ripple uv, .z = startTime (seconds), .w = padding
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ---- Raymarch budget (60fps @1080p) ------------------------------
const MAX_STEPS: i32 = 80;
const MAX_DIST: f32 = 22.0;
const SURF_DIST: f32 = 0.001;
const STEP_RELAX: f32 = 0.85;      // <1: fluid displacement breaks Lipschitz-1
const NUM_RINGS: i32 = 5;          // bounded ring budget
const FLUIDITY: f32 = 0.8;         // displacement amplitude of the chrono-fluid
// Rings farther than this coarse distance skip the 8-hash fluid noise:
// the displacement (<= ~0.6 world units) can never matter out there.
const FLUID_CULL_DIST: f32 = 1.5;
// Idea 2: gear teeth on the outer mater ring (bounded amplitude keeps the
// SDF close to Lipschitz-1 under STEP_RELAX).
const GEAR_TEETH: f32 = 36.0;
const GEAR_TOOTH_H: f32 = 0.025;
// Idea 3: rete plate latitude (stereographic almucantar geometry)
const PLATE_LAT: f32 = 0.72;

fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesTone(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + vec3<f32>(0.03))) /
                 (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)),
                 vec3<f32>(0.0), vec3<f32>(1.0));
}

// 3D value noise (iq-style lattice hash)
fn hash(p: f32) -> f32 {
    let q = fract(vec3<f32>(p) * vec3<f32>(17.1705, 31.7153, 51.4881));
    return fract(q.x * q.y * q.z * 13.13);
}

fn noise3D(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f_smooth = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    let n = p.x + p.y * 57.0 + 113.0 * p.z;

    return mix(mix(mix(hash(n + 0.0),   hash(n + 1.0),   f_smooth.x),
                   mix(hash(n + 57.0),  hash(n + 58.0),  f_smooth.x), f_smooth.y),
               mix(mix(hash(n + 113.0), hash(n + 114.0), f_smooth.x),
                   mix(hash(n + 170.0), hash(n + 171.0), f_smooth.x), f_smooth.y), f_smooth.z);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Per-frame scene constants, built once in main and passed by value.
struct SceneCtx {
    animTime: f32,        // time * Speed slider
    ringScale: f32,       // Scale slider: radius scale of the astrolabe
    detailFreq: f32,      // Scale slider: LOD-friendly noise frequency
    mouseWorld: vec2<f32>,// spring-smoothed cursor in world units (z=0 plane)
    mouseStrength: f32,   // Mouse Influence slider (bounded)
    bass: f32,
    treble: f32,
};

// Ring-local frame (shared by SDF and graduation shading).
// Idea 2: gear train — each ring spins about its axis at a rate set by the
// radius ratio to ring 0, alternating direction like meshing gears.
fn ringFrame(p: vec3<f32>, fi: f32, ctx: SceneCtx) -> vec3<f32> {
    var rp = p;
    // Audio-reactive realignment (treble wobble per ring)
    let axisShift = ctx.treble * 0.5 * sin(fi * 1.5 + ctx.animTime);
    let rpxy = rp.xy * rot2(ctx.animTime * 0.2 + fi * 0.5 + axisShift);
    rp.x = rpxy.x;
    rp.y = rpxy.y;
    let gearRatio = 1.0 / (1.0 + fi * 0.5);
    let gearDir = select(1.0, -1.0, (i32(fi) % 2) == 1);
    let rpxz = rp.xz * rot2(ctx.animTime * 0.3 * gearRatio * gearDir + fi * 0.8 + axisShift);
    rp.x = rpxz.x;
    rp.z = rpxz.y;
    return rp;
}

fn mouseWarp(p_in: vec3<f32>, ctx: SceneCtx) -> vec3<f32> {
    var p = p_in;
    // Bounded mouse gravity well (spring-smoothed, slider-scaled)
    let dm = p.xy - ctx.mouseWorld;
    let pull = ctx.mouseStrength / (dot(dm, dm) + 1.0);
    p.x += ctx.mouseWorld.x * pull * 0.5;
    p.y += ctx.mouseWorld.y * pull * 0.5;
    return p;
}

// Rings + holographic core. useFluid=false is the cheap coarse field.
fn sceneDist(p: vec3<f32>, ctx: SceneCtx, useFluid: bool) -> vec2<f32> {
    var d = MAX_DIST;
    var matId = 0.0;

    for (var i = 0; i < NUM_RINGS; i = i + 1) {
        let fi = f32(i);
        var rp = ringFrame(p, fi, ctx);

        let radius = (1.0 + fi * 0.5) * ctx.ringScale;
        let thickness = 0.05 + sin(ctx.animTime + fi) * 0.02;

        if (useFluid) {
            // Chrono-fluid displacement, LOD-scaled by the Scale slider
            let n = noise3D(rp * ctx.detailFreq + ctx.animTime) * FLUIDITY;
            rp = rp + rp * n * 0.2;
        }

        var ringD = sdTorus(rp, vec2<f32>(radius, thickness));
        // Idea 2: geared outer mater — rounded teeth on the outer rim only
        let isMater = i == NUM_RINGS - 1;
        let az = atan2(rp.z, rp.x);
        let tooth = clamp(sin(az * GEAR_TEETH) * 1.5, -1.0, 1.0) * 0.5 + 0.5;
        let outerSide = smoothstep(0.0, 0.04, length(rp.xz) - radius);
        ringD = select(ringD, ringD - GEAR_TOOTH_H * tooth * outerSide, isMater);
        let closer = ringD < d;
        d = select(d, ringD, closer);
        // matId 1.0..1.4 encodes ring index for graduation shading (< 1.5 = ring)
        matId = select(matId, 1.0 + fi * 0.1, closer);
    }

    // Holographic core, pulsing with the bass band
    let coreD = length(p) - 0.5 * ctx.ringScale + sin(ctx.animTime * 2.0 + ctx.bass * 4.0) * 0.05;
    let coreCloser = coreD < d;
    d = select(d, coreD, coreCloser);
    matId = select(matId, 2.0, coreCloser);

    return vec2<f32>(d, matId);
}

// Coarse cull: evaluate the cheap field first; only pay for the fluid
// noise when the ray is close enough for the displacement to matter.
fn map(p_in: vec3<f32>, ctx: SceneCtx) -> vec2<f32> {
    let p = mouseWarp(p_in, ctx);

    let coarse = sceneDist(p, ctx, false);
    if (coarse.x > FLUID_CULL_DIST) {
        return coarse;
    }
    return sceneDist(p, ctx, true);
}

fn getNormal(p: vec3<f32>, ctx: SceneCtx) -> vec3<f32> {
    let d = map(p, ctx).x;
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        map(p - e.xyy, ctx).x,
        map(p - e.yxy, ctx).x,
        map(p - e.yyx, ctx).x
    );
    return normalize(n + vec3<f32>(0.0, 0.0, 1e-6));
}

// Idea 1: engraved limb graduations. Returns (groove, majorGlint).
fn limbGraduation(pWorld: vec3<f32>, ringIdx: f32, ctx: SceneCtx) -> vec2<f32> {
    let rp = ringFrame(mouseWarp(pWorld, ctx), ringIdx, ctx);
    let radius = (1.0 + ringIdx * 0.5) * ctx.ringScale;
    let deg = (atan2(rp.z, rp.x) / TAU + 0.5) * 360.0;
    let fromFine = abs(fract(deg / 10.0 + 0.5) - 0.5) * 10.0;   // degrees to nearest 10deg mark
    let fromMajor = abs(fract(deg / 30.0 + 0.5) - 0.5) * 30.0;  // degrees to nearest 30deg mark
    // engrave only the outward/upper faces of the tube (the readable limb)
    let q = vec2<f32>(length(rp.xz) - radius, rp.y);
    let face = smoothstep(-0.2, 0.5, (q.x + abs(q.y)) / max(length(q), 1e-4));
    let fineMark = 1.0 - smoothstep(0.25, 0.6, fromFine);
    let majorMark = 1.0 - smoothstep(0.6, 1.2, fromMajor);
    return vec2<f32>(max(fineMark * 0.55, majorMark) * face, majorMark * face);
}

fn hash2(c: vec2<f32>) -> f32 {
    return hash(dot(c, vec2<f32>(1.0, 157.0)) * 0.0137);
}

// Idea 3: rete star-chart plate (stereographic almucantars + azimuths + stars)
fn retePlate(uv: vec2<f32>, ctx: SceneCtx, time: f32, mids: f32) -> vec3<f32> {
    let plateScale = 1.25 * ctx.ringScale;
    let pu = uv / max(plateScale, 0.05);
    let rPlate = length(pu);
    let plateMask = 1.0 - smoothstep(1.9, 2.2, rPlate);
    // Almucantars: stereographic altitude circles for latitude PLATE_LAT
    var lines = 0.0;
    let sinLat = sin(PLATE_LAT);
    let cosLat = cos(PLATE_LAT);
    for (var k = 0; k < 6; k = k + 1) {
        let alt = f32(k) * 0.25;
        let denom = max(sinLat + sin(alt), 0.05);
        let cy = cosLat / denom;
        let cr = cos(alt) / denom;
        let dc = abs(length(pu - vec2<f32>(0.0, -cy + 1.0)) - cr);
        lines = max(lines, exp(-dc * 180.0) * select(0.45, 0.8, k == 0));
    }
    // Azimuth spokes every 15 degrees, fading toward the rim
    let ang = atan2(pu.y, pu.x);
    let spoke = abs(fract(ang * 24.0 / TAU + 0.5) - 0.5) * TAU / 24.0 * rPlate;
    lines = max(lines, exp(-spoke * 220.0) * 0.35 * smoothstep(0.15, 0.4, rPlate) * (1.0 - smoothstep(1.2, 2.0, rPlate)));
    // Sidereal star field: rotates slowly about the core
    let su = pu * rot2(ctx.animTime * 0.05);
    let cell = floor(su * 22.0);
    let h = hash2(cell);
    let starPos = (cell + vec2<f32>(0.3 + 0.4 * fract(h * 17.0), 0.3 + 0.4 * fract(h * 31.0))) / 22.0;
    let sd = length(su - starPos) * 22.0;
    let twinkle = 0.7 + 0.3 * sin(time * 3.0 + h * 50.0) * (0.4 + mids);
    let star = step(0.9, h) * exp(-sd * sd * 60.0) * twinkle;
    return (vec3<f32>(0.85, 0.62, 0.25) * lines * 0.22 + vec3<f32>(0.75, 0.9, 1.2) * star * 0.9) * plateMask;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let pixel = vec2<i32>(gid.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) {
        return;
    }
    let time = u.config.x;
    let aspect = res.x / res.y;
    // ---- Spring-smoothed mouse (persistent state: extraBuffer[133..138]) --
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mouseUv = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) { mouseUv = rawMouse; mouseVelocity = vec2<f32>(0.0); }
    let springDt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let springOmega = 8.0;
    mouseVelocity += ((rawMouse - mouseUv) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
    mouseUv += mouseVelocity * springDt;
    if (gid.x == 0u && gid.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = mouseUv.x; extraBuffer[134] = mouseUv.y;
        extraBuffer[135] = mouseVelocity.x; extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0; extraBuffer[138] = time;
    }

    // ---- Audio: plasma bands + guarded engine FFT bins 1-4 ----------------
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    var fftPulse = 0.0;
    if (arrayLength(&extraBuffer) > 9u) {
        fftPulse = (extraBuffer[6] + extraBuffer[7] + extraBuffer[8] + extraBuffer[9]) * 0.25;
    }

    // ---- Live slider wiring (index order: Intensity / Speed / Scale / Mouse Influence)
    let intensity = mix(0.35, 1.7, clamp(u.zoom_params.x, 0.0, 1.0));   // emission + glow gain
    let speed = mix(0.15, 2.4, clamp(u.zoom_params.y, 0.0, 1.0));       // rotation/animation rate
    let scaleParam = clamp(u.zoom_params.z, 0.0, 1.0);

    var ctx: SceneCtx;
    ctx.animTime = time * speed;
    ctx.ringScale = mix(0.65, 1.45, scaleParam);                        // astrolabe radius scale
    ctx.detailFreq = mix(1.4, 3.2, scaleParam);                         // fluid noise LOD bias
    ctx.mouseWorld = (mouseUv * 2.0 - vec2<f32>(1.0)) * vec2<f32>(aspect, 1.0) * 2.6;
    ctx.mouseStrength = clamp(u.zoom_params.w, 0.0, 1.0) * 1.4;
    ctx.bass = bass;
    ctx.treble = treble;
    // ---- Camera ----------------------------------------------------------
    let uv = (vec2<f32>(gid.xy) * 2.0 - res) / res.y;
    let ro = vec3<f32>(0.0, 0.0, -8.0);
    let rd = normalize(vec3<f32>(uv, 1.5));

    // ---- Early out: analytic bounding sphere around the astrolabe --------
    let boundR = 3.05 * ctx.ringScale + 0.6;
    let tCa = -dot(ro, rd);
    let rayMiss = (tCa < 0.0) || (dot(ro, ro) - tCa * tCa > boundR * boundR);

    // ---- Raymarch (skipped for rays that miss the bounds) ---------------
    var t = 0.0;
    var matId = 0.0;
    var hit = false;
    if (!rayMiss) {
        for (var i = 0; i < MAX_STEPS; i = i + 1) {
            let p = ro + rd * t;
            let r = map(p, ctx);
            matId = r.y;
            if (r.x < SURF_DIST) {
                hit = true;
                break;
            }
            if (t > MAX_DIST) {
                break;
            }
            t += r.x * STEP_RELAX;
        }
    }

    // ---- Shading ----------------------------------------------------------
    var col = vec3<f32>(0.0);
    if (hit) {
        let p = ro + rd * t;
        let n = getNormal(p, ctx);
        let l = normalize(vec3<f32>(1.0, 2.0, -3.0));

        let diff = max(dot(n, l), 0.0);
        let viewDir = -rd;
        let spec = pow(max(dot(viewDir, reflect(-l, n)), 0.0), 32.0);

        if (matId < 1.5) { // Rings - iridescent liquid metal
            let baseCol = vec3<f32>(1.0, 0.8, 0.2); // warm gold
            let iridescence = vec3<f32>(0.0, 1.0, 1.0) * (0.5 + 0.5 * sin(p.x * 2.0 + time));
            col = mix(baseCol, iridescence, 0.5) * (diff + 0.2) * intensity + spec * intensity;
            // Idea 1: engraved graduations — dark groove, bright treble-glinting rim on major marks
            let grad = limbGraduation(p, round((matId - 1.0) * 10.0), ctx);
            col = col * (1.0 - grad.x * 0.6)
                + baseCol * grad.y * (0.25 + spec * 1.5 + treble * 0.8) * intensity;
        } else { // Core - holographic bloom
            col = (vec3<f32>(0.0, 1.0, 1.0) + vec3<f32>(1.0, 0.0, 1.0) * sin(time * 3.0))
                  * intensity * (1.0 + bass * 0.6);
        }
    } else {
        // Nebula dust interference (cheap single-octave, background only)
        let dustNoise = noise3D(vec3<f32>(uv * 10.0, time * 0.5));
        let dustIntensity = smoothstep(0.6, 1.0, dustNoise) * (1.0 + bass);
        // Idea 3: rete star-chart plate under the dust
        col += retePlate(uv, ctx, time, mids) * intensity;
        col += vec3<f32>(0.2, 0.4, 0.8) * dustIntensity * intensity * 0.6;
    }

    // Core glow halo (screen-space, scale-aware, FFT-pumped)
    let coreDist = length(uv / max(ctx.ringScale, 0.2));
    let glow = 0.05 / (coreDist * coreDist + 0.01) * intensity * (1.0 + fftPulse * 0.5);
    col += vec3<f32>(0.0, 0.5, 1.0) * glow;

    // Click shockwaves: bounded, finite-lived, spatially local
    var shock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    let uv01 = (vec2<f32>(gid.xy) + vec2<f32>(0.5)) / res;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.4) {
            let delta = (uv01 - ripple.xy) * vec2<f32>(aspect, 1.0);
            shock = max(shock, exp(-abs(length(delta) - age * 0.35) * 60.0) * exp(-age * 2.2));
        }
    }
    col += vec3<f32>(0.3, 0.9, 1.2) * shock * intensity;

    // ---- Temporal smoothing via display history (dataTextureC) -----------
    let prev = textureLoad(dataTextureC, pixel, 0);
    col = mix(max(col, vec3<f32>(0.0)), prev.rgb * 0.92, clamp(0.03 + mids * 0.01, 0.0, 0.06));

    // ---- HDR -> tone map, semantic alpha, generated relief depth ----------
    let tone = acesTone(col * 1.05);
    let alpha = clamp(select(0.05, 0.85, hit) + glow * 0.05 + shock * 0.25, 0.0, 0.97);
    let depth = select(0.0, clamp(1.0 - t / MAX_DIST, 0.0, 1.0), hit); // near-is-one
    let outColor = vec4<f32>(tone, alpha);

    textureStore(writeTexture, pixel, outColor);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, outColor);
}
