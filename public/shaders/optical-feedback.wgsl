// ═══════════════════════════════════════════════════════════════════
//  Optical Feedback Loop
//  Category: interactive-mouse
//  Features: upgraded-rgba, feedback, loop, infinite, mouse-driven,
//            temporal-persistence, audio-reactive, depth-aware,
//            domain-warp, hue-shift, semantic-alpha, gravity-well,
//            click-shockwave, spring-damper, emergent-feedback
//  Complexity: High
//  Upgraded: 2026-10-18
//  Ideas: multi-front ripple shockwaves; per-band spectral hue rotation; 9-point isotropic Laplacian Turing-edge restorer on feedback buffer (§12.2D 9-point Laplacian); Fabry-Perot optical cavity mirror interference fringes (§12.2F Thin-film interference)
//  A packing: ACES display RGBA (alpha = accumulated envelope/coverage)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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

// ── Idea 3: 9-Point Isotropic Laplacian Turing-Edge Restorer on Feedback Buffer (§12.2D 9-point Laplacian) ──
fn lap9Feedback(c: vec2<i32>, dims: vec2<i32>) -> vec3<f32> {
    let maxC = dims - vec2<i32>(1);
    let u0 = textureLoad(dataTextureC, clamp(c, vec2<i32>(0), maxC), 0).rgb;
    let ax = textureLoad(dataTextureC, clamp(c + vec2<i32>( 1,  0), vec2<i32>(0), maxC), 0).rgb +
             textureLoad(dataTextureC, clamp(c + vec2<i32>(-1,  0), vec2<i32>(0), maxC), 0).rgb +
             textureLoad(dataTextureC, clamp(c + vec2<i32>( 0,  1), vec2<i32>(0), maxC), 0).rgb +
             textureLoad(dataTextureC, clamp(c + vec2<i32>( 0, -1), vec2<i32>(0), maxC), 0).rgb;
    let dg = textureLoad(dataTextureC, clamp(c + vec2<i32>( 1,  1), vec2<i32>(0), maxC), 0).rgb +
             textureLoad(dataTextureC, clamp(c + vec2<i32>(-1,  1), vec2<i32>(0), maxC), 0).rgb +
             textureLoad(dataTextureC, clamp(c + vec2<i32>( 1, -1), vec2<i32>(0), maxC), 0).rgb +
             textureLoad(dataTextureC, clamp(c + vec2<i32>(-1, -1), vec2<i32>(0), maxC), 0).rgb;
    return 0.5 * ax + 0.25 * dg - 3.0 * u0;
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
    let ENGINE_DT = 0.016;
    let springRate = 14.0;
    let springK = 1.0 - exp(-springRate * ENGINE_DT);

    var smoothMouse = vec2<f32>(extraBuffer[SMOOTH_X], extraBuffer[SMOOTH_Y]);
    var huePhase = extraBuffer[HUE_PHASE];
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

    let dimsI = vec2<i32>(resolution);
    let feedbackSample = feedbackBilinear(sampleUV * resolution, dimsI);
    let lapRestorer = lap9Feedback(vec2<i32>(sampleUV * resolution), dimsI);
    let feedbackColor = clamp(feedbackSample.rgb * brightness - lapRestorer * (0.14 + treble * 0.1), vec3<f32>(0.0), vec3<f32>(4.0));

    // ---- Structure 2: per-band spectral hue rotation ----
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

    // ── Idea 4: Fabry-Perot Optical Cavity Mirror Interference Fringes (§12.2F Thin-film interference) ──
    let opticalPathDiff = ringT * 12.0 + dot(current.rgb - feedbackSample.rgb, vec3<f32>(1.2)) - time * 0.8;
    let finesse = 3.5 + zoomParam * 4.0;
    let fpPhase = vec3<f32>(opticalPathDiff, opticalPathDiff + 1.047, opticalPathDiff + 2.094);
    let sinFp = sin(fpPhase);
    let fabryPerot = vec3<f32>(1.0) / (vec3<f32>(1.0) + finesse * sinFp * sinFp);
    color = mix(color, color * (0.75 + 0.55 * fabryPerot), 0.28 * accumulationRate);

    color = mix(color, current.rgb, 0.08 + depth * 0.08);
    // ---- shockwave brightness injection ----
    color = color + vec3<f32>(0.15, 0.12, 0.25) * shock * (0.8 + treble);

    color = acesToneMap(color * (0.9 + env * 0.2));

    let finalResult = vec4<f32>(color, totalAlpha);
    textureStore(dataTextureA, coord, finalResult);
    textureStore(writeTexture, coord, finalResult);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
