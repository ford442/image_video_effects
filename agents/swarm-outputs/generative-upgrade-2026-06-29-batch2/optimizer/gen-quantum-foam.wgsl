// ═══════════════════════════════════════════════════════════════════
//  Quantum Foam — Optimized Upgrade
//  Category: generative
//  Features: audio-reactive, lod-scaling, blue-noise-jitter,
//            bilinear-temporal-feedback, hdr-chaining, depth-aware
//  Complexity: Medium
//  Upgraded: 2026-06-29
//
//  Performance-first refactor of the Worley-noise quantum vacuum.
//  - 3x3 branchless Worley kernel (was 5x5): mathematically sufficient
//    for jittered cell points and ~2.8x cheaper per octave.
//  - Frame-budget-aware LOD: Detail slider drives octave count; delta
//    time throttles layers when the GPU is struggling.
//  - Blue-noise sub-pixel jitter (interleaved-gradient noise) replaces
//    bare hash dither, giving smoother bubbles with fewer samples.
//  - Bilinear sampling of dataTextureC for cheap temporal trails.
//  - HDR-ready slot chaining: writeTexture gets tonemapped display,
//    dataTextureA keeps linear HDR for downstream passes, dataTextureB
//    packs depth/luma/flash/border for compositing.
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
  config: vec4<f32>,       // .x = time, .y = delta_time, .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = zoom, .yz = mouse_uv (0-1), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .xyzw = user params p1…p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = time_created, .w = strength
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Tunable constants ─────────────────────────────────────────────
const FOAM_DENSITY_MIN: f32 = 1.5;
const FOAM_DENSITY_MAX: f32 = 8.0;
const BUBBLE_MIN: f32 = 0.4;
const BUBBLE_MAX: f32 = 1.8;
const CHROMA_MIN: f32 = 0.1;
const CHROMA_MAX: f32 = 1.0;
const JITTER_AMP: f32 = 0.035;
const CA_STRENGTH: f32 = 0.025;
const DECAY_BASE: f32 = 0.94;
const MAX_LAYERS: i32 = 4;
const MIN_LAYERS: i32 = 1;
const FRAME_BUDGET_S: f32 = 0.020;        // 20 ms @ 50-60 fps
const NEIGHBOR_COUNT: i32 = 9;

// ── Core math / noise ─────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}

// Interleaved gradient noise — compute-safe blue-noise-style jitter.
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ── ACES tone map (canonical) ─────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Worley (cellular) noise — 3x3 branchless kernel ───────────────
// A 3x3 neighborhood is sufficient for cell points jittered inside
// [0,1]^2; the nearest feature point is always in an adjacent cell.
fn worley(p: vec2<f32>) -> vec2<f32> {
    let ip = floor(p);
    let fp = fract(p);
    var d1 = 8.0;
    var d2 = 8.0;

    for (var dy: i32 = -1; dy <= 1; dy = dy + 1) {
        for (var dx: i32 = -1; dx <= 1; dx = dx + 1) {
            let cell = ip + vec2<f32>(f32(dx), f32(dy));
            let jitter = hash22(cell);
            let off = vec2<f32>(f32(dx), f32(dy)) + jitter - fp;
            let d = dot(off, off);

            let nearer = step(d, d1);
            d2 = mix(d2, d1, nearer);
            d1 = mix(d1, d, nearer);

            let second = step(d, d2) * (1.0 - nearer);
            d2 = mix(d2, d, second);
        }
    }
    return sqrt(vec2<f32>(d1, d2));
}

// ── Layered Worley FBM — octave count driven by LOD ───────────────
fn foamField(p: vec2<f32>, t: f32, layers: i32) -> f32 {
    var accum: f32 = 0.0;
    var amp: f32 = 0.5;
    var freq: f32 = 1.0;
    var motion: vec2<f32> = vec2<f32>(t * 0.07, t * 0.05);

    for (var i: i32 = 0; i < layers; i = i + 1) {
        let w = worley(p * freq + motion);
        accum += amp * (w.y - w.x);
        freq *= 2.1;
        amp *= 0.5;
        motion = motion.yx * 0.93 + vec2<f32>(0.11, -0.07) * f32(i);
    }
    return accum;
}

// ── Chromatic offset for generative shaders ───────────────────────
fn foamChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(
        color.r * (1.0 + shift.x * 0.8),
        color.g,
        color.b * (1.0 - shift.y * 0.5)
    );
}

// ═══════════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01  = vec2<f32>(pixel) / res;
    let uv    = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time  = u.config.x;
    let dt    = u.config.y;
    let zoom  = max(u.zoom_config.x, 0.1);
    let mouse = u.zoom_config.yz;

    let p1 = u.zoom_params.x; // Density
    let p2 = u.zoom_params.y; // Bubble Size
    let p3 = u.zoom_params.z; // Chroma
    let p4 = u.zoom_params.w; // Detail / LOD
    let detail = clamp(p4, 0.0, 1.0);

    // ── Audio read (canonical) ────────────────────────────────────
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Depth & temporal read ─────────────────────────────────────
    let depthIn = textureLoad(readDepthTexture, pixel, 0).r;
    let prevHDR = textureSampleLevel(
        dataTextureC, u_sampler,
        clamp(uv01, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0
    ).rgb;

    // ── LOD scaling: user Detail + frame-budget throttle ──────────
    let baseLayers = i32(round(mix(2.0, f32(MAX_LAYERS), detail)));
    let budgetOk   = step(dt, FRAME_BUDGET_S);          // 1.0 if under budget
    let layers     = clamp(baseLayers - i32(1.0 - budgetOk), MIN_LAYERS, MAX_LAYERS);

    // ── Parameter mapping ─────────────────────────────────────────
    let density    = mix(FOAM_DENSITY_MIN, FOAM_DENSITY_MAX, p1) * (1.0 + bass * 0.25);
    let bubbleSize = mix(BUBBLE_MIN, BUBBLE_MAX, p2);
    let chroma     = mix(CHROMA_MIN, CHROMA_MAX, p3);
    let speed      = mix(0.05, 0.35, detail);
    let t          = time * speed;

    // ── World-space sample position ───────────────────────────────
    let aspect = res.x / max(res.y, 1.0);
    var p = uv * vec2<f32>(aspect, 1.0) * density;
    p += (mouse - vec2<f32>(0.5)) * 0.35;   // mouse drift
    p *= zoom;

    // Blue-noise sub-pixel jitter (reduces structured banding).
    let bn = ign(vec2<f32>(pixel));
    p += (bn - 0.5) * JITTER_AMP * mix(0.5, 1.0, detail);

    // ── Foam evaluation ───────────────────────────────────────────
    let f0 = foamField(p * bubbleSize, t, layers);
    let f1 = foamField(p * bubbleSize + vec2<f32>(3.7, 1.3), t + 0.5, layers);
    let f2 = foamField(p * bubbleSize + vec2<f32>(-1.7, 4.1), t + 1.0, layers);

    // ── Spectral color mapping ────────────────────────────────────
    let r = smoothstep(0.0, 0.5, f0) * (0.6 + chroma * 0.4 + treble * 0.15);
    let g = smoothstep(0.0, 0.5, f1) * (0.5 + chroma * 0.3 + mids   * 0.15);
    let b = smoothstep(0.0, 0.5, f2) * (0.7 + chroma * 0.5 + bass   * 0.20);
    var hdr = vec3<f32>(r, g, b);

    // Thin cell borders (audio-reactive on treble).
    let border0 = exp(-f0 * 20.0) * 1.5;
    let border1 = exp(-f1 * 20.0) * 1.2;
    hdr += vec3<f32>(border0 * 0.3, border1 * 0.2, border0 * 0.4) * (1.0 + treble * 0.5);

    // Vacuum background mix.
    let vacuumHue = fract(time * 0.03 + mids * 0.1);
    let vacuum = vec3<f32>(
        0.02 + 0.05 * cos(TAU * vacuumHue),
        0.02 + 0.05 * cos(TAU * (vacuumHue + 0.33)),
        0.05 + 0.08 * cos(TAU * (vacuumHue + 0.67))
    );
    let foamSum = f0 + f1 + f2;
    hdr = mix(vacuum, hdr, smoothstep(0.05, 0.3, foamSum));

    // Bass transient flash.
    let flash = smoothstep(0.6, 1.0, bass) * hash21(uv * 1000.0 + vec2<f32>(time)) * 0.3;
    hdr += flash;

    // Depth-aware dimming for compositing.
    hdr *= 1.0 - depthIn * 0.3;

    // Generative chromatic aberration.
    let caStr = CA_STRENGTH * chroma * (1.0 + bass);
    hdr = foamChromaticShift(hdr, uv01, caStr);

    // ── Temporal feedback (bilinear LOD from dataTextureC) ────────
    let blend = 0.12 + bass * 0.08;
    let decay = DECAY_BASE - detail * 0.03;
    let hdrTrail = mix(prevHDR * decay, hdr, blend);

    // ── Display output (tonemapped) ───────────────────────────────
    let display = acesToneMap(hdrTrail * 1.1);
    let lum     = luma(display);
    let alpha   = clamp(lum * 1.2 + border0 * 0.06, 0.1, 0.92) * (0.75 + depthIn * 0.25);

    // Depth buffer: foam density maps to pseudo-depth.
    let depth = clamp(foamSum * 0.22 + 0.25, 0.0, 1.0);

    // ── Slot chaining ─────────────────────────────────────────────
    // writeTexture: final display-ready RGBA (tonemapped, semantic alpha).
    textureStore(writeTexture, pixel, vec4<f32>(display, alpha));

    // writeDepthTexture: per-pixel depth for downstream DOF/depth blend.
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // dataTextureA: linear HDR trail for next-frame feedback / HDR chaining.
    textureStore(dataTextureA, pixel, vec4<f32>(hdrTrail, alpha));

    // dataTextureB: packed auxiliaries for compositing / post passes.
    // .x = depth, .y = luma, .z = flash, .w = border mask.
    let borderMask = clamp(border0 + border1, 0.0, 1.0);
    textureStore(dataTextureB, pixel, vec4<f32>(depth, lum, flash, borderMask));
}
