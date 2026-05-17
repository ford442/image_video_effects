// ═══════════════════════════════════════════════════════════════════
//  Luma Magnetism
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Created: 2026-05-17
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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let a = hash21(i); let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0)); let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn curl(p: vec2<f32>) -> vec2<f32> {
  let e = 0.01;
  let n = noise(p); let nx = noise(p + vec2<f32>(e, 0.0)); let ny = noise(p + vec2<f32>(0.0, e));
  return vec2<f32>(-(ny - n), nx - n) / e;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / res;
  let mousePos = u.zoom_config.yz;
  let click = u.zoom_config.w > 0.5;
  let aspect = res.x / res.y;
  let diff = uv - mousePos;
  let dist = length(vec2<f32>(diff.x * aspect, diff.y));
  let origColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luma = dot(origColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let strength = u.zoom_params.x * (1.0 + plasmaBuffer[0].x * 2.0);
  let radius = max(u.zoom_params.y, 0.01);
  let hardness = u.zoom_params.z * 5.0 + 1.0;
  let threshold = u.zoom_params.w * 0.99;
  let dir = select(normalize(diff), vec2<f32>(1.0, 0.0), length(diff) < 0.0001);
  let t = dist / radius;
  let distMask = smoothstep(1.0, 0.0, t);
  let lumaMask = smoothstep(threshold, threshold + 0.05, luma);
  let falloff = pow(1.0 - t, hardness) * distMask;
  let swirl = plasmaBuffer[0].y * 0.5;
  let rotDir = vec2<f32>(dir.y, -dir.x);
  let jitter = curl(uv * 8.0 + u.config.x) * 0.015;
  var offset = (dir + rotDir * swirl + jitter) * falloff * strength * luma * 0.2 * lumaMask;
  let shock = select(0.0, 0.15 / max(dist, 0.001), click);
  offset = offset + (diff / max(dist, 0.001)) * shock;
  let dispMag = length(offset);
  let stretch = dispMag * 0.3;
  let rUV = clamp(uv + offset + dir * stretch, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv + offset - dir * stretch * 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
  let rCol = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let gCol = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let bCol = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  let glow = smoothstep(radius, 0.0, dist) * lumaMask * abs(strength) * 0.15;
  let finalRGB = vec3<f32>(rCol, gCol, bCol) + vec3<f32>(luma, luma * 0.8, luma * 0.6) * glow;
  let alpha = mix(origColor.a, 1.0, min(dispMag * 2.0, 1.0));
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
}
