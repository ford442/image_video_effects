// ═══════════════════════════════════════════════════════════════
//  Cosmic Web Filament - Evolving Large-Scale Structure
//  Category: generative
//  Features: mouse-driven, audio-reactive, audio-driven, temporal, chromatic, depth-aware
//  Complexity: High
//  Physics: Multi-fractal cascade, Zel'dovich approximation,
//           stellar population synthesis, Voronoi filaments,
//           SDF voids, domain warping, quaternion rotation, Apollonian fractals
//  Upgraded: 2026-06-28
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
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(clamp(u.zoom_params.w, 0.0, 1.0) * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(controlled, color.a);
}

const PI = 3.14159265;
const PHI = 1.6180339887;

fn hash33(p: vec3<f32>) -> vec3<f32> {
  var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn hash31(p: vec3<f32>) -> f32 {
  var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn snoise3(p: vec3<f32>) -> f32 {
  let s = vec3<f32>(floor(p.x + p.y + p.z) / 3.0);
  let i = floor(p + s);
  let f = p - i;
  let g = step(f.yzx, f.xyz);
  let l = 1.0 - g;
  let o1 = min(g.xyz, l.zxy);
  let o2 = max(g.xyz, l.zxy);
  let c1 = i + o1;
  let c2 = i + o2;
  let c3 = i + vec3<f32>(1.0);
  let h0 = hash33(i);
  let h1 = hash33(c1);
  let h2 = hash33(c2);
  let h3 = hash33(c3);
  let w0 = f;
  let w1 = f - o1;
  let w2 = f - o2;
  let w3 = f - vec3<f32>(1.0);
  let d0 = dot(w0, w0);
  let d1 = dot(w1, w1);
  let d2 = dot(w2, w2);
  let d3 = dot(w3, w3);
  var w = vec4<f32>(0.0);
  w.x = max(0.5 - d0, 0.0); w.x = w.x * w.x * w.x;
  w.y = max(0.5 - d1, 0.0); w.y = w.y * w.y * w.y;
  w.z = max(0.5 - d2, 0.0); w.z = w.z * w.z * w.z;
  w.w = max(0.5 - d3, 0.0); w.w = w.w * w.w * w.w;
  return dot(w, vec4<f32>(dot(w0, h0 - 0.5), dot(w1, h1 - 0.5), dot(w2, h2 - 0.5), dot(w3, h3 - 0.5))) * 32.0;
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
        if (d < res.x) { res.y = res.x; res.x = d; }
        else if (d < res.y) { res.y = d; }
      }
    }
  }
  return sqrt(res);
}

fn fbm(p: vec3<f32>) -> f32 {
  var v = 0.0; var a = 0.5;
  for (var i: i32 = 0; i < 5; i++) {
    v += a * voronoi3D(p * (1.0 + f32(i) * 0.5)).x;
    a *= 0.5;
  }
  return v;
}

fn multifractalNoise(p: vec3<f32>, octaves: i32, H: f32) -> f32 {
  var v = 1.0; var a = 0.5; var f = 1.0;
  for (var i: i32 = 0; i < octaves; i++) {
    let n = voronoi3D(p * f).x;
    v = v * (1.0 + a * n);
    a *= H; f *= 2.1;
  }
  return v - 1.0;
}

fn ridgedVoronoi(p: vec3<f32>, octaves: i32) -> f32 {
  var v = 0.0; var a = 0.5; var f = 1.0;
  for (var i: i32 = 0; i < octaves; i++) {
    let n = 1.0 - voronoi3D(p * f).x;
    v += a * n * n; a *= 0.5; f *= 2.0;
  }
  return v;
}

fn domainWarp(p: vec3<f32>, t: f32) -> vec3<f32> {
  let q = vec3<f32>(
    fbm(p + vec3<f32>(0.0, 0.0, t * 0.1)),
    fbm(p + vec3<f32>(5.2, 1.3, t * 0.1)),
    fbm(p + vec3<f32>(1.7, 9.2, t * 0.1))
  );
  return p + q * 0.5;
}

fn sdfSphere(p: vec3<f32>, r: f32) -> f32 { return length(p) - r; }

fn sdfTorus(p: vec3<f32>, t_: vec2<f32>) -> f32 {
  let q = vec2<f32>(length(p.xy) - t_.x, p.z);
  return length(q) - t_.y;
}

fn sdfBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
  let q = abs(p) - b;
  return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn quaternionRotate(p: vec3<f32>, axis: vec3<f32>, angle: f32) -> vec3<f32> {
  let a = normalize(axis);
  let s = sin(angle * 0.5);
  let c = cos(angle * 0.5);
  let q = vec4<f32>(a * s, c);
  let t = 2.0 * cross(q.xyz, p);
  return p + q.w * t + cross(q.xyz, t);
}

fn spiralWarp(p: vec3<f32>, arms: f32, pitch: f32, strength: f32) -> vec3<f32> {
  let r = length(p.xy);
  let angle = atan2(p.y, p.x);
  let twist = r * pitch;
  let armPhase = fract(angle * arms / (2.0 * PI) + twist);
  let warp = sin(armPhase * 2.0 * PI) * strength;
  let c = cos(warp); let s = sin(warp);
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

fn apollonianEstimate(p: vec3<f32>, scale: f32) -> f32 {
  var z = p; var dr = 1.0; var r = 0.0;
  for (var i: i32 = 0; i < 4; i++) {
    r = length(z);
    if (r > 4.0) { break; }
    let theta = acos(clamp(z.z / r, -1.0, 1.0)) * scale;
    let phi = atan2(z.y, z.x) * scale;
    dr = pow(r, scale - 1.0) * scale * dr + 1.0;
    z = pow(r, scale) * vec3<f32>(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta)) + p;
  }
  return 0.5 * log(r) * r / dr;
}

fn kleinWarp(p: vec3<f32>, t: f32) -> vec3<f32> {
  let u_ = p.x * 0.5 + t * 0.05;
  let v_ = p.y * 0.5;
  let cu = cos(u_); let su = sin(u_);
  let cv = cos(v_); let sv = sin(v_);
  let a = 0.3;
  let bx = (a + cu) * sv;
  let by = (a + cu) * cv;
  let bz = -su;
  return p + vec3<f32>(bx, by, bz) * 0.1;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  var res = u.config.zw;
  if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }
  let uv01 = vec2<f32>(id.xy) / res;
  var uv = (vec2<f32>(id.xy) / res - 0.5) * vec2<f32>(res.x / res.y, -1.0) * u.zoom_config.z;
  var mouse = (vec2<f32>(u.zoom_config.y, 1.0 - u.zoom_config.z) - 0.5) * u.zoom_config.z;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
  let warpStrength = zp.x * 3.0 + bass * 0.5;
  let densityParam = zp.y * 3.5 + 0.5;
  let speed = zp.z * 2.0;
  let dist = length(uv - mouse);
  let force = smoothstep(0.5, 0.0, dist);
  uv -= normalize(uv - mouse + 0.001) * force * 0.8;
  var p = vec3<f32>(uv * 3.0, u.config.x * speed * 0.3);
  p += zeldovichDisplacement(p * 0.5, u.config.x * speed * 0.1);
  p = spiralWarp(p, 3.0, 0.5, warpStrength * 0.2);
  p = domainWarp(p, u.config.x * speed * 0.2);
  p = quaternionRotate(p, vec3<f32>(0.3, 0.7, 0.5), u.config.x * speed * 0.15);
  p = kleinWarp(p, u.config.x * speed);
  let voidSDF = min(
    min(sdfSphere(p - vec3<f32>(mouse * 3.0, 0.0), 0.4 + bass * 0.2), sdfTorus(p - vec3<f32>(mouse * 3.0, 0.0), vec2<f32>(0.5, 0.15))),
    sdfBox(p + vec3<f32>(mouse * 2.0, 0.0), vec3<f32>(0.3))
  );
  let apollo = apollonianEstimate(p * 0.5, 2.0 + mids);
  let noise3 = snoise3(p * 0.8 + u.config.x * speed * 0.1);
  let mf = multifractalNoise(p * 0.4, 4, 0.6);
  p += mf * warpStrength * 0.3;
  let fbmDetail = fbm(p * 0.6);
  let rv = ridgedVoronoi(p * densityParam, 4);
  let v = voronoi3D(p * densityParam);
  let filament = 1.0 / (v.y - v.x + 0.001);
  let filDensity = smoothstep(0.0, 2.0, filament * 0.6) + rv * 0.3 + fbmDetail * 0.15 + noise3 * 0.1;
  let structDensity = clamp(filDensity * smoothstep(-0.1, 0.1, -voidSDF) * smoothstep(0.0, 0.5, apollo), 0.0, 1.0);
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
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0);
  col = mix(col, prev.rgb * 0.9, 0.03 + bass * 0.01);
  let cStr = 0.003 + bass * 0.005;
  let cDir = normalize(uv01 - vec2<f32>(0.5) + 0.001);
  let prevR = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * (1.0 + mids), 0.0).r;
  let prevG = textureSampleLevel(dataTextureC, u_sampler, uv01 + cDir * cStr * (0.5 + treble), 0.0).g;
  let prevB = textureSampleLevel(dataTextureC, u_sampler, uv01 - cDir * cStr * (0.8 + bass * 0.5), 0.0).b;
  col.r = mix(col.r, prevR * 0.9, 0.02 + treble * 0.01);
  col.g = mix(col.g, prevG * 0.9, 0.02 + bass * 0.01);
  col.b = mix(col.b, prevB * 0.9, 0.02 + mids * 0.01);
  let alpha = 1.0;
  textureStore(writeTexture, id.xy, applyGenerativePrimaryControls(vec4<f32>(col, alpha)));
  textureStore(writeDepthTexture, id.xy, vec4<f32>(structDensity * 0.5, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, id.xy, vec4<f32>(col, alpha));
}
