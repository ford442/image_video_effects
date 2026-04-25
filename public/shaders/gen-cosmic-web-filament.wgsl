// ═══════════════════════════════════════════════════════════════
//  Cosmic Web Filament - Evolving Large-Scale Structure
//  Category: generative
//  Features: mouse-driven
//  Physics: Multi-fractal cascade, Zel'dovich approximation,
//           stellar population synthesis, Voronoi filaments
// ═══════════════════════════════════════════════════════════════
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
const PI = 3.14159265;
fn hash33(p: vec3<f32>) -> vec3<f32> {
  var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xxy + p3.yxx) * p3.zyx);
}
fn voronoi3D(p: vec3<f32>) -> vec2<f32> {
  let i = floor(p);
  let f = fract(p);
  var res = vec2<f32>(8.0, 8.0);
  for (var k: i32 = -1; k <= 1; k++) {
    for (var j: i32 = -1; j <= 1; j++) {
      for (var i_: i32 = -1; i_ <= 1; i_++) {
        let b = vec3<f32>(f32(i_), f32(j), f32(k));
        let r = b - f + hash33(i + b);
        let d = dot(r, r);
        if (d < res.x) {
          res.y = res.x; res.x = d;
        } else if (d < res.y) {
          res.y = d;
        }
      }
    }
  }
  return sqrt(res);
}
fn fbm(p: vec3<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  for (var i: i32 = 0; i < 5; i++) {
    v += a * voronoi3D(p * (1.0 + f32(i) * 0.5)).x;
    a *= 0.5;
  }
  return v;
}
fn multifractalNoise(p: vec3<f32>, octaves: i32, H: f32) -> f32 {
  var v = 1.0;
  var a = 0.5;
  var f = 1.0;
  for (var i: i32 = 0; i < octaves; i++) {
    let n = voronoi3D(p * f).x;
    v = v * (1.0 + a * n);
    a *= H;
    f *= 2.1;
  }
  return v - 1.0;
}
fn ridgedVoronoi(p: vec3<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i: i32 = 0; i < octaves; i++) {
    let n = 1.0 - voronoi3D(p * f).x;
    v += a * n * n;
    a *= 0.5;
    f *= 2.0;
  }
  return v;
}
fn spiralWarp(p: vec3<f32>, arms: f32, pitch: f32, strength: f32) -> vec3<f32> {
  let r = length(p.xy);
  let angle = atan(p.y, p.x);
  let twist = r * pitch;
  let armPhase = fract(angle * arms / (2.0 * PI) + twist);
  let warp = sin(armPhase * 2.0 * PI) * strength;
  let c = cos(warp);
  let s = sin(warp);
  return vec3<f32>(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
}
fn stellarColor(age: f32, metallicity: f32) -> vec3<f32> {
  let young = vec3<f32>(0.8, 0.9, 1.0);
  let old = vec3<f32>(1.0, 0.7, 0.4);
  let lowMetal = vec3<f32>(0.9, 0.8, 0.7);
  let highMetal = vec3<f32>(0.6, 0.7, 1.0);
  let a = clamp(age, 0.0, 1.0);
  let m = clamp(metallicity, 0.0, 1.0);
  return mix(old, young, a) * 0.5 + mix(lowMetal, highMetal, m) * 0.5;
}
fn volumetricGlow(p: vec3<f32>, lightPos: vec3<f32>, density: f32) -> f32 {
  let dist = length(p - lightPos);
  let atten = 1.0 / (1.0 + dist * dist * 2.0);
  return density * atten * 2.0;
}
fn zeldovichDisplacement(q: vec3<f32>, t: f32) -> vec3<f32> {
  let s = t * 0.1;
  let dx = voronoi3D(q + vec3<f32>(0.01, 0.0, 0.0)).x - voronoi3D(q - vec3<f32>(0.01, 0.0, 0.0)).x;
  let dy = voronoi3D(q + vec3<f32>(0.0, 0.01, 0.0)).x - voronoi3D(q - vec3<f32>(0.0, 0.01, 0.0)).x;
  let dz = voronoi3D(q + vec3<f32>(0.0, 0.0, 0.01)).x - voronoi3D(q - vec3<f32>(0.0, 0.0, 0.01)).x;
  return vec3<f32>(dx, dy, dz) * s;
}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  var res = u.config.zw;
  if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }
  var uv = (vec2<f32>(id.xy) / res - 0.5) * vec2<f32>(res.x / res.y, 1.0) * u.zoom_config.z;
  var mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let warpStrength = u.zoom_params.x * 3.0 + bass * 0.5;
  let densityParam = u.zoom_params.y * 3.5 + 0.5;
  let speed = u.zoom_params.z * 2.0;
  let dist = length(uv - mouse);
  let force = smoothstep(0.5, 0.0, dist);
  uv -= normalize(uv - mouse + 0.001) * force * 0.8;
  var p = vec3<f32>(uv * 3.0, u.config.x * speed * 0.3);
  p += zeldovichDisplacement(p * 0.5, u.config.x * speed * 0.1);
  p = spiralWarp(p, 3.0, 0.5, warpStrength * 0.2);
  let mf = multifractalNoise(p * 0.4, 4, 0.6);
  p += mf * warpStrength * 0.3;
  let fbmDetail = fbm(p * 0.6);
  let rv = ridgedVoronoi(p * densityParam, 4);
  let v = voronoi3D(p * densityParam);
  let filament = 1.0 / (v.y - v.x + 0.001);
  let filDensity = smoothstep(0.0, 2.0, filament * 0.6) + rv * 0.3 + fbmDetail * 0.15;
  let structDensity = clamp(filDensity, 0.0, 1.0);
  let tempGrad = structDensity * (1.0 + bass * 0.5);
  let age = fract(sin(v.x * 100.0) * 43758.5453);
  let metal = fract(cos(v.y * 100.0) * 43758.5453);
  let starCol = stellarColor(age, metal);
  let glow = volumetricGlow(vec3<f32>(uv * 3.0, 0.0), vec3<f32>(mouse * 3.0, 0.0), structDensity);
  let evolution = sin(u.config.x * speed * 0.1) * 0.5 + 0.5;
  var col = vec3<f32>(0.0);
  col.r = structDensity * (0.8 + evolution * 0.4);
  col.g = tempGrad;
  col.b = dot(starCol, vec3<f32>(0.3, 0.5, 0.2));
  let alpha = clamp(structDensity + glow * 0.2, 0.0, 1.0);
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, id.xy, vec4<f32>(structDensity * 0.5, 0.0, 0.0, 0.0));
}
