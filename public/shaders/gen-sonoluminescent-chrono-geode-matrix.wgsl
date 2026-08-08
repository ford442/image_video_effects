// ----------------------------------------------------------------
// Sonoluminescent Chrono-Geode Matrix
// Category: generative
// Batch 38 (Algorithmist): FAST MOTION upgrade —
//   * closed-form high-speed orbital camera + eased time-warp spin
//     (frame-rate independent, sub-frame stable, no hash strobing)
//   * sonoluminescent flash-burst physics: closed-form bubble-collapse
//     cycle (exp-collapse core radius + exp-decay flash envelope +
//     ballistic expanding shockwave shell)
//   * bass-transient kick detection (rising-edge, dt-integrated in
//     extraBuffer[133..135]) that pumps flash amplitude + fracture
//   * velocity-advected motion-blur trails via dataTextureC feedback
//     (swirl-advected, textureLoad only, HDR history clamped <= 5.0)
//   * uniform-truth rewrite (config = [time, rippleCount, resW, resH]),
//     plasmaBuffer audio, real generated depth, semantic alpha, ACES.
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
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

const MAX_STEPS: i32 = 90;
const MAX_DIST: f32 = 16.0;
const SURF_DIST: f32 = 0.0015;
const HDR_CLAMP: f32 = 5.0;     // feedback energy bound (Batch 36 lesson)

// 3D rotation helper (axis-angle)
fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let a = normalize(axis);
    let s = sin(angle);
    let c = cos(angle);
    let oc = 1.0 - c;
    return mat3x3<f32>(
        oc * a.x * a.x + c,           oc * a.x * a.y - a.z * s,  oc * a.z * a.x + a.y * s,
        oc * a.x * a.y + a.z * s,     oc * a.y * a.y + c,        oc * a.y * a.z - a.x * s,
        oc * a.z * a.x - a.y * s,     oc * a.y * a.z + a.x * s,  oc * a.z * a.z + c
    );
}

fn acesTone(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + vec3<f32>(0.03))) /
                 (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)),
                 vec3<f32>(0.0), vec3<f32>(1.0));
}

// 3D Value Noise (kept from original — smooth, temporal-coherent)
fn vnoise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    let n = p.x + p.y * 157.0 + 113.0 * p.z;
    return mix(
        mix(mix(fract(sin(n + 0.0) * 43758.5453), fract(sin(n + 1.0) * 43758.5453), f2.x),
            mix(fract(sin(n + 157.0) * 43758.5453), fract(sin(n + 158.0) * 43758.5453), f2.x), f2.y),
        mix(mix(fract(sin(n + 113.0) * 43758.5453), fract(sin(n + 114.0) * 43758.5453), f2.x),
            mix(fract(sin(n + 270.0) * 43758.5453), fract(sin(n + 271.0) * 43758.5453), f2.x), f2.y), f2.z);
}

// SDF for geode shell (kept fractal fold from original)
fn sdGeodeShell(p: vec3<f32>, scale: f32) -> f32 {
    var q = p;
    let s = 2.0;
    for (var i = 0; i < 4; i = i + 1) {
        q = abs(q) - vec3<f32>(0.5) * scale;
        let rot = rot3D(normalize(vec3<f32>(1.0, 1.0, 1.0)), 0.5);
        q = rot * q;
        q = q * s;
    }
    return (length(q) - 1.0 * scale) / pow(s, 4.0);
}

// Per-frame scene constants (built once in main, passed by value)
struct SceneCtx {
    animTime: f32,       // time * Speed slider
    warpTime: f32,       // eased time-warp (fast-in / smooth-out rotation)
    flashPhase: f32,     // 0..1 position in the sonoluminescent cycle
    flash: f32,          // bounded flash envelope (collapse brightness)
    coreR: f32,          // animated bubble radius (collapses each cycle)
    ringR: f32,          // ballistic shockwave shell radius
    geodeScale: f32,     // Scale slider
    fractureAmp: f32,    // Intensity slider * audio energy
    mouseWorld: vec3<f32>, // cursor in world units (z = 0 plane)
    mouseForce: f32,     // Mouse Influence slider (0 while not pressed)
    kick: f32,           // bass-transient burst energy (bounded)
};

fn map(p: vec3<f32>, ctx: SceneCtx) -> vec2<f32> {
    // Eased time-warp rotation (fast spin with smooth non-uniform easing)
    let rotY = rot3D(vec3<f32>(0.0, 1.0, 0.0), ctx.warpTime * 1.6);
    let rotX = rot3D(normalize(vec3<f32>(1.0, 0.3, 0.2)), ctx.warpTime * 0.9);
    let p_rot = rotX * (rotY * p);

    // Mouse interaction (press repels shards) — uniform-truth mouse
    var explode_offset = vec3<f32>(0.0);
    if (ctx.mouseForce > 0.001) {
        let toMouse = p - ctx.mouseWorld;
        let dist = length(toMouse);
        let force = exp(-dist * 2.0) * ctx.mouseForce;
        explode_offset = normalize(toMouse + vec3<f32>(0.0001)) * force;
    }

    // Scale slider zooms the geode domain (SDF-correct scaling)
    let sp = p_rot / ctx.geodeScale;

    // Audio fracture: smooth value noise scrolled FAST in time (temporal-
    // coherent, no per-frame hash strobing) + high-frequency flutter layer
    let t = ctx.animTime;
    let fracture = ctx.fractureAmp * (
        vnoise3(sp * 5.0 + vec3<f32>(t * 1.5)) +
        0.35 * vnoise3(sp * 11.0 - vec3<f32>(0.0, t * 4.0, t * 2.0))
    );
    let explode = explode_offset + normalize(sp + vec3<f32>(0.0001)) * fracture * 0.35;

    let geode_dist = max(sdGeodeShell(sp - explode, 1.5), length(sp) - 1.0) * ctx.geodeScale;

    // Sonoluminescent bubble core: radius collapses each flash cycle,
    // surface churns at high speed with smooth noise
    let core_noise = vnoise3(p * 3.0 - vec3<f32>(0.0, t * 3.0, 0.0));
    let core_dist = length(p) - ctx.coreR + core_noise * (0.22 + 0.12 * ctx.flash);

    if (geode_dist < core_dist) {
        return vec2<f32>(geode_dist, 1.0); // 1.0 = geode material
    } else {
        return vec2<f32>(core_dist, 2.0); // 2.0 = core material
    }
}

fn calcNormal(p: vec3<f32>, ctx: SceneCtx) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.0005;
    return normalize(
        e.xyy * map(p + e.xyy, ctx).x +
        e.yyx * map(p + e.yyx, ctx).x +
        e.yxy * map(p + e.yxy, ctx).x +
        e.xxx * map(p + e.xxx, ctx).x
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let pixel = vec2<i32>(id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) {
        return;
    }

    let time = u.config.x;
    let aspect = res.x / max(res.y, 1.0);

    // ---- Audio: plasma bands + guarded engine FFT bins 1-4 ----------------
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    var fftPulse = 0.0;
    if (arrayLength(&extraBuffer) > 9u) {
        fftPulse = (extraBuffer[6] + extraBuffer[7] + extraBuffer[8] + extraBuffer[9]) * 0.25;
    }

    // ---- Bass-transient kick: rising-edge detect, dt-integrated decay ----
    // Persistent state ONLY in [133..135], single writer thread.
    if (id.x == 0u && id.y == 0u && arrayLength(&extraBuffer) > 135u) {
        let prevT = extraBuffer[134];
        let dt = clamp(time - prevT, 0.0, 0.1); // frame-rate independent
        let prevBass = extraBuffer[133];
        var kickE = extraBuffer[135] * exp(-dt * 5.0);
        let rising = max(bass - prevBass, 0.0);
        kickE = min(kickE + rising * 2.5, 2.0); // bounded burst energy
        extraBuffer[133] = bass;
        extraBuffer[134] = time;
        extraBuffer[135] = kickE;
    }
    var kick = 0.0;
    if (arrayLength(&extraBuffer) > 135u) {
        kick = extraBuffer[135];
    }

    // ---- Live slider wiring (Intensity / Speed / Scale / Mouse Influence)
    let intensity = mix(0.25, 1.6, clamp(u.zoom_params.x, 0.0, 1.0));
    let speedNorm = clamp(u.zoom_params.y, 0.0, 1.0);
    let rate = mix(0.35, 3.2, speedNorm);              // global fast-motion rate
    let geodeScale = mix(0.85, 1.4, clamp(u.zoom_params.z, 0.0, 1.0));
    let mouseUv = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;

    // ---- Closed-form fast motion (all analytic in time: fps-independent)
    let animTime = time * rate;
    // Time-warp easing: base advance + two smooth incommensurate modulations
    // (fast-in / smooth-out rotation; never strobes)
    let warpTime = animTime + 0.35 * sin(animTime * 0.83) + 0.09 * sin(animTime * 2.39);

    // Sonoluminescent flash-burst physics (closed-form bubble collapse):
    // each acoustic cycle the bubble implodes (exp envelope) then re-grows;
    // brightness spikes at collapse with bounded exponential decay.
    let flashRate = 0.8 + speedNorm * 1.2 + bass * 0.6;
    let flashPhase = fract(animTime * flashRate);
    let collapse = exp(-flashPhase * 7.0);
    let regrow = 1.0 - exp(-flashPhase * 4.0);

    var ctx: SceneCtx;
    ctx.animTime = animTime;
    ctx.warpTime = warpTime;
    ctx.flashPhase = flashPhase;
    ctx.flash = collapse * (0.5 + 0.9 * intensity) * (1.0 + kick * 1.5 + fftPulse * 0.5);
    ctx.coreR = (0.45 + 0.35 * regrow) * (0.9 + 0.2 * bass);
    ctx.ringR = flashPhase * (5.0 + kick * 3.0);       // ballistic shock shell
    ctx.geodeScale = geodeScale;
    ctx.fractureAmp = intensity * (0.25 + bass * 0.8 + kick * 0.6);
    ctx.mouseWorld = vec3<f32>((mouseUv.x - 0.5) * 2.0 * aspect, (mouseUv.y - 0.5) * 2.0, 0.0); // top-down mouse: screen top = -cv (world -y), so no y-flip
    ctx.mouseForce = select(0.0, mix(0.4, 3.0, clamp(u.zoom_params.w, 0.0, 1.0)), mouseDown);
    ctx.kick = kick;

    // ---- Camera: closed-form high-speed orbit with breathing radius ------
    let camA = warpTime * (0.5 + 0.4 * speedNorm);
    let camR = 3.6 + 0.5 * sin(warpTime * 0.41);
    let ro = vec3<f32>(sin(camA) * camR, 1.1 * sin(warpTime * 0.67 + 1.3), cos(camA) * camR);
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));
    let suv = (vec2<f32>(pixel) * 2.0 - res) / res.y;
    let rd = normalize(suv.x * cu + suv.y * cv + 1.5 * cw);

    // ---- Raymarch with volumetric plasma + shockwave-shell accumulation --
    var d0: f32 = 0.0;
    var mat_id: f32 = 0.0;
    var plasma_acc: f32 = 0.0;

    for (var i = 0; i < MAX_STEPS; i = i + 1) {
        let p_march = ro + rd * d0;
        let dS = map(p_march, ctx);

        if (dS.y == 2.0) {
            // Plasma accumulation, flash-pumped (bounded by flash envelope)
            plasma_acc = plasma_acc + (0.045 + 0.10 * ctx.flash) * exp(-max(dS.x, 0.0) * 5.0);
        }

        // Ballistic shockwave shell racing outward from each collapse
        let shellD = abs(length(p_march) - ctx.ringR);
        plasma_acc = plasma_acc + exp(-shellD * 4.0) * ctx.flash * 0.05;

        if (dS.x < SURF_DIST) {
            mat_id = dS.y;
            break;
        }
        d0 = d0 + max(dS.x, 0.002) * 0.55; // relaxed march for volumetrics
        if (d0 > MAX_DIST) {
            break;
        }
    }
    let hit = mat_id > 0.5 && d0 <= MAX_DIST;

    // ---- Shading ----------------------------------------------------------
    var col = vec3<f32>(0.0);
    if (hit && mat_id == 1.0) {
        // Geode material (iridescent, kept from original)
        let p_surf = ro + rd * d0;
        let n = calcNormal(p_surf, ctx);
        let l = normalize(vec3<f32>(1.0, 1.0, 2.0));

        let diff = max(dot(n, l), 0.0);
        let view_dir = normalize(-rd);
        let fresnel = pow(1.0 - max(dot(n, view_dir), 0.0), 3.0);

        // Iridescence: fast hue sweep driven by eased warp time
        let iridescence = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.0, 4.0) + fresnel * 5.0 + warpTime * 1.5);

        col = diff * vec3<f32>(0.2) + fresnel * iridescence * (0.6 + 0.6 * intensity);

        // Reflection of the plasma core, flash-boosted
        let r = reflect(rd, n);
        let core_refl = max(0.0, dot(r, normalize(vec3<f32>(0.0) - p_surf)));
        col = col + core_refl * vec3<f32>(0.2, 0.5, 1.0) * intensity * (0.6 + ctx.flash);
    }

    // Sonoluminescent flash glow (blue-white burst, HDR before tonemap)
    let core_glow_color = mix(vec3<f32>(0.1, 0.6, 1.0), vec3<f32>(0.7, 0.9, 1.2), clamp(ctx.flash, 0.0, 1.0));
    col = col + plasma_acc * core_glow_color * intensity * (0.5 + bass * 0.5 + ctx.flash);

    // Background (deep space with fast faint dust streaks)
    let bgDust = vnoise3(vec3<f32>(suv * 6.0, animTime * 2.0));
    var bg = vec3<f32>(0.01, 0.02, 0.05) + vec3<f32>(0.02, 0.05, 0.09) * smoothstep(0.65, 0.95, bgDust) * (0.5 + treble);
    bg += vec3<f32>(0.05, 0.15, 0.3) * ctx.flash * 0.25; // flash lights the void
    col = mix(bg, col, min(1.0, plasma_acc + select(0.0, 1.0, hit)));

    // ---- Velocity-advected motion-blur trails (feedback, textureLoad) ----
    // Screen-space swirl velocity of the spinning geode: tangential around
    // center, magnitude tracks the eased rotation rate. Clamped to +-4px.
    let uvC = (vec2<f32>(pixel) - res * 0.5) / res.y;
    let rotVel = (1.6 + 0.9 * speedNorm) * rate * 0.5;   // approx d(warp)/dt
    let swirl = vec2<f32>(-uvC.y, uvC.x) * rotVel * 60.0; // px/frame scale
    let advect = vec2<i32>(clamp(swirl, vec2<f32>(-4.0), vec2<f32>(4.0)));
    let prevPx = clamp(pixel - advect, vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
    let prev = textureLoad(dataTextureC, prevPx, 0);

    let decay = 0.86 - 0.05 * clamp(u.zoom_params.w, 0.0, 1.0); // Mouse Influence lengthens streaks
    var history = prev.rgb * decay + col * (0.35 + 0.25 * ctx.flash);
    history = clamp(history, vec3<f32>(0.0), vec3<f32>(HDR_CLAMP)); // energy bound

    // ---- HDR -> ACES, semantic alpha, real generated depth ----------------
    let tone = acesTone(history * 1.05);
    let alpha = clamp(select(0.06, 0.9, hit) + plasma_acc * 0.35 + ctx.flash * 0.1, 0.0, 0.97);
    let depth = select(clamp(plasma_acc * 0.15, 0.0, 0.25),
                       clamp(1.0 - d0 / MAX_DIST, 0.0, 1.0), hit); // near-is-one relief

    textureStore(writeTexture, pixel, vec4<f32>(tone, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(history, alpha));
}
