// ═══════════════════════════════════════════════════════════════
//  Faceted Gem with Caustics
//  Category: generative
//  Description: Raymarched faceted gems with subsurface scattering,
//               caustic lighting, and organic domain warping.
//  Features: mouse-driven, raymarched, caustics
//  Tags: crystal, gem, caustics, 3d, raymarching, subsurface
//  Author: ford442
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

fn sdSphere(p: vec3<f32>, r: f32) -> f32 { return length(p) - r; }

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
  var q = abs(p) - b; return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
  let q = abs(p);
  return (q.x + q.y + q.z - s) * 0.57735027;
}

fn sdHexPrism(p: vec3<f32>, h: vec2<f32>) -> f32 {
  let q = abs(p);
  let d1 = q.y - h.y;
  let d2 = max(q.x * 0.866025 + q.z * 0.5, q.z) - h.x;
  return length(max(vec2<f32>(d1, d2), vec2<f32>(0.0))) + min(max(d1, d2), 0.0);
}

fn sdPyramid(p: vec3<f32>, h: f32) -> f32 {
  let m2 = h * h + 0.25;
  var q = p;
  q.x = abs(q.x);
  let a = q.x - min(q.x, select((m2 - q.y * q.y) / (2.0 * q.y + 2.0), 1.0, q.y < 0.0));
  let b = sqrt(q.x * q.x + q.z * q.z);
  let d2 = min(b, q.y + h);
  return sqrt(min(b * b + a * a, d2 * d2 - m2 * min(d2 * d2, m2)));
}

// FBM domain warp for organic erosion
fn warpDomain(p: vec3<f32>, time: f32) -> vec3<f32> {
  var wp = p;
  wp.x = wp.x + sin(wp.y * 2.3 + time * 0.4) * 0.15;
  wp.y = wp.y + cos(wp.z * 1.7 + time * 0.3) * 0.12;
  wp.z = wp.z + sin(wp.x * 2.1 + time * 0.5) * 0.10;
  wp.x = wp.x + sin(wp.z * 3.1 + time * 0.2) * 0.08;
  return wp;
}

// Caustic intensity from 4 light sources
fn causticIntensity(p: vec3<f32>, sources: array<vec3<f32>, 4>, time: f32) -> f32 {
  var c = 0.0;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    let dir = normalize(sources[i] - p);
    let dist = length(sources[i] - p);
    let wave = sin(dist * 12.0 - time * 4.0) * cos(dir.x * 8.0 + time * 2.0);
    c = c + max(0.0, wave) / (1.0 + dist * 0.5);
  }
  return c * 0.5;
}

// Subsurface scattering approximation
fn subsurfaceScattering(p: vec3<f32>, n: vec3<f32>, l: vec3<f32>, thickness: f32, albedo: vec3<f32>) -> vec3<f32> {
  let wrap = 0.5;
  let ndotl = dot(n, l);
  let diff = clamp((ndotl + wrap) / (1.0 + wrap), 0.0, 1.0);
  let scatter = exp(-thickness * 3.0) * (1.0 - diff);
  return albedo * (diff + scatter * vec3<f32>(1.2, 0.8, 0.6));
}

fn map(p: vec3<f32>, scale: f32, pulse: f32, time: f32, audioReactivity: f32) -> vec2<f32> {
  let ps = warpDomain(p * scale, time);
  var d = ps.y + 1.5;
  d = min(d, length(ps.xz) - 12.0 + sin(ps.y * 2.0) * 0.8);
  let cell = floor(ps * 0.8);
  var q = ps - cell * 1.25;
  let tmod = sin(time * pulse * audioReactivity * 8.0 + length(cell)) * 0.3;
  let id = (cell.x + cell.y + cell.z) % 3.0;
  var crystal: f32;
  if (id < 1.0) { crystal = sdOctahedron(q + vec3<f32>(0.0, tmod, 0.0), 0.5); }
  else if (id < 2.0) { crystal = sdHexPrism(q + vec3<f32>(0.0, tmod, 0.0), vec2<f32>(0.35, 0.5)); }
  else { crystal = sdPyramid(q + vec3<f32>(0.0, tmod, 0.0), 0.5); }
  let finalD = min(d, crystal * (1.0 + id * 0.2));
  return vec2<f32>(finalD, 2.0);
}

fn getNormal(p: vec3<f32>, scale: f32, pulse: f32, time: f32, audioReactivity: f32) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let nx = map(p + e.xyy, scale, pulse, time, audioReactivity).x;
  let ny = map(p + e.yxy, scale, pulse, time, audioReactivity).x;
  let nz = map(p + e.yyx, scale, pulse, time, audioReactivity).x;
  let c = map(p, scale, pulse, time, audioReactivity).x;
  return normalize(vec3<f32>(nx - c, ny - c, nz - c));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let res = u.config.zw;
  let time = u.config.x;
  let audioBass = plasmaBuffer[0].x;
  let audioMid = plasmaBuffer[0].y;
  let audioHigh = plasmaBuffer[0].z;
  let audioReactivity = 1.0 + audioBass * 0.5;
  var mouse = u.zoom_config.yz;
  if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }
  var uv = (vec2<f32>(id.xy) / res - 0.5) * vec2<f32>(res.x / res.y, 1.0) * u.zoom_config.z;
  let scale = u.zoom_params.x * 1.9 + 0.1;
  let glowIntensity = u.zoom_params.z * 2.0;
  let fogDensity = u.zoom_params.w * 2.0;
  let mouseAngle = mouse.x * 6.28;
  var ro = vec3<f32>(sin(mouseAngle) * 10.0, 3.0, cos(mouseAngle) * 10.0);
  let lookAt = vec3<f32>(0.0, 0.0, 0.0);
  let fwd = normalize(lookAt - ro);
  let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
  let up = cross(fwd, right);
  let rd = normalize(fwd + uv.x * right + uv.y * up);
  var t = 0.0;
  var mat = 0.0;
  for (var i: i32 = 0; i < 100; i = i + 1) {
    var p = ro + rd * t;
    let r = map(p, scale, 0.5, time, audioReactivity);
    if (r.x < 0.001) { mat = r.y; break; }
    t = t + r.x * 0.9;
    if (t > 80.0) { break; }
  }
  var col = vec3<f32>(0.01, 0.005, 0.03);
  if (t < 79.0) {
    var p = ro + rd * t;
    let n = getNormal(p, scale, 0.5, time, audioReactivity);
    let lightDir = normalize(vec3<f32>(0.5, 1.0, 0.3));
    let sources = array<vec3<f32>, 4>(
      vec3<f32>(3.0, 4.0, 2.0), vec3<f32>(-3.0, 3.0, -2.0),
      vec3<f32>(0.0, 5.0, 4.0), vec3<f32>(2.0, 2.0, -3.0)
    );
    let caustics = causticIntensity(p, sources, time) * glowIntensity;
    if (mat > 1.5) {
      let sss = subsurfaceScattering(p, n, lightDir, 0.3, vec3<f32>(0.6, 0.8, 1.0));
      let glow = pow(glowIntensity * 1.5 + sin(time * 8.0 * audioReactivity) * 0.3, 2.0);
      col = vec3<f32>(0.4, 0.8, 1.0) * glow + vec3<f32>(0.6, 0.3, 1.0) * 0.6;
      col = col + sss * 0.4 + vec3<f32>(0.8, 0.9, 1.0) * caustics * 0.5;
    } else {
      let sss = subsurfaceScattering(p, n, lightDir, 0.8, vec3<f32>(0.4, 0.3, 0.2));
      col = vec3<f32>(0.15, 0.1, 0.08) + caustics * vec3<f32>(0.3, 0.25, 0.4) * 0.3;
      col = col + sss * 0.15;
    }
  }
  let mouseLight = max(0.0, 1.0 - length(uv - mouse) * 3.0);
  col = col + vec3<f32>(0.8, 0.6, 1.0) * mouseLight * 0.8;
  var alpha = 0.0;
  if (t < 79.0) { alpha = clamp(1.0 - t / 80.0 * fogDensity, 0.05, 1.0); }
  alpha = alpha * (0.2 + 0.8 * mouseLight);
  textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, alpha));
  var depth = 0.5;
  if (t < 79.0) { depth = 1.0 - (t / 80.0); }
  textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
