// ═══════════════════════════════════════════════════════════════════
//  JFA Aurora Voronoi — flood
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: halving jump schedule (extraBuffer[133] at (0,0))
//  A packing: raw flood field (seed xy, dist², id)
// ═══════════════════════════════════════════════════════════════════
//  Reads/writes: (seed.xy, dist², seed_id)

#include "_prelude.wgsl"

fn load(p: vec2<i32>, resI: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), resI - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;

  // ── Idea 1: halving jump. Jump Scale is the first step. ───────────
  // Default 0.5 → 128, then 64…1. The sum matches the old fixed 32×8 reach.
  let floodPass = u32(clamp(extraBuffer[133], 0.0, 7.0));
  let base = u32(max(1.0, mix(1.0, 256.0, u.zoom_params.x)));
  let jump = i32(max(base >> floodPass, 1u));

  var best = load(pixel, resI);
  var bestD2 = best.z;
  let missing = best.x < 0.0;
  bestD2 = select(bestD2, 1e6, missing);

  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      let np = pixel + vec2<i32>(dx, dy) * jump;
      let n = load(np, resI);
      let live = n.x >= 0.0;
      let d2 = dot(uv - n.xy, uv - n.xy);
      let better = live && d2 < bestD2;
      bestD2 = select(bestD2, d2, better);
      best = select(best, vec4<f32>(n.xy, d2, n.w), better);
    }
  }

  textureStore(dataTextureA, pixel, vec4<f32>(best.xy, bestD2, best.w));

  if (gid.x == 0u && gid.y == 0u) {
    extraBuffer[133] = f32(floodPass + 1u);
  }
}
