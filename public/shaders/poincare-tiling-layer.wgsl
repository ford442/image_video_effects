// ═══ POINCARÉ TILING — LAYER COMPOSITE ══════════════════════════════════════

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

fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  let d = dot(b, b);
  return vec2<f32>(dot(a, b), a.y * b.x - a.x * b.y) / max(d, 1e-6);
}

fn mobius(z: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, d: vec2<f32>) -> vec2<f32> {
  return cdiv(cmul(a, z) + b, cmul(c, z) + d);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let base = textureLoad(dataTextureC, pixel, 0).rgb;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let scale = mix(0.3, 0.9, u.zoom_params.w);
  var z = (uv - vec2<f32>(0.5)) * 2.0;
  let rot = u.config.x * mix(0.1, 0.6, u.zoom_params.z);
  let layer = mobius(z, vec2<f32>(cos(rot), sin(rot)), vec2<f32>(0.0), vec2<f32>(0.0), vec2<f32>(1.0, 0.0));
  let su = clamp(vec2<f32>(0.5) + layer * scale, vec2<f32>(0.02), vec2<f32>(0.98));
  let layerCol = textureSampleLevel(readTexture, u_sampler, su, 0.0).rgb;
  var col = mix(base, layerCol, 0.45 + plasmaBuffer[0].y * 0.15);
  col = clamp(col * 1.05, vec3<f32>(0.0), vec3<f32>(1.1));
  textureStore(writeTexture, pixel, vec4<f32>(col, 1.0));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
}
