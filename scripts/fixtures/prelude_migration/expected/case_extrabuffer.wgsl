// ═══════════════════════════════════════════════════════════════════
//  Fixture Swirl
//  Category: image
//  Upgraded: 2026-09-27
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const SLOT_BASE: u32 = 133u;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<i32>(u.config.zw);
  let coord = vec2<i32>(gid.xy);
  if (coord.x >= dims.x || coord.y >= dims.y) { return; }
  let uv = (vec2<f32>(coord) + 0.5) / u.config.zw;
  // keep this comment: it explains the sample
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  extraBuffer[SLOT_BASE + gid.x % 4u] = src.r;
  textureStore(writeTexture, coord, src);
}
