// ═══════════════════════════════════════════════════════════════════
//  Predator-Prey Ecology — render
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: age cohorts on flora and fauna
//  A packing: raw sim copied back (prey, predator, nutrient, age). ACES on display only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let st = textureLoad(dataTextureC, pixel, 0);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let prey = clamp(st.r, 0.0, 1.5);
  let pred = clamp(st.g, 0.0, 1.2);
  let treble = plasmaBuffer[0].z;
  let cohort = clamp(st.a, 0.0, 1.0);

  // ── Idea 3: age cohorts. Age 0 is the original green / orange ─────
  let floraYoung = vec3<f32>(0.15, 0.85, 0.35);
  let floraOld = vec3<f32>(0.72, 0.78, 0.18);
  let faunaYoung = vec3<f32>(0.95, 0.35 + pred * 0.2, 0.12);
  let faunaOld = vec3<f32>(0.40, 0.07, 0.06);
  let flora = mix(floraYoung, floraOld, cohort) * prey;
  let fauna = mix(faunaYoung, faunaOld, cohort) * pred;
  var col = src.rgb * 0.15 + flora + fauna;
  col += vec3<f32>(st.b * 0.15, st.b * 0.08, st.b * 0.25);
  col = mix(col, col * (1.0 + treble * 0.15), clamp(prey + pred, 0.0, 1.0));

  let alpha = clamp(src.a * 0.2 + prey * 0.4 + pred * 0.35 + st.b * 0.1, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(aces(max(col, vec3<f32>(0.0))), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(mix(depth, 1.0 - clamp(prey + pred, 0.0, 1.0), 0.55), 0.0, 1.0), 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, st);
}
