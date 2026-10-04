// ═══ OPTICAL FLOW DREAM — GRADE / RENDER ═══════════════════════════════════

#include "_prelude.wgsl"

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
