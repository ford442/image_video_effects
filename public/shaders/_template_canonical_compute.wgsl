// ═══════════════════════════════════════════════════════════════════
//  Canonical Compute Shader Template
//  Category: template
//  Features: canonical-bindings, alpha-passthrough, depth-passthrough
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

@compute @workgroup_size(16, 16, 1)
fn main_compute(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = textureDimensions(writeTexture);
  let coord = vec2<i32>(gid.xy);
  let dimsI = vec2<i32>(dims);

  if (any(coord >= dimsI)) {
    return;
  }

  let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, coord, vec4<f32>(src.rgb, src.a));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
