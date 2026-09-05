// ═══ CHROMATOGRAPHIC FLUID — INTERACT ══════════════════════════════════════
//  Cross-channel drag / cohesion so dyes pull and smear each other.

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let st = textureLoad(dataTextureC, pixel, 0);
  let dye = st.rgb;
  let mean = (dye.r + dye.g + dye.b) / 3.0;
  let drag = mix(0.04, 0.18, u.zoom_params.x);
  let mixed = mix(dye, vec3<f32>(mean), drag * 0.35);
  let sep = dye - vec3<f32>(mean);
  let outDye = clamp(mixed + sep * (0.15 + plasmaBuffer[0].z * 0.1), vec3<f32>(0.0), vec3<f32>(4.0));
  textureStore(dataTextureA, pixel, vec4<f32>(outDye, st.a));
}
