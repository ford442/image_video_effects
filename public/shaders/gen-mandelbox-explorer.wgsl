// ═══════════════════════════════════════════════════════════════════
//  Mandelbox Explorer
//  Category: generative
//  Features: procedural, fractal, mandelbox, orbit-trap, raymarched-slice,
//            domain-warping, fbm, strange-attractor, audio-reactive,
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

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
  return length(p) - r;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

fn boxFold(v: vec3<f32>) -> vec3<f32> {
  return clamp(v, vec3<f32>(-1.0), vec3<f32>(1.0)) * 2.0 - v;
}

fn sphereFold(v: vec3<f32>) -> vec3<f32> {
  let r2 = dot(v, v);
  let inSmall = r2 < 0.25;
  let inLarge = r2 < 1.0;
  let s1 = select(1.0, 4.0, inSmall);
  let s2 = select(1.0, 1.0 / max(r2, 0.0001), inLarge && !inSmall);
  return v * s1 * s2;
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

  let scale = mix(-2.5, 2.5, clamp(u.zoom_params.x + bass * 0.25, 0.0, 1.0));
  let maxIter = i32(mix(30.0, 90.0, u.zoom_params.y));
  let sliceThick = mix(0.0, 0.6, u.zoom_params.z);
  let specular = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 4.0;

  let angle = (mouse.x - 0.5) * PI;
  let ca = cos(angle);
  let sa = sin(angle);
  p = vec2<f32>(p.x * ca - p.y * sa, p.x * sa + p.y * ca);

  // Domain-warped slice thickness and c offset
  let warp = domainWarp(p * 1.5 + vec2<f32>(time * 0.1), 0.2 + bass * 0.1, 4);
  let zSlice = sliceThick + warp.x * 0.15;
  var z = vec3<f32>(p.x, p.y, zSlice);
  let cBase = vec3<f32>(p.x, p.y, 0.0);
  let c = cBase + vec3<f32>(warp * 0.08, 0.0);

  var orbitMin = 1e9;
  var orbitAvg = 0.0;
  var orbitTrap = vec3<f32>(1e9);

  for (var i = 0; i < maxIter; i = i + 1) {
    z = boxFold(z);
    z = sphereFold(z);
    z = z * scale + c;
    let lz = length(z);
    orbitMin = min(orbitMin, lz);
    orbitAvg = orbitAvg + lz;
    orbitTrap.x = min(orbitTrap.x, abs(z.x));
    orbitTrap.y = min(orbitTrap.y, abs(z.y));
    orbitTrap.z = min(orbitTrap.z, abs(z.z));
    if (dot(z, z) > 10000.0) { break; }
  }
  orbitAvg = orbitAvg / f32(maxIter);

  // Blend with a strange-attractor / SDF sphere orbit trap
  let attractorP = vec3<f32>(
    sin(time * 0.3) * 0.8,
    cos(time * 0.22) * 0.6,
    sin(time * 0.17) * 0.5
  );
  let attractorDist = sdSphere(z - attractorP, 0.35 + bass * 0.15);
  orbitMin = smin(orbitMin, attractorDist, 0.25);

  let ao = exp(-orbitMin * 4.0);
  let temp = fract(orbitAvg * 0.1 + 0.5);
  let warm = vec3<f32>(0.95, 0.78, 0.55);
  let cool = vec3<f32>(0.55, 0.72, 0.92);
  var color = mix(warm, cool, temp);
  color = mix(vec3<f32>(0.15, 0.18, 0.25), color, 1.0 - ao * 0.8);

  // Orbit-trap metallic tint
  let trapColor = vec3<f32>(0.95, 0.92, 0.85) * clamp(1.0 - orbitTrap * 3.0, vec3<f32>(0.0), vec3<f32>(1.0));
  color = mix(color, trapColor, 0.25);

  let highlight = exp(-orbitMin * orbitMin * 12.0);
  color = color + vec3<f32>(1.0, 0.95, 0.78) * highlight * specular * 3.5;

  let edge = smoothstep(0.25, 0.65, 1.0 - ao);
  color = vec3<f32>(
    color.r * (1.0 + edge * 0.12),
    color.g * (1.0 + edge * 0.04),
    color.b * (1.0 - edge * 0.1)
  );

  // Temporal feedback
  let histUV = uv + vec2<f32>(sin(time * 0.18) * 0.001, cos(time * 0.12) * 0.001);
  let prev = textureSampleLevel(dataTextureC, u_sampler, histUV, 0.0).rgb;
  color = mix(color, prev * 0.94, 0.05);

  // Chromatic aberration before tonemap
  let density = 1.0 - ao;
  let depth = density * clamp(orbitMin * 2.5, 0.0, 1.0);
  let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

  let alpha = density * clamp(orbitMin * 3.0, 0.0, 1.0) * (0.8 + treble * 0.2);

  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));

  color = acesToneMap(color * 2.2);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
