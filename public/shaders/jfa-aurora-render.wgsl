// ═══ JFA AURORA — RENDER ════════════════════════════════════════════════════

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

fn aurora(h: f32, t: f32) -> vec3<f32> {
  return vec3<f32>(
    0.35 + 0.65 * sin(h * 6.28 + t),
    0.4 + 0.5 * sin(h * 6.28 + t * 1.3 + 1.0),
    0.55 + 0.45 * sin(h * 6.28 + t * 0.7 + 2.0),
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let st = textureLoad(dataTextureC, pixel, 0);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let dist = sqrt(max(st.z, 0.0));
  let hue = st.w + dist * mix(1.0, 4.0, u.zoom_params.y) + plasmaBuffer[0].y * 0.2;
  let glow = mix(0.15, 1.2, u.zoom_params.z);
  var col = aurora(hue, time * mix(0.2, 1.0, u.zoom_params.y)) * glow * (1.0 - dist * 2.5);
  col += src * 0.12;
  col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.6));

  textureStore(writeTexture, pixel, vec4<f32>(col, 1.0));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, st);
}
