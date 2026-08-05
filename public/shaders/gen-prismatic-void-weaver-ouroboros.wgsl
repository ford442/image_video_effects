// ----------------------------------------------------------------
// Prismatic Void-Weaver Ouroboros
// Category: generative
// Batch 36 (Optimizer): canonical uniform truth, coarse->refined SDF
// (fbm scales culled when far), bounding-sphere early out, tetrahedron
// normals (4 taps vs 6), spring-smoothed void well + bounded click
// surge, real audio + FFT reactivity, HDR + ACES, semantic alpha,
// generated hit depth, temporal history smoothing.
// ----------------------------------------------------------------

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
    config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active), .zw = resolution (width, height)
    zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
    zoom_params: vec4<f32>,  // .x = Twist Density, .y = Plasma Glow, .z = Void Gravity, .w = Audio Reactivity
    ripples: array<vec4<f32>, 50>, // .xy = ripple uv, .z = startTime (seconds), .w = padding
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ---- Raymarch budget (60fps @1080p) ------------------------------
const MAX_STEPS: i32 = 90;
const MAX_DIST: f32 = 50.0;
const SURF_DIST: f32 = 0.001;
const STEP_RELAX: f32 = 0.8;       // <1: twisted/displaced SDF is not Lipschitz-1
const MAX_STEP: f32 = 1.2;         // hard cap keeps far marching cheap
const TORUS_MAJOR: f32 = 2.5;
const TORUS_MINOR: f32 = 0.8;
const SCALE_AMP: f32 = 0.15;       // fractal scale displacement amplitude
// Torus farther than this coarse distance skips the 4-octave fbm:
// the scale displacement (<= ~0.53) can never matter out there.
const FBM_CULL_DIST: f32 = 1.6;

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
}

fn acesTone(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + vec3<f32>(0.03))) /
                 (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)),
                 vec3<f32>(0.0), vec3<f32>(1.0));
}

// 3D value noise for fractal scales
fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uu = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);

    let n = i.x + i.y * 157.0 + i.z * 113.0;

    return mix(
        mix(mix(fract(sin(n + 0.0) * 43758.5453123), fract(sin(n + 1.0) * 43758.5453123), uu.x),
            mix(fract(sin(n + 157.0) * 43758.5453123), fract(sin(n + 158.0) * 43758.5453123), uu.x), uu.y),
        mix(mix(fract(sin(n + 113.0) * 43758.5453123), fract(sin(n + 114.0) * 43758.5453123), uu.x),
            mix(fract(sin(n + 270.0) * 43758.5453123), fract(sin(n + 271.0) * 43758.5453123), uu.x), uu.y), uu.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i = i + 1) {
        f += amp * noise3(pos);
        pos = pos * 2.0;
        amp *= 0.5;
    }
    return f;
}

// Per-frame scene constants, built once in main and passed by value.
struct SceneCtx {
    time: f32,
    twist: f32,          // Twist Density slider (live in geometry)
    gravity: f32,        // Void Gravity slider + bounded click surge
    audioEnergy: f32,    // band energy * Audio Reactivity slider (clamped)
    voidCenter: vec3<f32>, // spring-smoothed cursor (screen-true, y down)
    fftShimmer: f32,     // guarded engine FFT bins 1-8 average
};

// useDetail=false is the cheap coarse field (no fbm).
fn sdfOuroboros(p_in: vec3<f32>, ctx: SceneCtx, useDetail: bool) -> f32 {
    var p = p_in;

    // Void gravity lensing: branchless, bounded, falls off as 1/d^2
    let toP = p - ctx.voidCenter;
    let distToVoid = max(length(toP), 0.001);
    let pull = min(ctx.gravity / (distToVoid * distToVoid + 0.1), 3.0);
    p -= (toP / distToVoid) * pull * 0.1;

    // Transform to torus cross-section space
    let angle = atan2(p.z, p.x);
    let tXy = vec2<f32>(length(p.xz) - TORUS_MAJOR, p.y);

    // Twist the cross section (Twist Density drives the geometry here)
    let rotM = rotate2D(angle * ctx.twist + ctx.time * 0.5);
    let q = rotM * tXy;

    // Base torus (coarse bound for the displaced surface)
    let baseSdf = length(tXy) - TORUS_MINOR;
    if (!useDetail) {
        return baseSdf;
    }

    // Fractal scales, evaluated in twisted space so the twist is visible
    let scaleDisp = fbm(vec3<f32>(q * 3.0, angle * 2.0) + vec3<f32>(ctx.time * 0.2)) * SCALE_AMP;
    return baseSdf - scaleDisp * (1.0 + ctx.audioEnergy);
}

// Coarse cull: only pay for the fbm scales when the ray is close enough.
fn mapScene(p: vec3<f32>, ctx: SceneCtx) -> f32 {
    let coarse = sdfOuroboros(p, ctx, false);
    if (coarse > FBM_CULL_DIST) {
        return coarse;
    }
    return sdfOuroboros(p, ctx, true);
}

// Tetrahedron normal: 4 taps instead of the classic 6.
fn getNormal(p: vec3<f32>, ctx: SceneCtx) -> vec3<f32> {
    let e = vec2<f32>(0.0015, -0.0015);
    return normalize(
        e.xyy * mapScene(p + e.xyy, ctx) +
        e.yyx * mapScene(p + e.yyx, ctx) +
        e.yxy * mapScene(p + e.yxy, ctx) +
        e.xxx * mapScene(p + e.xxx, ctx)
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let pixel = vec2<i32>(gid.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) {
        return;
    }

    let time = u.config.x;

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

    // ---- Audio: plasma bands * Audio Reactivity + guarded FFT bins 1-8 ----
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    var fftShimmer = 0.0;
    if (arrayLength(&extraBuffer) > 13u) {
        fftShimmer = (extraBuffer[6] + extraBuffer[7] + extraBuffer[8] + extraBuffer[9]
                    + extraBuffer[10] + extraBuffer[11] + extraBuffer[12] + extraBuffer[13]) * 0.125;
    }

    // ---- Live slider wiring (index order: Twist / Glow / Gravity / Audio) --
    var ctx: SceneCtx;
    ctx.time = time;
    ctx.twist = max(u.zoom_params.x, 0.0);                                  // 1..20 twists
    ctx.gravity = max(u.zoom_params.z, 0.0)
                  * (1.0 + step(0.5, u.zoom_config.w) * 0.8);               // bounded click surge
    ctx.audioEnergy = clamp((bass + mids + treble) * 0.3333, 0.0, 2.0)
                      * clamp(u.zoom_params.w, 0.0, 1.0);
    // y=0 is TOP in both mouse_uv and pixel space: no flip needed
    ctx.voidCenter = vec3<f32>((mouseUv * 2.0 - vec2<f32>(1.0)) * 2.0, 0.0);
    ctx.fftShimmer = fftShimmer;

    // ---- Camera (slow orbit) ----------------------------------------------
    let uv = (vec2<f32>(gid.xy) - 0.5 * res) / res.y;
    var ro = vec3<f32>(0.0, 0.0, -6.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    let camRot = rotate2D(time * 0.1);
    let roXz = camRot * vec2<f32>(ro.x, ro.z);
    ro.x = roXz.x;
    ro.z = roXz.y;
    let rdXz = camRot * vec2<f32>(rd.x, rd.z);
    rd.x = rdXz.x;
    rd.z = rdXz.y;

    // ---- Early out: analytic bounding sphere around the serpent -----------
    let boundR = TORUS_MAJOR + TORUS_MINOR + 1.4;
    let tCa = -dot(ro, rd);
    let rayMiss = (tCa < 0.0) || (dot(ro, ro) - tCa * tCa > boundR * boundR);

    // ---- Raymarch (skipped entirely for rays that miss the bounds) --------
    var dO = 0.0;
    var hit = false;
    if (!rayMiss) {
        for (var i = 0; i < MAX_STEPS; i = i + 1) {
            let p = ro + rd * dO;
            let dS = mapScene(p, ctx);
            if (dS < SURF_DIST) {
                hit = true;
                break;
            }
            if (dO > MAX_DIST) {
                break;
            }
            dO += min(dS * STEP_RELAX, MAX_STEP);
        }
    }

    // ---- Shading -----------------------------------------------------------
    var col = vec3<f32>(0.0);

    // Background / void glow (always evaluated: cheap exponential)
    let distToVoidBg = length(ro + rd * min(dO, 20.0) - ctx.voidCenter);
    let voidGlow = exp(-distToVoidBg * 0.5) * vec3<f32>(0.5, 0.1, 0.8) * u.zoom_params.y;

    if (hit) {
        let p = ro + rd * dO;
        let n = getNormal(p, ctx);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));

        let diff = max(dot(n, l), 0.0);
        let viewDir = normalize(ro - p);
        let spec = pow(max(dot(viewDir, reflect(-l, n)), 0.0), 32.0);

        // Chromatic dispersion color
        let matCol = vec3<f32>(
            0.5 + 0.5 * sin(time + p.x * 2.0 + 0.0),
            0.5 + 0.5 * sin(time + p.y * 2.0 + 2.0),
            0.5 + 0.5 * sin(time + p.z * 2.0 + 4.0)
        ) * 0.8 + vec3<f32>(0.2);

        // Dark matter core darkening
        let darkMatter = clamp(length(p.xz) - 1.5, 0.0, 1.0);

        col = matCol * diff * darkMatter + spec * vec3<f32>(0.8, 0.9, 1.0);

        // Plasma aura (band energy drives scale emission, FFT adds shimmer)
        let emission = clamp(fbm(p * 5.0 - vec3<f32>(time)), 0.0, 1.0)
                       * u.zoom_params.y * (1.0 + ctx.audioEnergy + ctx.fftShimmer * 0.5);
        col += matCol * emission * vec3<f32>(1.5, 0.5, 2.0);

        // Distance fog
        col = mix(col, vec3<f32>(0.02, 0.0, 0.05), 1.0 - exp(-0.02 * dO * dO));
    }

    col += voidGlow;

    // ---- Temporal smoothing via display history (dataTextureC) -------------
    let prev = textureLoad(dataTextureC, pixel, 0);
    col = mix(max(col, vec3<f32>(0.0)), prev.rgb * 0.92, clamp(0.03 + mids * 0.01, 0.0, 0.06));

    // ---- HDR -> tone map, semantic alpha, generated hit depth --------------
    let tone = acesTone(col * 1.05);
    let glowLuma = dot(voidGlow, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(select(0.05, 0.88, hit) + glowLuma * 0.15, 0.0, 0.97);
    let depth = select(0.0, clamp(1.0 - dO / MAX_DIST, 0.0, 1.0), hit); // near-is-one
    let outColor = vec4<f32>(tone, alpha);

    textureStore(writeTexture, pixel, outColor);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, outColor);
}
