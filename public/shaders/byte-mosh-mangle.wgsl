// ═══ BYTE-MOSH — MANGLE (bitcast bitwise) ═══════════════════════════════════

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

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let mixOp = u.zoom_params.x;
  let shift = u32(mix(0.0, 12.0, u.zoom_params.y));
  let err = mix(0.0, 1.0, u.zoom_params.z + plasmaBuffer[0].x * 0.2);
  let block = max(1.0, mix(2.0, 32.0, u.zoom_params.w));
  let bx = floor(uv.x * block) / block;
  let by = floor(uv.y * block) / block;
  let h = hash12(vec2<f32>(bx, by) + u.config.x * 0.01);
  var packed = bitcast<u32>(src.r) ^ bitcast<u32>(src.g) ^ bitcast<u32>(src.b);
  if (h < err) {
    packed = packed ^ u32(f32(pixel.x) * 13.0 + f32(pixel.y) * 7.0);
    packed = (packed << shift) | (packed >> (32u - shift));
    let mask = u32(mix(4294967295.0, 16711935.0, mixOp));
    packed = packed & mask;
  }
  let out = vec3<f32>(bitcast<f32>(packed), bitcast<f32>(packed ^ 0x9e3779b9u), bitcast<f32>(packed ^ 0x517cc1b7u));
  textureStore(dataTextureA, pixel, vec4<f32>(clamp(out, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0));
}
