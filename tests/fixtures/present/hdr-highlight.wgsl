// HDR present fixture (tests/hdr-present.swiftshader.spec.ts): a constant colour whose
// red channel is 3.0 in linear light (an HDR highlight), green 0.5, blue 0.25.
// Not a catalog shader.
#include "_prelude.wgsl"

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(3.0, 0.5, 0.25, 1.0));
}
