// ═══════════════════════════════════════════════════════════════════
//  Radial RGB
//  Category: distortion
//  Features: mouse-driven, chromatic-aberration
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

// ═══ Radial RGB Functions ═══
fn lensDistort(uv: vec2<f32>, center: vec2<f32>, k1: f32, k2: f32) -> vec2<f32> {
  let d = uv - center;
  let r2 = dot(d, d);
  let r4 = r2 * r2;
  let dist = 1.0 + k1 * r2 + k2 * r4;
  return center + d * dist;
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  var r = 0.0;
  var g = 0.0;
  var b = 0.0;
  if (lambda < 440.0) {
    r = (440.0 - lambda) / 60.0;
    b = 1.0;
  } else if (lambda < 490.0) {
    g = (lambda - 440.0) / 50.0;
    b = 1.0;
  } else if (lambda < 510.0) {
    g = 1.0;
    b = (510.0 - lambda) / 20.0;
  } else if (lambda < 580.0) {
    r = (lambda - 510.0) / 70.0;
    g = 1.0;
  } else if (lambda < 645.0) {
    r = 1.0;
    g = (645.0 - lambda) / 65.0;
  } else {
    r = 1.0;
  }
  var intensity = 1.0;
  if (lambda < 420.0) {
    intensity = 0.3 + 0.7 * (lambda - 380.0) / 40.0;
  } else if (lambda > 700.0) {
    intensity = 0.3 + 0.7 * (780.0 - lambda) / 80.0;
  }
  return clamp(vec3(r, g, b) * intensity, vec3(0.0), vec3(1.0));
}

fn sampleSpectral(uv: vec2<f32>, dispersion: f32, direction: vec2<f32>) -> vec3<f32> {
  var color = vec3(0.0);
  let wavelengths = array(380.0, 450.0, 500.0, 550.0, 600.0, 650.0, 700.0);
  for (var i = 0; i < 7; i = i + 1) {
    let lambda = wavelengths[i];
    let offset = (lambda - 550.0) / 250.0 * dispersion;
    let sampleUV = uv + direction * offset;
    let sampleCol = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let w = wavelengthToRGB(lambda);
    color = color + sampleCol * w;
  }
  return color * 0.25;
}

fn applyVignette(color: vec3<f32>, uv: vec2<f32>, intensity: f32, roundness: f32) -> vec3<f32> {
  let dist = length(uv - 0.5);
  let v = 1.0 - smoothstep(0.3 * roundness, 0.85, dist * intensity);
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
  let k1 = (u.zoom_params.x - 0.5) * 2.0;
  let k2 = (u.zoom_params.y - 0.5) * 2.0;
  let anamorphic = 1.0 + u.zoom_params.z * 2.0;
  let dispersion = u.zoom_params.w * 0.05;

  // Lens distortion
  var distortedUV = lensDistort(uv, center, k1, k2);

  // Anamorphic stretch
  distortedUV.y = (distortedUV.y - 0.5) / anamorphic + 0.5;

  // Direction from mouse
  let mouseDir = normalize(u.zoom_config.yz - 0.5 + vec2(0.0001));

  // Spectral sampling
  var color = sampleSpectral(distortedUV, dispersion, mouseDir);

  // Vignette
  let vignetteIntensity = 1.0 + abs(k1) * 0.5;
  color = applyVignette(color, uv, vignetteIntensity, 1.0);

  // Alpha: lens transmission based on vignette
  let dist = length(uv - 0.5);
  let transmission = 1.0 - smoothstep(0.4, 0.9, dist * (1.0 + abs(k1) * 0.3));
  let alpha = clamp(transmission, 0.4, 1.0);

  textureStore(writeTexture, global_id.xy, vec4(color, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
