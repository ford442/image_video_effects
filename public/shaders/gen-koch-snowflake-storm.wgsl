// ═══════════════════════════════════════════════════════════════════
//  Koch Snowflake Storm
//  Category: generative
//  Features: procedural, fractal, koch-snowflake, domain-warping,
//            fbm-turbulence, curl-noise, voronoi-ice, audio-reactive,
//            mouse-driven, aces-tonemap, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-30
//  Upgraded: 2026-07-13
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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var q = p;
  for (var i = 0; i < oct; i = i + 1) {
    v = v + a * valueNoise(q);
    q = q * 2.03 + vec2<f32>(1.7, 9.2);
    a = a * 0.5;
  }
  return v;
}

fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
  let q = vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
  return p + strength * q;
}

fn voronoi(p: vec2<f32>) -> vec2<f32> {
  let i = floor(p);
  let f = fract(p);
  var minDist = 1.0e10;
  var cellId = 0.0;
  for (var y = -1; y <= 1; y = y + 1) {
    for (var x = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let point = neighbor + hash21(i + neighbor);
      let diff = point - f;
      let d = dot(diff, diff);
      let closer = f32(d < minDist);
      minDist = mix(minDist, d, closer);
      cellId = mix(cellId, hash21(i + neighbor), closer);
    }
  }
  return vec2<f32>(sqrt(minDist), cellId);
}

fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.01;
  let n0 = fbm(p + vec2<f32>(eps, 0.0) + t, 3);
  let n1 = fbm(p - vec2<f32>(eps, 0.0) + t, 3);
  let n2 = fbm(p + vec2<f32>(0.0, eps) + t, 3);
  let n3 = fbm(p - vec2<f32>(0.0, eps) + t, 3);
  let dndx = (n0 - n1) / (2.0 * eps);
  let dndy = (n2 - n3) / (2.0 * eps);
  return vec2<f32>(dndy, -dndx);
}

fn snowflake_sdf(p: vec2<f32>, size: f32, recurse: i32) -> f32 {
  let a = atan2(p.y, p.x);
  let r = length(p);
  var border = size;
  for (var i = 0; i < recurse; i = i + 1) {
    let fi = f32(i);
    let freq = pow(3.0, fi + 1.0);
    border = border + sin(a * freq + fi * 0.4) * size * 0.18 / pow(3.0, fi);
  }
  return r - border;
}

fn sdHexagon(p: vec2<f32>, r: f32) -> f32 {
  let k = vec3<f32>(-0.866025404, 0.5, 0.577350269);
  var q = abs(p);
  q = q - 2.0 * min(dot(k.xy, q), 0.0) * k.xy;
  q = q - vec2<f32>(clamp(q.x, -k.z * r, k.z * r), r);
  return length(q) * sign(q.y);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;

  let turbStrength = mix(0.05, 0.45, clamp(u.zoom_params.x + bass * 0.35, 0.0, 1.0));
  let recursions = i32(mix(2.0, 5.0, u.zoom_params.y));
  let snowCount = i32(mix(2.0, 5.0, u.zoom_params.z));
  let dispersion = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 3.0;

  let mousePos = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;

  // Domain-warped storm drift + curl noise
  let warp = domainWarp(p * 2.5 + vec2<f32>(time * 0.18, time * 0.12), turbStrength, 4);
  let storm = curlNoise(p * 1.5 + time * 0.1, time * 0.15) * turbStrength * 0.15;
  p = p + vec2<f32>(cos(warp.x * TAU), sin(warp.y * TAU)) * turbStrength * 0.25 + storm;

  var minDist = 1e9;
  var nearestSize = 0.0;
  var nearestId = 0.0;

  for (var si = 0; si < snowCount; si = si + 1) {
    let sf = f32(si);
    let angle = sf * 2.094 + time * 0.08 * (1.0 + bass * 0.5);
    let dist = 0.7 + sin(sf * 1.3 + time * 0.15) * 0.35;
    let offset = vec2<f32>(cos(angle), sin(angle)) * dist + mousePos * 0.4;
    let size = 0.25 + sin(sf * 2.7) * 0.12;
    let d = snowflake_sdf(p - offset, size, recursions);
    let hexD = sdHexagon(p - offset * 1.3, size * 0.4);
    let combined = smin(d, hexD, 0.08);
    let closer = f32(combined < minDist);
    minDist = mix(minDist, combined, closer);
    nearestSize = mix(nearestSize, size, closer);
    nearestId = mix(nearestId, sf, closer);
  }

  // Voronoi ice crystal grain overlay
  let voro = voronoi(p * 4.0 + warp);
  let crystal = smoothstep(0.12, 0.0, voro.x);

  let edge = abs(minDist) / max(nearestSize, 0.001);
  let inside = smoothstep(0.0, 0.08, -minDist);
  let glow = exp(-edge * 4.0);

  var color = mix(
    vec3<f32>(0.75, 0.88, 0.95),
    vec3<f32>(0.12, 0.35, 0.55),
    inside
  );

  // Subsurface scattering warm core
  let core = exp(-edge * 8.0) * (0.6 + 0.4 * cos(nearestId + time * 0.2));
  color = color + vec3<f32>(0.6, 0.75, 1.0) * glow * 1.5;
  color = mix(color, vec3<f32>(0.95, 0.85, 0.65), core * 0.3);

  // Crystalline grain
  color = mix(color, vec3<f32>(0.9, 0.95, 1.0), crystal * 0.2);

  let ca = smoothstep(0.1, 0.5, edge) * dispersion;
  color = vec3<f32>(
    color.r * (1.0 + ca * 0.15),
    color.g * (1.0 + ca * 0.05),
    color.b * (1.0 - ca * 0.08)
  );

  // Temporal feedback
  let histUV = uv + vec2<f32>(sin(time * 0.18) * 0.001, cos(time * 0.12) * 0.001);
  let prev = textureSampleLevel(dataTextureC, u_sampler, histUV, 0.0).rgb;
  color = mix(color, prev * 0.94, 0.05);

  color = acesToneMap(color * 1.6);

  let density = glow * 0.7 + inside * 0.3 + crystal * 0.15;
  let alpha = clamp(density * turbStrength * 2.5 + treble * 0.1, 0.0, 0.95);
  let depth = clamp(1.0 - edge * 0.8 + crystal * 0.1, 0.0, 1.0);

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}
