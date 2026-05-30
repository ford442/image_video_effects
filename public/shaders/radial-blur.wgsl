// ═══════════════════════════════════════════════════════════════════
//  Radial Blur v2 — Transcendent Pass
//  Category: post-processing
//  Features: mouse-driven, depth-aware, audio-reactive, anisotropic-bokeh,
//            diffraction-spikes, anamorphic-streaks, spectral-dispersion
//  Complexity: Very High
//  Upgraded: 2026-05-30
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let mouseDist = length(uv - mousePos);

  // Velocity proxy from ripple[0].zw as last-frame mouse delta
  let mouseVel = u.ripples[0].zw;
  let motionDir = normalize(mouseVel + vec2(0.0001, 0.0001));
  let velMag = length(mouseVel);

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
  let motionBlur = velMag * 0.15;
  let strength = blurRadius + motionBlur;

  // Adaptive sample count: fewer in smooth regions, more at edges
  let edge = abs(valueNoise(uv * 30.0) - valueNoise(uv * 30.0 + vec2(0.01, 0.0))) * 10.0;
  let adaptiveSamples = i32(mix(16.0, 40.0, clamp(edge + coc + motionBlur * 5.0, 0.0, 1.0)));

  // Early exit for perfectly in-focus pixels
  if (coc < 0.005 && motionBlur < 0.001 && localCoC < 0.001) {
    let pristine = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    textureStore(writeTexture, global_id.xy, vec4(pristine, 0.0));
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
    return;
  }

  let chromaShift = baseSigma * 0.06;
  var color = sampleChromatic(uv, dir, strength, adaptiveSamples, chromaShift, shape, motionDir);

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

  // Alpha = CoC * motion energy (semantic: translucency of blurred layer)
  let alpha = clamp(coc * (1.0 + motionBlur * 10.0) * (1.0 + localCoC * 2.0), 0.0, 1.0);

  textureStore(writeTexture, global_id.xy, vec4(color.rgb, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
