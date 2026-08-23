// ═══ OPTICAL FLOW DREAM — GRADE / RENDER ═══════════════════════════════════

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
  let flow = unpack2x16float(bitcast<u32>(st.a));
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let chroma = mix(0.0, 0.08, u.zoom_params.z) * (1.0 + plasmaBuffer[0].z);
  let dreamMix = mix(0.35, 0.92, u.zoom_params.w);
  let split = vec2<f32>(flow.x, -flow.y) * chroma * 12.0;
  let rUv = clamp(uv + split, vec2<f32>(0.001), vec2<f32>(0.999));
  let bUv = clamp(uv - split, vec2<f32>(0.001), vec2<f32>(0.999));
  let rPx = clamp(vec2<i32>(rUv * res), vec2<i32>(0), resI - vec2<i32>(1));
  let bPx = clamp(vec2<i32>(bUv * res), vec2<i32>(0), resI - vec2<i32>(1));
  let cr = textureLoad(dataTextureC, rPx, 0).r;
  let cg = st.g;
  let cb = textureLoad(dataTextureC, bPx, 0).b;
  var col = vec3<f32>(cr, cg, cb);
  col = mix(src.rgb, col, dreamMix);
  col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.6));
  let alpha = clamp(0.4 + length(col) * 0.25, 0.25, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth, 0.05, 1.0), 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(clamp(col, vec3<f32>(0.0), vec3<f32>(4.0)), st.a));
}
