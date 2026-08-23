// ═══════════════════════════════════════════════════════════════════
//  Elastic Chromatic — Interactivist Upgrade
//  Category: distortion / visual-effects
//  Features: mouse-driven, depth-aware, audio-reactive, chromatic-aberration,
//            temporal-feedback, split-tone, blackbody-temperature, aces-tone-map,
//            ign-dither, premultiplied-alpha, alpha-layered, luminance-key,
//            accumulative-alpha, spring-damper-mouse, click-shockwave, iq-palette
//  Complexity: Medium
//  Upgrade: spring-damper elastic mouse lag (state in extraBuffer) so the
//           chromatic source overshoots and settles like a damped spring; click
//           shockwave ring boosts the chromatic split; IQ cosine palette tint
//           layered at low mix over the blackbody/split-tone grade.
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Elasticity, y=Damping, z=ShockwaveBoost, w=PaletteMix
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const MAX_LAG: f32 = 0.995;

// ── Color / tone helpers ───────────────────────────────────────────
fn srgbToLinear(c: vec3<f32>) -> vec3<f32> { return pow(c, vec3<f32>(2.2)); }
fn linearToSrgb(c: vec3<f32>) -> vec3<f32> { return pow(c, vec3<f32>(1.0 / 2.2)); }

fn luma(rgb: vec3<f32>) -> f32 { return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722)); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn huePreserveClamp(c: vec3<f32>, maxLum: f32) -> vec3<f32> {
    let L = luma(c);
    let s = min(1.0, maxLum / max(L, 1e-4));
    return c * s;
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 40000.0) / 100.0;
    var r = 1.0;
    var g = 0.0;
    var b = 1.0;
    if (t > 66.0) {
        r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0);
        g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0);
    } else {
        g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0);
        if (t <= 19.0) { b = 0.0; }
        else { b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0); }
    }
    return vec3<f32>(r, g, b);
}

// ── IQ cosine palette ──────────────────────────────────────────────
// a + b*cos(2π(c·t + d)) — classic Inigo Quilez cosine palette.
fn iqCosinePalette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5); let b = vec3<f32>(0.5);
    let c = vec3<f32>(1.0); let d = vec3<f32>(0.00, 0.33, 0.67);
    return a + b * cos(TAU * (c * t + d));
}

// ── Core elastic helpers ───────────────────────────────────────────
fn mouseInfluence(uv: vec2<f32>, mouse: vec2<f32>, aspect: f32, strength: f32) -> f32 {
    let d = distance((uv - mouse) * vec2<f32>(aspect, 1.0), vec2<f32>(0.0));
    return smoothstep(0.5, 0.0, d) * strength;
}

fn ema(current: f32, history: f32, lag: f32) -> f32 {
    return mix(current, history, lag);
}

fn chromaticAberration(uv: vec2<f32>, amount: f32) -> vec3<f32> {
    let center = vec2<f32>(0.5);
    let delta = uv - center;
    let lenSq = max(dot(delta, delta), 0.000001);
    let dir = delta * (1.0 / sqrt(lenSq));
    let offset = dir * max(amount, 0.0);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - offset * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    return vec3<f32>(r, g, b);
}

// ── Spring-damper integrator ───────────────────────────────────────
// Semi-implicit Euler; returns vec4(newPos.xy, newVel.xy). Underdamped
// settings overshoot on fast mouse moves, then settle like a real spring.
fn springStep(pos: vec2<f32>, vel: vec2<f32>, goal: vec2<f32>, stiffness: f32, dampCoef: f32, dt: f32) -> vec4<f32> {
    let accel = (goal - pos) * stiffness - vel * dampCoef;
    let newVel = vel + accel * dt;
    let newPos = pos + newVel * dt;
    return vec4<f32>(newPos, newVel);
}

// ── Click shockwave ring ───────────────────────────────────────────
// Expanding ring spawned on mouse-down; a thin bright band that fades
// with age and temporarily boosts the chromatic split as it passes.
fn shockwaveRing(uv: vec2<f32>, origin: vec2<f32>, aspect: f32, age: f32, boost: f32) -> f32 {
    if (age <= 0.0 || age > 3.0) { return 0.0; }
    let radius = age * 1.35;
    let d = distance((uv - origin) * vec2<f32>(aspect, 1.0), vec2<f32>(0.0));
    let off = d - radius;
    let band = exp(-off * off * 64.0);   // thin gaussian band
    let fade = exp(-age * 1.7);          // temporal decay
    return band * fade * max(boost, 0.0);
}

// ── Advanced alpha compositor ──────────────────────────────────────
fn composeAlpha(
    intensity: f32,
    depth: f32,
    lum: f32,
    historyA: f32,
    lag: f32,
    treble: f32
) -> f32 {
    // Depth-layered: distant pixels dissolve
    let depthAlpha = mix(0.28, 1.0, depth);

    // Luminance-key: suppress smearing in dark regions
    let lumaAlpha = smoothstep(0.04, 0.26, lum);

    // Effect-intensity base modulated by luminance key
    let baseAlpha = clamp(intensity * lumaAlpha, 0.06, 0.96);

    // Blend depth layering with intensity
    let layered = mix(baseAlpha, depthAlpha, 0.3);

    // Accumulative temporal alpha for feedback continuity
    let accum = ema(layered, historyA, clamp(lag * 0.9, 0.0, MAX_LAG));

    // Treble briefly increases temporal mix for audio reactivity
    return clamp(mix(layered, accum, 0.45 + treble * 0.1), 0.08, 0.98);
}

// ─────────────────────────────────────────────────────────────────────────────
// ACES Tone Mapping
// ─────────────────────────────────────────────────────────────────────────────
fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let m1 = mat3x3<f32>(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777
    );
    let m2 = mat3x3<f32>(
        1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602
    );
    let v = m1 * color;
    let a = v * (v + 0.0245786) - 0.000090537;
    let b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return clamp(m2 * (a / b), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;
    let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    let isLeader = global_id.x == 0u && global_id.y == 0u;

    let p1 = u.zoom_params.x;
    let p2 = u.zoom_params.y;
    let p3 = u.zoom_params.z;
    let p4 = u.zoom_params.w;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    // ── User parameters (sliders) ──────────────────────────────────
    // p1 Elasticity: spring stiffness + lag gain (bass widens the range)
    let elasticity = mix(0.1, 1.0, p1) * (1.0 + bass * 0.5);
    let stiffness = mix(28.0, 210.0, p1) * (1.0 + bass * 0.35);
    // p2 Damping: spring damping ratio + legacy EMA lag scale
    let zeta = mix(0.18, 1.05, p2);
    let dampLag = mix(0.1, 0.9, p2);
    // p3 Shockwave Boost: click ring strength on the chromatic split
    let shockBoost = mix(0.4, 2.4, p3);
    // p4 Palette Mix: IQ cosine palette tint amount over the grade
    let paletteMix = clamp(p4, 0.0, 1.0);
    // Legacy slider-derived constants pinned at their original defaults so
    // the shader's established look survives the slider re-scoping.
    let chromaticScale = 0.5;
    let lissajousRatio = 1.25;

    // ── Spring-damper elastic mouse (state in extraBuffer[0..3]) ───
    let rawPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    let rawVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    // Lazy init: an untouched buffer snaps to the live mouse, so there is
    // no lurch from the origin on the first frames after load.
    let springPosPrev = select(rawPos, mouse, rawPos == vec2<f32>(0.0));
    let dampCoef = 2.0 * sqrt(stiffness) * zeta;
    let spring = springStep(springPosPrev, rawVel, mouse, stiffness, dampCoef, dt);
    let springPos = clamp(spring.xy, vec2<f32>(-0.1), vec2<f32>(1.1));
    let springVel = clamp(spring.zw, vec2<f32>(-6.0), vec2<f32>(6.0));
    if (isLeader) {
        extraBuffer[133] = springPos.x;
        extraBuffer[134] = springPos.y;
        extraBuffer[135] = springVel.x;
        extraBuffer[136] = springVel.y;
        extraBuffer[137] = time;
    }

    // ── Click shockwave state (extraBuffer[4..6], edge in [8]) ─────
    var ring = 0.0;
    let rippleCnt = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCnt; i++) {
        let r = u.ripples[i];
        let age = time - r.z;
        if (age >= 0.0 && age < 4.0) {
            ring += shockwaveRing(uv01, r.xy, aspect, age, shockBoost);
        }
    }

    // ── Lissajous secondary chromatic source riding the spring ─────
    let lissFreqX = 1.0 + mids * 0.3;
    let lissFreqY = lissajousRatio + mids * 0.2;
    let lissAmp = chromaticScale * 0.08;
    let springKick = springVel * 0.02;   // spring velocity nudges the source
    let lissPos = springPos + springKick + vec2<f32>(
        lissAmp * sin(time * lissFreqX * 2.0 * (1.0 + elasticity)),
        lissAmp * sin(time * lissFreqY * 2.0 * (1.0 + elasticity))
    );

    // ── Chromatic input sample with radial RGB shift ───────────────
    // The shockwave ring temporarily widens the split as it sweeps past.
    let caAmount = (0.003 * (1.0 + bass) + depth * 0.002 + chromaticScale * 0.004)
        * (1.0 + ring);
    let source = srgbToLinear(chromaticAberration(uv01, caAmount));

    // ── Influences (spring position overshoots on fast moves) ──────
    let influence = mouseInfluence(uv01, springPos, aspect, elasticity) + ring * 0.6;
    let lissInfluence = smoothstep(0.4, 0.0, distance(uv01, lissPos)) * chromaticScale;
    let depthMod = (1.0 - depth) * 0.35;

    // ── Per-channel elastic lag ────────────────────────────────────
    let lagR = clamp(elasticity + influence + depthMod + lissInfluence, 0.0, MAX_LAG) * dampLag;
    let lagB = clamp(elasticity * 0.8 + influence * 0.5 + depthMod * 0.5 + lissInfluence * 0.7, 0.0, MAX_LAG) * dampLag;
    let lagG = clamp(elasticity * 0.6 + influence * 0.3, 0.0, MAX_LAG) * dampLag;

    // ── Temporal chromatic accumulation in linear light ────────────
    var color = vec3<f32>(0.0);
    color.r = ema(source.r, prev.r, lagR);
    color.g = ema(source.g, prev.g, lagG);
    color.b = ema(source.b, prev.b, lagB);

    // ── Audio-reactive split-tone temperature grading ──────────────
    let lumPre = luma(color);
    let shadowK = 2200.0 + depth * 1500.0;
    let highlightK = 5500.0 + bass * 6500.0;
    let tone = smoothstep(0.18, 0.72, lumPre);
    let toneColor = mix(blackbodyRGB(shadowK), blackbodyRGB(highlightK), tone);
    color = color * toneColor;

    // ── IQ cosine palette tint (low mix; grade stays dominant) ─────
    let palettePhase = lumPre * 1.3 + time * 0.045 + mids * 0.12;
    let tint = iqCosinePalette(palettePhase) * 2.0;   // mean ≈ 1.0 multiplier
    color = mix(color, color * tint, paletteMix);

    // ── HDR clamp, ACES tone map, sRGB encode ──────────────────────
    color = huePreserveClamp(color, 1.6 + mids * 0.4);
    let linearOut = acesToneMap(color * (0.95 + treble * 0.15));

    // Write linear history for next-frame feedback
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // ── Advanced semantic alpha: depth-layered + luma-key + accum ──
    let lum = luma(linearOut);
    let aberration = abs(lagR - lagB) + lissInfluence + ring * 0.35;
    let intensity = 0.26 + aberration * 2.2 + treble * 0.12;
    let effectAlpha = composeAlpha(intensity, depth, lum, prev.a, max(lagR, lagB), treble);

    let dither = (ign(vec2<f32>(pixel)) - 0.5) / 255.0;
    let srgbOut = linearToSrgb(linearOut) + vec3<f32>(dither);

    textureStore(dataTextureA, pixel, vec4<f32>(linearOut, effectAlpha));
    textureStore(writeTexture, pixel, vec4<f32>(aces_tonemap(srgbOut * effectAlpha), effectAlpha));
}
