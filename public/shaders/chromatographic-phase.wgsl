// ═══ CHROMATOGRAPHIC FLUID — PHASE CHANGE ══════════════════════════════════
//  Temperature evaporates dye into vapor sparkle; cool regions condense.

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
  let treble = plasmaBuffer[0].z;
  var temp = clamp(st.a, 0.0, 1.0);
  let evap = smoothstep(0.45, 0.95, temp) * mix(0.01, 0.08, u.zoom_params.z);
  let cond = smoothstep(0.4, 0.0, temp) * 0.015;
  var dye = max(st.rgb * (1.0 - evap) + vec3<f32>(cond), vec3<f32>(0.0));
  dye += vec3<f32>(0.15, 0.4, 1.0) * evap * (0.35 + treble) * 0.4;
  dye = clamp(dye, vec3<f32>(0.0), vec3<f32>(4.0));
  textureStore(dataTextureA, pixel, vec4<f32>(dye, temp));
}
