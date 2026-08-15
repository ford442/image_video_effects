// ═══ CHROMATOGRAPHIC FLUID — RENDER ════════════════════════════════════════
//  False-color plate + solvent sparkle. Commits dye+temp to dataA.

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

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let st = textureLoad(dataTextureC, pixel, 0);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let dye = st.rgb;
  let temp = st.a;
  let lum = max(dye.r, max(dye.g, dye.b));
  var col = pow(dye / (dye + vec3<f32>(1.0)), vec3<f32>(0.85));
  col = mix(src.rgb * 0.15, col, 0.88);
  col += vec3<f32>(1.0, 0.7, 0.3) * temp * lum * 0.25;
  col += vec3<f32>(0.4, 0.8, 1.0) * plasmaBuffer[0].z * lum * 0.12;
  let alpha = clamp(0.35 + lum * 0.55, 0.2, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(clamp(col, vec3<f32>(0.0), vec3<f32>(1.5)), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(1.0 - lum * 0.4, 0.05, 1.0) * max(depth, 0.05), 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(clamp(dye, vec3<f32>(0.0), vec3<f32>(4.0)), clamp(temp, 0.0, 1.0)));
}
