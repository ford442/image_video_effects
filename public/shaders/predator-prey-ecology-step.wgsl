// ═══════════════════════════════════════════════════════════════════
//  Predator-Prey Ecology — step
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: Holling type II intake; nutrient grazing scar; age-raised death
//  A packing: raw sim (prey, predator, nutrient, age)
// ═══════════════════════════════════════════════════════════════════
//  A/C packing: .r prey, .g predator, .b nutrient, .a age
//  zoom_params: .x eat rate, .y death, .z mutation, .w breed

#include "_prelude.wgsl"

fn load(p: vec2<i32>, resI: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), resI - vec2<i32>(1)), 0);
}

fn laplaceAt(p: vec2<i32>, resI: vec2<i32>, ch: i32) -> f32 {
  let c = load(p, resI);
  let n = load(p + vec2<i32>(0, 1), resI);
  let s = load(p + vec2<i32>(0, -1), resI);
  let e = load(p + vec2<i32>(1, 0), resI);
  let w = load(p + vec2<i32>(-1, 0), resI);
  let center = select(c.g, c.r, ch == 0);
  let sum = select(n.g + s.g + e.g + w.g, n.r + s.r + e.r + w.r, ch == 0);
  return sum * 0.25 - center;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let eat = mix(0.08, 0.45, u.zoom_params.x) + mid * 0.04;
  let death = mix(0.02, 0.18, u.zoom_params.y);
  let mutate = mix(0.0, 0.12, u.zoom_params.z + bass * 0.05);
  let breed = mix(0.05, 0.35, u.zoom_params.w);

  var st = load(pixel, resI);
  var prey = st.r;
  var pred = st.g;
  var nutrient = st.b;
  var age = st.a;

  let cold = time < 0.08;
  prey = select(prey, 0.15 + nutrient * 0.1, cold);
  pred = select(pred, 0.05, cold);

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let photoLuma = dot(src.rgb, vec3<f32>(0.299, 0.587, 0.114));

  let lapP = laplaceAt(pixel, resI, 0);
  let lapPred = laplaceAt(pixel, resI, 1);

  // ── Idea 1: Holling type II intake ────────────────────────────────
  // Mass-action prey×predator saturates. response == prey at prey ≈ 0.3,
  // so a moderate field still matches the old Lotka–Volterra step.
  let halfSat = 0.7;
  let response = prey * (halfSat + 0.3) / max(halfSat + prey, 0.001);
  // ── Idea 3: age raises death; Death Rate still owns the base ──────
  let deathAged = death * (1.0 + 0.28 * clamp(age, 0.0, 1.0));
  let growth = prey * (nutrient * 0.8 + 0.1) - response * pred * eat;
  let predGrowth = pred * (response * eat * 1.2 - deathAged);
  prey = clamp(prey + growth * 0.35 + lapP * 0.12 + mutate * nutrient, 0.0, 1.5);
  pred = clamp(pred + predGrowth * 0.3 + lapPred * 0.08, 0.0, 1.2);

  // ── Idea 2: nutrient grazing scar, then the photo refills at 0.04 ─
  let grazed = nutrient - prey * (0.012 + eat * 0.02);
  nutrient = clamp(mix(grazed, photoLuma, 0.04), 0.0, 1.2);

  let inBrush = length(uv - mouse) < 0.08;
  let seed = select(0.0, 1.0, held && inBrush);
  prey = prey + breed * 0.25 * seed;
  pred = pred + breed * 0.08 * seed;

  let nRipple = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nRipple; i = i + 1u) {
    let rp = u.ripples[i];
    let ageR = time - rp.z;
    let bloom = select(0.0, (1.0 - ageR / 0.35) * breed * 0.4, ageR > 0.0 && ageR < 0.35 && length(uv - rp.xy) < 0.04);
    prey = prey + bloom;
  }

  age = fract(age + 0.002 + pred * 0.001);
  textureStore(dataTextureA, pixel, vec4<f32>(prey, pred, nutrient, age));
  let cover = clamp(prey * 0.45 + pred * 0.4, 0.0, 1.0);
  textureStore(writeDepthTexture, pixel, vec4<f32>(1.0 - cover, 0.0, 0.0, 0.0));
}
