// ═══════════════════════════════════════════════════════════════════
//  Waveform Glitch
//  Category: retro-glitch
//  Features: temporal
//  Complexity: High
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

// ── Hash & Noise ─────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}
fn hash11(p: f32) -> f32 {
  return fract(sin(p * 12.9898) * 43758.5453);
}
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}

// ── Color Utilities ──────────────────────────────────────────
fn rgbToLuma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}
fn rgbToYuv(rgb: vec3<f32>) -> vec3<f32> {
  let y = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b;
  let u = -0.14713 * rgb.r - 0.28886 * rgb.g + 0.436 * rgb.b;
  let v = 0.615 * rgb.r - 0.51499 * rgb.g - 0.10001 * rgb.b;
  return vec3<f32>(y, u, v);
}
fn yuvToRgb(yuv: vec3<f32>) -> vec3<f32> {
  let r = yuv.x + 1.13983 * yuv.z;
  let g = yuv.x - 0.39465 * yuv.y - 0.58060 * yuv.z;
  let b = yuv.x + 2.03211 * yuv.y;
  return vec3<f32>(r, g, b);
}
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let c = hsv.z * hsv.y;
  let h = hsv.x * 6.0;
  let x = c * (1.0 - abs(fract(h) * 2.0 - 1.0));
  var rgb = vec3<f32>(0.0);
  if (h < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
  else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else              { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(hsv.z - c);
}

// ── Waveform & Glitch Functions ──────────────────────────────
fn sawtoothWave(x: f32) -> f32 {
  return fract(x);
}
fn vhsTracking(uv: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
  let jitter = sin(time * 30.0 + uv.y * 1000.0) * intensity * 0.02;
  let roll = sin(time * 0.2) * intensity * 0.005;
  return uv + vec2<f32>(jitter, roll);
}
fn blockCorruption(uv: vec2<f32>, blockSize: f32, intensity: f32, time: f32) -> vec2<f32> {
  let blockId = floor(uv / blockSize);
  let rnd = hash21(blockId + vec2<f32>(time * 0.1, 7.31));
  let offset = (rnd - 0.5) * intensity * blockSize;
  return uv + vec2<f32>(offset, 0.0);
}
fn datamoshDisp(uv: vec2<f32>, time: f32, smearScale: f32) -> vec2<f32> {
  let n = fbm(uv * 12.0 + time * 2.0, 3);
  let grad = vec2<f32>(
    valueNoise(uv + vec2<f32>(0.001, 0.0)) - valueNoise(uv - vec2<f32>(0.001, 0.0)),
    valueNoise(uv + vec2<f32>(0.0, 0.001)) - valueNoise(uv - vec2<f32>(0.0, 0.001))
  );
  let gradLen = length(grad);
  let dir = select(vec2<f32>(0.0), grad / gradLen, gradLen > 0.0001);
  return uv + dir * n * smearScale * 0.05;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let uv = vec2<f32>(global_id.xy) / vec2<f32>(u.config.z, u.config.w);
  let time = u.config.x;

  let vhsJitter = u.zoom_params.x;
  let intensity = u.zoom_params.y;
  let smearScale = u.zoom_params.z;
  let flickerSpeed = 2.0 + u.zoom_params.w * 20.0;

  var warped = vhsTracking(uv, time, vhsJitter);
  warped = blockCorruption(warped, 0.08, intensity, time);
  warped = datamoshDisp(warped, time, smearScale);
  warped = clamp(warped, vec2<f32>(0.0), vec2<f32>(1.0));

  let glitchStrength = clamp(length(warped - uv) * 10.0, 0.0, 1.0);

  let cR = textureSampleLevel(readTexture, u_sampler, warped + vec2<f32>(0.003 * intensity, 0.0), 0.0);
  let cG = textureSampleLevel(readTexture, u_sampler, warped, 0.0);
  let cB = textureSampleLevel(readTexture, u_sampler, warped - vec2<f32>(0.003 * intensity, 0.0), 0.0);

  let flicker = 0.8 + 0.2 * sawtoothWave(time * flickerSpeed);
  let col = vec3<f32>(cR.r, cG.g, cB.b) * flicker;
  let alpha = cG.a * (1.0 - glitchStrength * 0.5);

  textureStore(writeTexture, global_id.xy, vec4<f32>(col, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
