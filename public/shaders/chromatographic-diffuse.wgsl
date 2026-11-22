// ═══════════════════════════════════════════════════════════════════
//  Chromatographic Fluid — Diffuse
//  Category: simulation
//  Features: multi-pass
//  Complexity: Medium
//  Upgraded: 2026-11-22
//  Ideas: paper saturation; heat run
//  A packing: raw dye.rgb + temperature. No display write
// ═══════════════════════════════════════════════════════════════════
//  Per-channel viscosity: R sticky, B runny. Repeat 2× under pass budget.

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

  let split = u.zoom_params.x;
  let visR = mix(0.08, 0.42, 1.0 - split);
  let visG = mix(0.12, 0.28, split);
  let visB = mix(0.18, 0.55, split);
  let vis = vec3<f32>(visR, visG, visB);

  let c = load(pixel, resI);
  let n = load(pixel + vec2<i32>(0, 1), resI).rgb;
  let s = load(pixel + vec2<i32>(0, -1), resI).rgb;
  let e = load(pixel + vec2<i32>(1, 0), resI).rgb;
  let w = load(pixel + vec2<i32>(-1, 0), resI).rgb;
  let lap = (n + s + e + w) * 0.25 - c.rgb;
  // ── Idea 1: paper saturation — dense dye diffuses less
  let mass = max(c.r + c.g + c.b, 0.0);
  let sat = 1.0 / (1.0 + mass * 0.35);
  // ── Idea 2: heat run — warm solvent (temperature already in .a) runs farther
  let heat = 0.7 + 0.6 * clamp(c.a, 0.0, 1.0);
  let dye = clamp(c.rgb + lap * vis * sat * heat, vec3<f32>(0.0), vec3<f32>(4.0));
  textureStore(dataTextureA, pixel, vec4<f32>(dye, c.a));
}
