// ═══ BYTE-MOSH — RENDER ═══════════════════════════════════════════════════

#include "_prelude.wgsl"

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }
  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let mosh = textureLoad(dataTextureC, pixel, 0).rgb;
  let orig = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let treble = plasmaBuffer[0].z;
  var col = mix(orig, mosh, 0.85 + treble * 0.1);
  col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.2));
  textureStore(writeTexture, pixel, vec4<f32>(col, 1.0));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
}
