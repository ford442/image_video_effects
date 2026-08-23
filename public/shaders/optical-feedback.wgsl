// ═══════════════════════════════════════════════════════════════════
//  Optical Feedback Loop
//  Category: interactive-mouse
//  Features: upgraded-rgba, feedback, loop, infinite, mouse-driven,
//            temporal-persistence, audio-reactive, depth-aware,
//            domain-warp, hue-shift, semantic-alpha, gravity-well,
//            click-shockwave, spring-damper, emergent-feedback
//  Complexity: High
//  Upgraded: 2026-08-23 (Batch 64)
//
//  TWO BUGS FIXED IN THIS PASS
//
//  1. Ripple count used as delta time. The shader had
//
//         let dt = u.config.y;
//         velocity = velocity + accel * dt;
//         smoothMouse = smoothMouse + velocity * dt;
//
//     `config.y` is the RIPPLE COUNT, not a per-frame dt — no dt is uploaded on
//     either backend (docs/BINDING_CONTRACT.md, do-not-reintroduce list). With
//     no clicks alive `dt == 0`, so the spring never moved and the hue phase
//     never advanced: the "spring-damper" and "hue-shift" features were frozen
//     solid. With clicks alive it jumped to 1..50, and a stiff spring (k = 55)
//     integrated at dt = 50 diverges instantly. The spring is now a
//     frame-rate-corrected exponential tracker driven by the fixed engine step,
//     which needs no velocity state at all.
//
//  2. State written into the engine's audio slots. Nine values were stored at
//     `extraBuffer[0..8]` — which per the binding contract are bass, mid,
//     treble, reserved, `historyHead`, and FFT bins 5-8. This shader was
//     overwriting the audio EVERY OTHER SHADER IN THE CHAIN reads, and reading
//     back values the engine rewrites each frame, so its own state was garbage
//     too. The extraBuffer audit carried these as nine grandfathered baseline
//     violations.
//
//     The state also did not need nine slots: `clickTime`/`clickPos` duplicate
//     what `u.ripples[i]` already provides (`.xy` = click uv, `.z` = click
//     time), and `prevPress` existed only to detect the press edge the ripple
//     queue already detects. Dropping those four plus the two velocity slots
//     leaves smoothed pointer xy + hue phase, now at `extraBuffer[133..135]` —
//     inside the engine's scratch range — and written only by invocation (0,0)
//     instead of racing across every pixel.
//
//  TWO NEW STRUCTURES
//
//    1. Multi-front ripple shockwaves — the feedback loop was disturbed by a
//       single hand-tracked click at a time. It now integrates every live
//       ripple (capped at 50) as its own expanding front, so overlapping clicks
//       build interference in the feedback rather than replacing each other.
//
//    2. Per-band spectral hue rotation — the hue shift was one global phase.
//       Each of the eight FFT bins now rotates its own radial zone of the
//       frame, so the feedback tunnel separates into spectral rings.
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
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// Persistent state lives in the engine's scratch range [133..138]. Indices
// 0..132 are ENGINE-OWNED (bass/mid/treble, historyHead, FFT bins) and must
// never be written from a shader — see the header.
const SMOOTH_X: i32 = 133;
const SMOOTH_Y: i32 = 134;
const HUE_PHASE: i32 = 135;

fn feedbackBilinear(p: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
    let maxC = dims - vec2<i32>(1);
    let f = fract(p);
    let i0 = vec2<i32>(floor(p));
    let s00 = textureLoad(dataTextureC, clamp(i0,                     vec2<i32>(0), maxC), 0);
    let s10 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 0), vec2<i32>(0), maxC), 0);
    let s01 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(0, 1), vec2<i32>(0), maxC), 0);
    let s11 = textureLoad(dataTextureC, clamp(i0 + vec2<i32>(1, 1), vec2<i32>(0), maxC), 0);
    return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
}
fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
    return p + strength * q;
}
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    return mix(prev, bass, select(release, attack, bass > prev));
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn rgb2hsv(rgb: vec3<f32>) -> vec3<f32> {
    let mx = max(max(rgb.r, rgb.g), rgb.b);
    let mn = min(min(rgb.r, rgb.g), rgb.b);
    let d = mx - mn;
    var h = 0.0;
    if d > 0.0 {
        if mx == rgb.r { h = (rgb.g - rgb.b) / d + select(0.0, 6.0, rgb.g < rgb.b); }
        else if mx == rgb.g { h = (rgb.b - rgb.r) / d + 2.0; }
        else { h = (rgb.r - rgb.g) / d + 4.0; }
        h /= 6.0;
    }
    return vec3<f32>(h, select(0.0, d / mx, mx > 0.0), mx);
}
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let c = hsv.z * hsv.y;
    let h = hsv.x * 6.0;
    let x = c * (1.0 - abs(fract(h / 2.0) * 2.0 - 1.0));
    let m = hsv.z - c;
    var rgb: vec3<f32>;
    if h < 1.0 { rgb = vec3<f32>(c, x, 0.0); }
    else if h < 2.0 { rgb = vec3<f32>(x, c, 0.0); }
    else if h < 3.0 { rgb = vec3<f32>(0.0, c, x); }
    else if h < 4.0 { rgb = vec3<f32>(0.0, x, c); }
    else if h < 5.0 { rgb = vec3<f32>(x, 0.0, c); }
    else { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(m);
}
fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
    let len = length(v);
    return select(v / len, vec2<f32>(0.0), len < 0.0001);
}
fn shockwave(uv: vec2<f32>, clickPos: vec2<f32>, age: f32) -> vec2<f32> {
    let radius = age * 0.5;
    let delta = uv - clickPos;
    let dRing = length(delta);
    let arg = (dRing - radius) * 12.0;
    let ring = exp(-arg * arg);
    let strength = ring * (1.0 - age * 0.8) * 0.07;
    return safeNormalize(delta) * strength;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let accumulationRate = clamp(u.zoom_params.x, 0.0, 1.0);
    let zoomParam = u.zoom_params.y;
    let rotationParam = u.zoom_params.z;
    let hueShiftParam = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let prev = textureLoad(dataTextureC, coord, 0);
    let env = bass_env(prev.a, bass, 0.8, 0.15);
    // ---- persistent interactive state (scratch range only, (0,0) writes) ----
    // Critically-damped exponential tracker with a frame-rate-correct factor;
    // no velocity slots needed, and no bogus dt (see header).
    let ENGINE_DT = 0.016;
    let springRate = 14.0;
    let springK = 1.0 - exp(-springRate * ENGINE_DT);

    var smoothMouse = vec2<f32>(extraBuffer[SMOOTH_X], extraBuffer[SMOOTH_Y]);
    var huePhase = extraBuffer[HUE_PHASE];
    // Cold start: a zeroed buffer snaps to the live cursor rather than crawling
    // out of the corner.
    if (smoothMouse.x == 0.0 && smoothMouse.y == 0.0) { smoothMouse = mouse; }
    smoothMouse = smoothMouse + (mouse - smoothMouse) * springK;
    huePhase = fract(huePhase + (env * 0.02 + mouseDown * 0.04) * ENGINE_DT * 60.0);

    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[SMOOTH_X] = smoothMouse.x;
        extraBuffer[SMOOTH_Y] = smoothMouse.y;
        extraBuffer[HUE_PHASE] = huePhase;
    }

    let zoom = zoomParam * 0.03 * (1.0 + env * 0.6);
    let rotation = rotationParam * 0.12 + mouseDown * 0.03 * sin(time * 4.0) + mids * 0.02;
    let brightness = 1.0 + accumulationRate * 1.2;

    let current = textureLoad(readTexture, coord, 0);
    // ---- feedback centre blends instantaneous and spring-damped mouse ----
    let lagCenter = mix(vec2<f32>(0.5), smoothMouse, 0.5 + mouseDown * 0.25);
    let instantCenter = mix(vec2<f32>(0.5), mouse, 0.5 + mouseDown * 0.25);
    let center = mix(instantCenter, lagCenter, 0.5);

    let centered = uv - center;
    let c = cos(rotation);
    let s = sin(rotation);
    let rotated = vec2<f32>(centered.x * c - centered.y * s, centered.x * s + centered.y * c);
    let scaled = rotated * (1.0 - zoom) + center;

    let warp = domainWarp(scaled * 4.0 + vec2<f32>(time * 0.03), 0.04 + treble * 0.04, 3);
    var sampleUV = clamp(scaled + (warp - scaled) * 0.15, vec2<f32>(0.0), vec2<f32>(1.0));
    // ---- mouse gravity well pulls feedback samples toward the cursor ----
    let toMouse = mouse - sampleUV;
    let gravityStrength = smoothstep(0.6, 0.0, length(toMouse)) * (0.025 + env * 0.02);
    sampleUV = sampleUV + toMouse * gravityStrength;
    sampleUV = clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0));
    // ---- Structure 1: every live ripple is its own shockwave front ----
    // Previously only one hand-tracked click could disturb the loop at a time;
    // overlapping clicks now build real interference in the feedback.
    var shock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age < 0.0 || age >= 1.25) { continue; }
        sampleUV = clamp(sampleUV + shockwave(sampleUV, rp.xy, age) * (1.0 + env),
                         vec2<f32>(0.0), vec2<f32>(1.0));
        let radius = age * 0.5;
        let dRing = length(uv - rp.xy);
        let arg = (dRing - radius) * 12.0;
        shock += exp(-arg * arg) * (1.0 - age * 0.8) * 1.2;
    }
    shock = min(shock, 2.0);
    // ---- emergent feedback: previous frame energy warps the read coordinate ----
    let feedbackEnergy = length(prev.rgb);
    sampleUV = sampleUV + safeNormalize(sampleUV - center) * feedbackEnergy * 0.01 * (1.0 + mids);
    sampleUV = clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0));

    // Exact float32 fetch with hand-rolled bilinear — dataTextureC is rgba32float
    // and `float32-filterable` is only requested when the adapter offers it
    // (src/renderer/webgpu/device.ts), so the filtering sampler is unsafe here.
    let feedbackSample = feedbackBilinear(sampleUV * resolution, vec2<i32>(resolution));
    let feedbackColor = feedbackSample.rgb * brightness;

    // ---- Structure 2: per-band spectral hue rotation ----
    // Each FFT bin owns a radial zone of the tunnel, so the feedback separates
    // into spectral rings instead of rotating under one global phase.
    let ringT = clamp(length(uv - center) * 1.9, 0.0, 0.999);
    let bandIdx = u32(ringT * 8.0);
    let bandEnergy = plasmaBuffer[bandIdx + 1u].x;
    let bandPhase = bandEnergy * 0.22 + f32(bandIdx) * 0.035;

    let hsv = rgb2hsv(feedbackColor);
    let shifted = hsv2rgb(vec3<f32>(
        fract(hsv.x + hueShiftParam * 0.2 + env * 0.05 + huePhase + bandPhase),
        clamp(hsv.y * (1.0 + bandEnergy * 0.35), 0.0, 1.0),
        hsv.z));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let fog = 1.0 - exp(-depth * 1.5);
    let depthFade = 1.0 - fog * 0.5;

    let accumulatedAlpha = prev.a * (1.0 - accumulationRate * 0.08) + feedbackSample.a * accumulationRate;
    let totalAlpha = min(accumulatedAlpha * depthFade, 1.0);
    let blendFactor = select(feedbackSample.a * accumulationRate / totalAlpha, 0.0, totalAlpha < 0.001);
    var color = mix(prev.rgb, shifted, blendFactor);

    color = mix(color, current.rgb, 0.08 + depth * 0.08);
    // ---- shockwave brightness injection ----
    color = color + vec3<f32>(0.15, 0.12, 0.25) * shock * (0.8 + treble);

    color = acesToneMap(color * (0.9 + env * 0.2));

    let finalResult = vec4<f32>(color, totalAlpha);
    textureStore(dataTextureA, coord, finalResult);
    textureStore(writeTexture, coord, finalResult);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
