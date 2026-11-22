// ═══════════════════════════════════════════════════════════════════
//  Chromatographic Fluid — Interact
//  Category: simulation
//  Features: audio-reactive, multi-pass
//  Complexity: Medium
//  Upgraded: 2026-11-22
//  Ideas: Rf competition; band edge
//  A packing: raw dye.rgb + temperature. No display write
// ═══════════════════════════════════════════════════════════════════
//  Cross-channel drag / cohesion so dyes pull and smear each other.

#include "_prelude.wgsl"

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let st = textureLoad(dataTextureC, pixel, 0);
  let dye = st.rgb;
  let mean = (dye.r + dye.g + dye.b) / 3.0;
  let drag = mix(0.04, 0.18, u.zoom_params.x);
  let mixed = mix(dye, vec3<f32>(mean), drag * 0.35);
  let sep = dye - vec3<f32>(mean);
  var outDye = mixed + sep * (0.15 + plasmaBuffer[0].z * 0.1);
  // ── Idea 1: Rf competition — the strongest channel keeps itself and crowds the other two
  let peak = max(outDye.r, max(outDye.g, outDye.b));
  let share = outDye / max(peak, 1e-3);
  outDye = outDye * (0.84 + 0.16 * share);
  let n = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(0, 1), vec2<i32>(0), resI - vec2<i32>(1)), 0).rgb;
  let s = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(0, -1), vec2<i32>(0), resI - vec2<i32>(1)), 0).rgb;
  let e = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(1, 0), vec2<i32>(0), resI - vec2<i32>(1)), 0).rgb;
  let w = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(-1, 0), vec2<i32>(0), resI - vec2<i32>(1)), 0).rgb;
  let avg = (n + s + e + w) * 0.25;
  // ── Idea 2: band edge — unsharp against the neighbor mean so spots stay bands
  outDye = outDye + (dye - avg) * 0.18;
  outDye = clamp(outDye, vec3<f32>(0.0), vec3<f32>(4.0));
  textureStore(dataTextureA, pixel, vec4<f32>(outDye, st.a));
}
