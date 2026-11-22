// ═══════════════════════════════════════════════════════════════════
//  Chromatographic Fluid — Phase
//  Category: simulation
//  Features: audio-reactive, multi-pass
//  Complexity: Medium
//  Upgraded: 2026-11-22
//  Ideas: differential volatility; latent-heat cooling
//  A packing: raw dye.rgb + temperature. No display write
// ═══════════════════════════════════════════════════════════════════
//  Temperature evaporates dye into vapor sparkle; cool regions condense.

#include "_prelude.wgsl"

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let st = textureLoad(dataTextureC, pixel, 0);
  let treble = plasmaBuffer[0].z;
  var temp = clamp(st.a, 0.0, 1.0);
  let evap = smoothstep(0.45, 0.95, temp) * mix(0.01, 0.08, u.zoom_params.z);
  let cond = smoothstep(0.4, 0.0, temp) * 0.015;
  // ── Idea 1: differential volatility — blue leaves first, red stays on the paper
  let vol = vec3<f32>(0.55, 1.0, 1.45);
  var dye = max(st.rgb * (1.0 - evap * vol) + vec3<f32>(cond), vec3<f32>(0.0));
  dye += vec3<f32>(0.15, 0.4, 1.0) * evap * (0.35 + treble) * 0.4;
  dye = clamp(dye, vec3<f32>(0.0), vec3<f32>(4.0));
  // ── Idea 2: latent-heat cooling — boiling spends the heat stored in .a
  temp = clamp(temp - evap * 0.45, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(dye, temp));
}
