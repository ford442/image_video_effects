// Golden-frame fixture (tests/compositor-golden.swiftshader.spec.ts): a static
// gradient, the bottom layer of every composite. Not a catalog shader.
#include "_prelude.wgsl"

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(0.1 + 0.8 * uv.x, 0.15 + 0.7 * uv.y, 0.35, 1.0));
}
