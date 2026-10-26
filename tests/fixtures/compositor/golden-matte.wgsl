// Golden-frame fixture: a grey ramp for a `mask` slot (luma matte = uv.y). Not a catalog shader.
#include "_prelude.wgsl"

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(vec3<f32>(uv.y), 1.0));
}
