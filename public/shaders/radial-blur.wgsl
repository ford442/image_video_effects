// ═══════════════════════════════════════════════════════════════════
//  Radial Blur v2 — Transcendent Pass
//  Category: post-processing
//  Features: mouse-driven, depth-aware, audio-reactive, anisotropic-bokeh,
//            diffraction-spikes, anamorphic-streaks, spectral-dispersion
//  Complexity: Very High
//  Upgraded: 2026-05-30
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
//  Upgraded: 2026-08-23 (Batch 67 — fast motion / psychedelic / high energy)
//
//  THREE BUGS FIXED
//
//  1. Ripple payload read as a velocity. The shader had
//
//         let mouseVel = u.ripples[0].zw;   // "last-frame mouse delta"
//
//     but per docs/BINDING_CONTRACT.md `ripples[i].z` is the click START TIME in
//     seconds and `.w` is PADDING, always 0.0 and explicitly "not a strength
//     value". So `mouseVel` was `(startTime, 0)`: `motionDir` normalised to
//     ~(1,0) forever, and `velMag` equalled the absolute click timestamp — which
//     grows without bound, so `motionBlur = velMag * 0.15` ramps the whole frame
//     toward maximum blur the longer the session runs. Real pointer velocity now
//     comes from a spring-damper in `extraBuffer[133..136]`.
//
//  2. No `dataTextureA` writeback on either exit path, so the slot was dead and
//     `dataTextureC` could never carry anything.
//
//  3. The early-exit "pristine" path wrote alpha hardcoded to `0.0`, telling the
//     compositor the in-focus region was fully transparent.
//
//  FAST MOTION (two analytic techniques)
//
//    1. Zoom-burst speed lines — radial streaks whose length scales with the
//       blur radius and pointer speed, sampled as a closed-form line integral
//       outward from the focus centre. Clamped so the streak can never exceed a
//       bounded fraction of the frame.
//
//    2. Rotational shear streaks — a second integral along the tangential
//       direction, phase-advanced continuously in `config.x`, so the blur field
//       visibly spins as well as zooms. The two combine into a whip.
//
//  PSYCHEDELIC COLOUR — the chromatic sampler is driven by an IQ cosine palette
//  keyed to circle-of-confusion and per-band FFT energy, so the bokeh fringes
//  fan through the spectrum instead of a single R/B split.
//
//  HIGH ENERGY — bounded click bursts detonate zoom shockwaves that snap the
//  focus outward and recover elastically.
// ═══════════════════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ── Utilities ────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

fn rgbToLuma(c: vec3<f32>) -> f32 {
  return dot(c, vec3(0.299, 0.587, 0.114));
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec3(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let p = abs(fract(c.xxx + k) * 6.0 - 3.0);
  return c.z * mix(vec3(1.0), clamp(p - vec3(1.0), vec3(0.0), vec3(1.0)), c.y);
}

// ── Bokeh & Sampling ─────────────────────────────────────────
fn gaussianWeight(t: f32, sigma: f32) -> f32 {
  let s = max(sigma, 0.001);
  return exp(-(t * t) / (2.0 * s * s));
}

fn getBokehOffset(t: f32, angle: f32, shape: f32) -> vec2<f32> {
  let a = angle + t * 6.28318530718;
  let circ = vec2(cos(a), sin(a));
  let seg = floor(a / 1.0471975512);
  let ang = a - seg * 1.0471975512 - 0.52359877559;
  let hex = vec2(cos(ang), sin(ang)) / cos(0.52359877559);
  let r = 1.0 + 0.5 * cos(a * 6.0);
  let star = vec2(cos(a), sin(a)) * r;
  return mix(mix(circ, hex, smoothstep(0.0, 1.0, shape)), star, smoothstep(1.0, 2.0, shape));
}

fn calculateCoC(depth: f32, focalDepth: f32, maxBlur: f32) -> f32 {
  return clamp(abs(depth - focalDepth) * maxBlur * 10.0, 0.0, 1.0);
}

// ═══ CHUNK: fibonacciSphere (from advanced-hybrid canon) ═══
fn fibonacciSphere(i: f32, n: f32) -> vec2<f32> {
  let phi = 1.61803398875;
  let theta = 6.28318530718 * fract(i * phi);
  let r = sqrt(i / (n - 1.0));
  return vec2(cos(theta), sin(theta)) * r;
}

// Sellmeier-ish spectral dispersion approximation
fn spectralRefract(lambda: f32) -> f32 {
  let l2 = lambda * lambda;
  return 1.0 + 0.5 / (1.0 - 0.04 / l2) + 0.1 / (1.0 - 0.1 / l2);
}

fn diffractionSpikes(uv: vec2<f32>, dir: vec2<f32>, luma: f32, strength: f32) -> vec3<f32> {
  let spike = pow(max(1.0 - abs(dot(uv, vec2(dir.y, -dir.x))) * 8.0, 0.0), 8.0);
  return vec3(spike * strength * luma);
}

fn sampleChromatic(uv: vec2<f32>, dir: vec2<f32>, strength: f32, samples: i32, chromaShift: f32, shape: f32, motionDir: vec2<f32>) -> vec4<f32> {
  var accR = vec3(0.0);
  var accG = vec3(0.0);
  var accB = vec3(0.0);
  var weightSum = 0.0;

  let sigma = clamp(u.zoom_params.x, 0.01, 1.0);

  for (var i = 0; i < samples; i = i + 1) {
    let fi = f32(i);
    let t = fi / f32(samples - 1);
    let w = gaussianWeight(t - 0.5, sigma);

    let angle = fi * 2.39996322973;
    let bokeh = getBokehOffset(t, angle, shape);

    let sampleUV = uv + dir * t * strength;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
    let coc = calculateCoC(depth, u.zoom_params.z, u.zoom_params.w);
    let effStrength = strength * (1.0 + coc);

    // Spectral dispersion via Sellmeier approx
    let lambdaR = 0.70;
    let lambdaG = 0.53;
    let lambdaB = 0.45;
    let dispR = (spectralRefract(lambdaR) - 1.0) * chromaShift;
    let dispB = (spectralRefract(lambdaB) - 1.0) * chromaShift;

    // Anamorphic streak along motionDir
    let streak = motionDir * dot(motionDir, bokeh) * 0.4;

    let uvR = uv + dir * t * effStrength * 1.1 + bokeh * chromaShift * 1.2 + streak * dispR + vec2(dispR * 0.02, 0.0);
    let uvG = uv + dir * t * effStrength + streak * 0.1;
    let uvB = uv + dir * t * effStrength * 0.9 - bokeh * chromaShift * 1.2 + streak * dispB - vec2(dispB * 0.02, 0.0);

    accR = accR + textureSampleLevel(readTexture, u_sampler, clamp(uvR, vec2(0.0), vec2(1.0)), 0.0).rgb * w;
    accG = accG + textureSampleLevel(readTexture, u_sampler, clamp(uvG, vec2(0.0), vec2(1.0)), 0.0).rgb * w;
    accB = accB + textureSampleLevel(readTexture, u_sampler, clamp(uvB, vec2(0.0), vec2(1.0)), 0.0).rgb * w;

    weightSum = weightSum + w;
  }

  let iw = 1.0 / max(weightSum, 0.001);
  return vec4(accR.r * iw, accG.g * iw, accB.b * iw, 1.0);
}

fn applyVignette(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
  let dist = length(uv - 0.5);
  return color * (1.0 - smoothstep(0.3, 0.9, dist * strength));
}

fn atmosphericHaze(color: vec3<f32>, depth: f32, hazeAmt: f32) -> vec3<f32> {
  let haze = vec3(0.75, 0.82, 0.92);
  return mix(color, haze, depth * hazeAmt);
}

fn spectrum(tt: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(6.2831853 * (tt + vec3<f32>(0.0, 0.33, 0.67)));
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let mouseDist = length(uv - mousePos);

  let time = u.config.x;
  let coord = vec2<i32>(global_id.xy);

  // ── Real pointer velocity, spring-damped in extraBuffer[133..136] ─────────
  // [133..134] = smoothed position, [135..136] = smoothed velocity. Only
  // invocation (0,0) writes. (The old `u.ripples[0].zw` was a click timestamp
  // and a padding zero — see header.)
  if (global_id.x == 0u && global_id.y == 0u) {
    var sm = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    if (sm.x == 0.0 && sm.y == 0.0) { sm = mousePos; }
    let dt = 0.016;
    let k = 1.0 - exp(-11.0 * dt);
    let next = sm + (mousePos - sm) * k;
    var sv = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    sv = mix(sv, (next - sm) / dt, 0.3);
    extraBuffer[133] = next.x;
    extraBuffer[134] = next.y;
    extraBuffer[135] = sv.x;
    extraBuffer[136] = sv.y;
  }
  let mouseVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  let velMag = clamp(length(mouseVel), 0.0, 4.0);
  let motionDir = select(vec2<f32>(1.0, 0.0), mouseVel / max(length(mouseVel), 1e-5),
                         velMag > 1e-4);

  // ── HIGH ENERGY: bounded click zoom shockwaves ───────────────────────────
  var zoomBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age < 0.0 || age >= 2.0) { continue; }
    let r = length(uv - rp.xy);
    let front = r - age * 0.7;
    zoomBurst += exp(-front * front * 150.0) * exp(-age * 1.6);
  }
  zoomBurst = min(zoomBurst, 1.5);

  let bass = plasmaBuffer[0].x;
  let baseSigma = u.zoom_params.x;
  let shapeParam = clamp(u.zoom_params.y, 0.0, 2.0);
  let focalDepth = u.zoom_params.z;
  let maxBlur = u.zoom_params.w;

  // Anisotropic shape morph: audio drives circle->hex->star
  let audioShape = shapeParam + bass * 0.5;
  let shape = clamp(audioShape, 0.0, 2.0);

  // Dynamic focus point: mouse overrides center when down
  let focusCenter = mix(vec2(0.5), mousePos, mouseDown * 0.7);
  let dir = normalize(uv - focusCenter + vec2(0.0001));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let coc = calculateCoC(depth, focalDepth, maxBlur);

  // Bass drives blur radius; mouse proximity adds local CoC
  let localCoC = mouseDown * exp(-mouseDist * 4.0) * 0.5;
  let blurRadius = baseSigma * 0.25 * (1.0 + bass * 0.6 + coc * 2.0 + localCoC);

  // Velocity adds directional motion blur
  let motionBlur = clamp(velMag * 0.06 + zoomBurst * 0.10, 0.0, 0.35);
  let strength = blurRadius + motionBlur;

  // Adaptive sample count: fewer in smooth regions, more at edges
  let edge = abs(valueNoise(uv * 30.0) - valueNoise(uv * 30.0 + vec2(0.01, 0.0))) * 10.0;
  let adaptiveSamples = i32(mix(16.0, 40.0, clamp(edge + coc + motionBlur * 5.0, 0.0, 1.0)));

  // Early exit for perfectly in-focus pixels
  if (coc < 0.005 && motionBlur < 0.001 && localCoC < 0.001) {
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    // Alpha was hardcoded 0.0 here, telling the compositor the in-focus region
    // was fully transparent. In-focus content is the most solid thing on screen.
    let pristineOut = vec4(acesFilm(src.rgb), clamp(src.a * 0.85 + 0.15, 0.0, 1.0));
    textureStore(writeTexture, coord, pristineOut);
    textureStore(dataTextureA, coord, pristineOut);
    textureStore(writeDepthTexture, coord, vec4(depth, 0.0, 0.0, 0.0));
    return;
  }

  let chromaShift = baseSigma * 0.06 * (1.0 + zoomBurst);
  var color = sampleChromatic(uv, dir, strength, adaptiveSamples, chromaShift, shape, motionDir);

  // ── FAST MOTION 1: zoom-burst speed lines ────────────────────────────────
  // Closed-form line integral outward from the focus centre; length scales with
  // blur radius and pointer speed, hard-clamped so it can never run away.
  let streakLen = clamp(strength * 0.9 + velMag * 0.012 + zoomBurst * 0.05, 0.0, 0.09);
  var speedLines = vec3<f32>(0.0);
  var slw = 0.0;
  for (var s = 1u; s <= 6u; s = s + 1u) {
    let fs = f32(s) / 6.0;
    let w = 1.0 - fs * 0.75;
    let tapUV = clamp(uv + dir * streakLen * fs, vec2<f32>(0.0), vec2<f32>(1.0));
    speedLines += textureSampleLevel(readTexture, u_sampler, tapUV, 0.0).rgb * w;
    slw += w;
  }
  speedLines = speedLines / max(slw, 1e-4);

  // ── FAST MOTION 2: rotational shear streaks ──────────────────────────────
  // Tangential integral with a continuously advancing phase, so the field spins
  // as well as zooms.
  let tangential = vec2<f32>(-dir.y, dir.x);
  let spinPhase = time * (0.8 + bass * 1.6);
  let shearLen = clamp(strength * 0.6 + velMag * 0.008, 0.0, 0.06)
               * (0.6 + 0.4 * sin(spinPhase));
  var shear = vec3<f32>(0.0);
  var shw = 0.0;
  for (var s = 1u; s <= 5u; s = s + 1u) {
    let fs = f32(s) / 5.0;
    let w = 1.0 - fs * 0.7;
    let tapUV = clamp(uv + tangential * shearLen * fs, vec2<f32>(0.0), vec2<f32>(1.0));
    shear += textureSampleLevel(readTexture, u_sampler, tapUV, 0.0).rgb * w;
    shw += w;
  }
  shear = shear / max(shw, 1e-4);

  let whipMix = clamp(motionBlur * 2.2 + zoomBurst * 0.6, 0.0, 0.75);
  color = vec4(mix(color.rgb, max(speedLines, shear), whipMix), color.a);

  // ── PSYCHEDELIC: CoC + FFT keyed bokeh spectrum ──────────────────────────
  let bandIdx = u32(clamp(length(uv - focusCenter) * 8.0, 0.0, 7.999));
  let band = plasmaBuffer[bandIdx + 1u].x;
  let bokehHue = fract(coc * 1.6 + band * 0.7 + time * 0.05 + velMag * 0.05);
  let bokehTint = pow(spectrum(bokehHue), vec3<f32>(0.72));
  let fringe = clamp(coc * 1.4 + whipMix * 0.8, 0.0, 1.0);
  color = vec4(mix(color.rgb, color.rgb * bokehTint * 1.7, fringe * 0.65), color.a);
  color = vec4(color.rgb + spectrum(fract(bokehHue + 0.5)) * zoomBurst * 1.2, color.a);

  // Diffraction spikes on bright highlights
  let luma = rgbToLuma(color.rgb);
  let spikeBright = pow(smoothstep(0.5, 1.0, luma), 3.0);
  let spikes = diffractionSpikes(uv - focusCenter, dir, spikeBright, strength * 2.0);
  color = vec4(color.rgb + spikes, color.a);

  // Atmospheric haze on distant blur
  color = vec4(atmosphericHaze(color.rgb, depth * coc, 0.25), color.a);

  // Vignette
  let vignetteStrength = 1.0 + baseSigma;
  color = vec4(applyVignette(color.rgb, uv, vignetteStrength), color.a);

  // Temporal streak memory (exact load — dataTextureC is rgba32float).
  let prev = textureLoad(dataTextureC, coord, 0);
  color = vec4(max(color.rgb, prev.rgb * (0.70 + whipMix * 0.18)), color.a);

  let finalRGB = acesFilm(color.rgb);

  // Alpha = CoC * motion energy (semantic: translucency of the blurred layer),
  // with a floor so blurred content is never fully invisible.
  let alpha = clamp(coc * (1.0 + motionBlur * 10.0) * (1.0 + localCoC * 2.0)
                    + whipMix * 0.3 + zoomBurst * 0.25 + 0.08, 0.0, 1.0);

  let outColor = vec4(finalRGB, alpha);
  textureStore(writeTexture, coord, outColor);
  textureStore(dataTextureA, coord, outColor);
  textureStore(writeDepthTexture, coord, vec4(depth, 0.0, 0.0, 0.0));
}
