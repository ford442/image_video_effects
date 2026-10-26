// Golden-frame fixture: fbm + hsv colour through the _half.wgsl helpers, always f32
// (no `@requires f16` header). The reference for its f16 twin. Not a catalog shader.
#include "_prelude.wgsl"
#include "_half.wgsl"

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let n = h_fbm(uv * 6.0, 5);
  let rgb = h_hsv2rgb(hv3(hf(0.6) * n + hf(0.1), hf(0.7), hf(0.35) + hf(0.6) * n));
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(vec3<f32>(h_srgbToLinear(rgb)), 1.0));
}
