// ═══════════════════════════════════════════════════════════════════
//  Sierpinski Tetrahedron
//  Category: generative
//  Features: procedural, fractal, sierpinski, tetrahedron, 3d-projection,
//            audio-reactive, mouse-driven, chromatic-aberration, aces-tonemap,
//            temporal-feedback, depth-aware, domain-warping, multi-orbit-trap
//  Complexity: High
//  Created: 2026-05-31
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0; var a = 0.5; var f = 1.0;
  for (var i = 0; i < oct; i = i + 1) {
    s += a * valueNoise(p * f);
    f *= 2.0;
    a *= 0.5;
  }
  return s;
}

fn domainWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
  let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t), 3), fbm(p + vec2<f32>(5.2, 1.3), 3));
  return p + 0.3 * q;
}

fn rotX(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a); let s = sin(a);
  return vec3<f32>(v.x, c * v.y - s * v.z, s * v.y + c * v.z);
}

fn rotY(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a); let s = sin(a);
  return vec3<f32>(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
  let pa = p - a; let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

fn jewelColor(idx: f32, shade: f32) -> vec3<f32> {
  let j0 = vec3<f32>(0.0, 0.6, 0.3) * shade;
  let j1 = vec3<f32>(0.0, 0.3, 0.7) * shade;
  let j2 = vec3<f32>(0.7, 0.1, 0.2) * shade;
  let j3 = vec3<f32>(0.5, 0.2, 0.6) * shade;
  let f = fract(idx);
  let c1 = mix(j0, j1, clamp(f * 3.0, 0.0, 1.0));
  let c2 = mix(j1, j2, clamp((f - 0.33) * 3.0, 0.0, 1.0));
  let c3 = mix(j2, j3, clamp((f - 0.66) * 3.0, 0.0, 1.0));
  return select(select(c3, c2, f < 0.66), c1, f < 0.33);
}

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
  let angle = atan2(uv.y - 0.5, uv.x - 0.5);
  let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
  return vec3<f32>(
    color.r * (1.0 + shift.x * 0.8),
    color.g,
    color.b * (1.0 - shift.y * 0.5)
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;

  let recursion = i32(mix(4.0, 10.0, clamp(u.zoom_params.x + bass * 0.25, 0.0, 1.0)));
  let rotSpeed = mix(0.1, 0.6, u.zoom_params.y) * (1.0 + bass * 0.5);
  let persp = mix(1.5, 4.0, u.zoom_params.z);
  let caAmt = u.zoom_params.w;

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthFactor = mix(0.5, 1.5, depth);

  let warpUv = domainWarp(uv01 * 3.0 + vec2<f32>(time * 0.03), time * 0.05);
  let warpField = fbm(warpUv * 2.0, 4);

  let aspect = res.x / max(res.y, 1.0);
  var p = (uv01 - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
  p += (warpField - 0.5) * (0.04 + bass * 0.04);

  let yaw = (mouse.x - 0.5) * TAU + time * rotSpeed;
  let pitch = (mouse.y - 0.5) * PI * 0.8 + sin(time * 0.3) * 0.2;

  let v0 = vec3<f32>(0.0, 1.0, 0.0);
  let v1 = vec3<f32>(-0.816, -0.333, 0.577);
  let v2 = vec3<f32>(0.816, -0.333, 0.577);
  let v3 = vec3<f32>(0.0, -0.333, -1.155);

  var rp = vec3<f32>(p.x * persp * depthFactor, p.y * persp * depthFactor, 2.5);
  rp = rotY(rotX(rp, pitch), yaw);

  var point = rp;
  var minTrap = 1e9;
  var trapIdx = 0.0;

  for (var i = 0; i < recursion; i = i + 1) {
    let d0 = distance(point, v0);
    let d1 = distance(point, v1);
    let d2 = distance(point, v2);
    let d3 = distance(point, v3);

    var nearest = d0;
    var vi = 0.0;
    nearest = select(nearest, d1, d1 < nearest); vi = select(vi, 1.0, d1 < nearest);
    nearest = select(nearest, d2, d2 < nearest); vi = select(vi, 2.0, d2 < nearest);
    nearest = select(nearest, d3, d3 < nearest); vi = select(vi, 3.0, d3 < nearest);

    let pointTrap = min(min(d0, d1), min(d2, d3));
    let edgeTrap = min(min(min(sdCapsule(point, v0, v1, 0.0), sdCapsule(point, v0, v2, 0.0)),
                           min(sdCapsule(point, v0, v3, 0.0), sdCapsule(point, v1, v2, 0.0))),
                       min(sdCapsule(point, v1, v3, 0.0), sdCapsule(point, v2, v3, 0.0)));
    let shellTrap = abs(length(point) - 0.9) * 0.5;
    let trap = min(min(pointTrap, edgeTrap * 0.7), shellTrap);

    if trap < minTrap {
      minTrap = trap;
      trapIdx = vi;
    }

    let tgt = select(select(select(v3, v2, nearest == d2), v1, nearest == d1), v0, nearest == d0);
    point = (point + tgt) * 0.5;
  }

  let prev = textureLoad(dataTextureC, pixel, 0);
  minTrap = mix(minTrap, prev.r, 0.03 + mids * 0.02);

  let density = exp(-minTrap * 12.0);
  let edge = exp(-abs(minTrap - 0.05) * 30.0);

  var color = jewelColor(trapIdx * 0.25 + mids * 0.1 + treble * 0.05, 0.7 + density * 0.6);
  let spec = pow(edge, 4.0) * (0.8 + bass * 0.5);
  color = color + vec3<f32>(0.9, 0.85, 0.8) * spec;

  let bgGlow = vec3<f32>(0.05, 0.08, 0.12) * warpField * (1.0 - density);
  color = color + bgGlow;

  color = genChromaticShift(color, uv01, caAmt * 0.02 * (1.0 + bass), time);
  color = acesToneMap(color * (1.2 + treble * 0.1));

  let alpha = clamp(density * (f32(recursion) / 10.0) * depthFactor, 0.0, 1.0);
  let depthOut = clamp(0.3 + density * 0.7, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(minTrap, trapIdx, density, alpha));
}
