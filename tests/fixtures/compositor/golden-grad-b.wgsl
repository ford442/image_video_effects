// Golden-frame fixture: the blended layer. Alpha ramps with x so the `slotN`
// (alpha matte) mask has something to measure; it stays >= 0.5 because the
// thumbnail readback encodes through a premultiplied 2D canvas, which would
// quantise the colour of a nearly transparent texel. Not a catalog shader.
#include "_prelude.wgsl"

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(0.9 - 0.7 * uv.x, 0.55, 0.2 + 0.7 * uv.y, 0.5 + 0.5 * uv.x));
}
