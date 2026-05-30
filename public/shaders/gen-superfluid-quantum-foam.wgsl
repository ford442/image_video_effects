// ═══════════════════════════════════════════════════════════════════
//  Superfluid Quantum-Foam
//  Category: generative
//  Features: mouse-driven, audio-reactive, raymarched
//  Complexity: High
//  Created: 2026-05-30
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

fn hash13(p3: vec3<f32>) -> f32 {
  var p = fract(p3 * 0.1031);
  p += dot(p, p.yzx + 33.33);
  return fract((p.x + p.y) * p.z);
}

fn hash33(p3: vec3<f32>) -> vec3<f32> {
  var p = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
  p += dot(p, p.yxz + 33.33);
  return fract((p.xxy + p.yyxx) * p.zyx);
}

fn curlNoise(p: vec3<f32>) -> vec3<f32> {
  let e = vec3<f32>(0.01, 0.0, 0.0);
  let n1 = hash33(p + e);
  let n2 = hash33(p - e);
  let n3 = hash33(p + e.zxy);
  let n4 = hash33(p - e.zxy);
  let n5 = hash33(p + e.yzx);
  let n6 = hash33(p - e.yzx);
  return vec3<f32>(n4.z - n3.z - n6.y + n5.y, n6.x - n5.x - n2.z + n1.z, n3.y - n4.y - n1.y + n2.y) * 12.5;
}

fn map(p: vec3<f32>) -> vec2<f32> {
  let t = u.config.x;
  let bass = plasmaBuffer[0].x;
  let env = 1.0 + bass * 2.0;
  var pos = p + curlNoise(p * 0.5 + t * 0.1) * 0.3 * env;
  
  let m = vec3<f32>((u.zoom_config.y * 2.0 - 1.0) * 10.0, (u.zoom_config.z * 2.0 - 1.0) * 5.0, 0.0);
  let dm = length(p - m);
  let vr = u.zoom_params.y;
  if (dm < vr) {
    pos += normalize(m - p) * (vr - dm) * 0.5;
    let s = sin(dm);
    let c = cos(dm);
    let xz = pos.xz * mat2x2<f32>(c, -s, s, c);
    pos.x = xz.x;
    pos.z = xz.y;
  }
  
  let sp = 3.0 / env;
  var cell = floor(pos / sp);
  pos = pos - sp * round(pos / sp);
  let boil = hash13(cell) * sin(t * 3.0 + bass * 10.0) * u.zoom_params.x;
  let r = (0.6 + hash13(cell + 1.0) * 0.6) * env + boil;
  return vec2<f32>(length(pos) - r, hash13(cell));
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
  return normalize(e.xyy * map(p + e.xyy).x + e.yyx * map(p + e.yyx).x + e.yxy * map(p + e.yxy).x + e.xxx * map(p + e.xxx).x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let coords = vec2<i32>(global_id.xy);
  let dims = textureDimensions(writeTexture);
  if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) { return; }
  
  let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dims)) / f32(dims.y);
  let t = u.config.x;
  let bass = plasmaBuffer[0].x;
  let env = 1.0 + bass * 2.0;
  
  let ro = vec3<f32>(0.0, 0.0, -8.0 + t * u.zoom_params.w);
  let rd = normalize(vec3<f32>(uv, 1.0));
  var dist = 0.0;
  var glow = 0.0;
  
  for (var i = 0; i < 80; i++) {
    let p = ro + rd * dist;
    let res = map(p);
    if (res.x < 0.5) { glow += (0.5 - res.x) * 0.08 * u.zoom_params.z; }
    if (res.x < 0.001 || dist > 30.0) { break; }
    dist += res.x * 0.5;
  }
  
  var col = vec3<f32>(0.02, 0.0, 0.05);
  var alpha = 0.0;
  
  if (dist < 30.0) {
    let p = ro + rd * dist;
    let n = calcNormal(p);
    let v = -rd;
    let ndotv = clamp(dot(n, v), 0.0, 1.0);
    let irid = 0.5 + 0.5 * cos(6.28318 * (vec3<f32>(1.0, 1.0, 1.0) * ndotv + vec3<f32>(0.0, 0.33, 0.67)));
    let dif = clamp(dot(n, normalize(vec3<f32>(0.8, 0.7, -0.6))), 0.0, 1.0);
    col = mix(vec3<f32>(0.1, 0.1, 0.2), irid, 0.6) * dif;
    col = mix(col, vec3<f32>(0.02, 0.0, 0.05), 1.0 - exp(-0.02 * dist * dist));
    alpha = clamp(1.0 - exp(-0.05 * dist), 0.0, 1.0) * (0.4 + 0.6 * dif);
  }
  
  let flash = vec3<f32>(0.8, 0.1, 1.0) * glow * env;
  col += flash;
  alpha = max(alpha, glow * 0.5);
  
  let lum = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
  col = max(col, lum * vec3<f32>(0.3, 0.2, 0.4));
  
  textureStore(writeTexture, coords, vec4<f32>(col * alpha, alpha));
  textureStore(writeDepthTexture, coords, vec4<f32>(min(dist / 30.0, 1.0), 0.0, 0.0, 1.0));
}
