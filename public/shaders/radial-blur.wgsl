// ═══════════════════════════════════════════════════════════════════
//  Radial Blur
//  Category: post-processing
//  Features: mouse-driven, depth-aware
//  Complexity: Medium
//  Created: 2026-04-25
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

// ═══ Utility Module ═══
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash11(x: f32) -> f32 {
  return fract(sin(x * 127.1) * 43758.5453);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    v = v + a * valueNoise(p * f);
    a = a * 0.5;
    f = f * 2.0;
  }
  return v;
}

fn rgbToLuma(c: vec3<f32>) -> f32 {
  return dot(c, vec3(0.299, 0.587, 0.114));
}

fn rgbToYuv(c: vec3<f32>) -> vec3<f32> {
  return vec3(dot(c, vec3(0.299, 0.587, 0.114)),
              dot(c, vec3(-0.14713, -0.28886, 0.436)),
              dot(c, vec3(0.615, -0.51499, -0.10001)));
}

fn yuvToRgb(c: vec3<f32>) -> vec3<f32> {
  return vec3(c.x + 1.13983 * c.z,
              c.x - 0.39465 * c.y - 0.58060 * c.z,
              c.x + 2.03211 * c.y);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec3(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let p = abs(fract(c.xxx + k) * 6.0 - 3.0);
  return c.z * mix(vec3(1.0), clamp(p - vec3(1.0), vec3(0.0), vec3(1.0)), c.y);
}

fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
  return length(p) - r;
}

fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
  let d = abs(p) - b;
  return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

fn sdLine(p: vec2<f32>, a: vec2<f32>, b2: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b2 - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

// ═══ Radial Blur Functions ═══
fn gaussianWeight(t: f32, sigma: f32) -> f32 {
  let s = max(sigma, 0.001);
  return exp(-(t * t) / (2.0 * s * s));
}

fn getBokehOffset(t: f32, angle: f32, shape: i32) -> vec2<f32> {
  let a = angle + t * 6.28318530718;
  if (shape == 1) {
    let seg = floor(a / 1.0471975512);
    let ang = a - seg * 1.0471975512 - 0.52359877559;
    return vec2(cos(ang), sin(ang)) / cos(0.52359877559);
  } else if (shape == 2) {
    let r = 1.0 + 0.5 * cos(a * 6.0);
    return vec2(cos(a), sin(a)) * r;
  }
  return vec2(cos(a), sin(a));
}

fn calculateCoC(depth: f32, focalDepth: f32, maxBlur: f32) -> f32 {
  let diff = abs(depth - focalDepth);
  return clamp(diff * maxBlur * 10.0, 0.0, 1.0);
}

fn sampleChromatic(uv: vec2<f32>, dir: vec2<f32>, strength: f32, samples: i32, chromaShift: f32) -> vec4<f32> {
  var accR = vec3(0.0);
  var accG = vec3(0.0);
  var accB = vec3(0.0);
  var weightSum = 0.0;

  let sigma = clamp(u.zoom_params.x, 0.01, 1.0);
  let shape = clamp(i32(u.zoom_params.y), 0, 2);

  for (var i = 0; i < samples; i = i + 1) {
    let t = f32(i) / f32(samples - 1);
    let w = gaussianWeight(t - 0.5, sigma);

    let angle = f32(i) * 2.39996322973;
    let bokeh = getBokehOffset(t, angle, shape);

    // Depth-aware CoC
    let sampleUV = uv + dir * t * strength;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
    let coc = calculateCoC(depth, u.zoom_params.z, u.zoom_params.w);
    let effStrength = strength * (1.0 + coc);

    // R: +10% radius + chromatic offset
    let uvR = uv + dir * t * effStrength * 1.1 + bokeh * chromaShift;
    accR = accR + textureSampleLevel(readTexture, u_sampler, uvR, 0.0).rgb * w;

    // G: baseline
    let uvG = uv + dir * t * effStrength;
    accG = accG + textureSampleLevel(readTexture, u_sampler, uvG, 0.0).rgb * w;

    // B: -10% radius - chromatic offset
    let uvB = uv + dir * t * effStrength * 0.9 - bokeh * chromaShift;
    accB = accB + textureSampleLevel(readTexture, u_sampler, uvB, 0.0).rgb * w;

    weightSum = weightSum + w;
  }

  let iw = 1.0 / max(weightSum, 0.001);
  let r = accR.r * iw;
  let g = accG.g * iw;
  let b = accB.b * iw;

  let blurStrength = clamp(strength * 5.0, 0.0, 1.0);
  let alpha = mix(1.0, 0.8, blurStrength);

  return vec4(r, g, b, alpha);
}

fn applyVignette(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
  let dist = length(uv - 0.5);
  let v = 1.0 - smoothstep(0.3, 0.9, dist * strength);
  return color * v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;

  let center = vec2(0.5);
  let dir = normalize(uv - center + vec2(0.0001));

  let mousePos = u.zoom_config.yz;
  let mouseDist = length(uv - mousePos);
  let baseStrength = u.zoom_params.x * 0.2;
  let strength = baseStrength * (1.0 + mouseDist * 0.5);
  let chromaShift = baseStrength * 0.05;
  let samples = 32;

  var color = sampleChromatic(uv, dir, strength, samples, chromaShift);
  let vignetteStrength = 1.0 + u.zoom_params.x;
  color = vec4(applyVignette(color.rgb, uv, vignetteStrength), color.a);

  textureStore(writeTexture, global_id.xy, color);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
