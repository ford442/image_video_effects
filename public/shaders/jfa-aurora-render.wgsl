// ═══════════════════════════════════════════════════════════════════
//  JFA Aurora Voronoi — render
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: cell-wall curtains
//  A packing: raw flood field copied back. ACES on display only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn aurora(h: f32, t: f32) -> vec3<f32> {
  return vec3<f32>(
    0.35 + 0.65 * sin(h * 6.28 + t),
    0.4 + 0.5 * sin(h * 6.28 + t * 1.3 + 1.0),
    0.55 + 0.45 * sin(h * 6.28 + t * 0.7 + 2.0),
  );
}

fn distAt(p: vec2<i32>, hi: vec2<i32>) -> f32 {
  let s = textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0);
  return sqrt(max(s.z, 0.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  let resI = vec2<i32>(res);
  if (pixel.x >= resI.x || pixel.y >= resI.y) { return; }

  let uv = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let hi = resI - vec2<i32>(1);
  let st = textureLoad(dataTextureC, pixel, 0);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let dist = distAt(pixel, hi);
  let hue = st.w + dist * mix(1.0, 4.0, u.zoom_params.y) + plasmaBuffer[0].y * 0.2;
  let glow = mix(0.15, 1.2, u.zoom_params.z);
  let tint = aurora(hue, time * mix(0.2, 1.0, u.zoom_params.y));
  var col = tint * glow * (1.0 - dist * 2.5);
  col += src * 0.12;

  // ── Idea 2: cell-wall curtains. The distance gradient is the wall ─
  let edge = abs(distAt(pixel + vec2<i32>(1, 0), hi) - distAt(pixel + vec2<i32>(-1, 0), hi))
           + abs(distAt(pixel + vec2<i32>(0, 1), hi) - distAt(pixel + vec2<i32>(0, -1), hi));
  let filament = smoothstep(0.015, 0.11, edge);
  let sheet = sin(uv.y * 34.0 + time * 0.65 + dist * 18.0);
  let band = sheet * sheet;
  col = col + tint * filament * (0.35 + glow * 0.45) * (0.45 + 0.55 * band);

  col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.6));
  let alpha = clamp(0.2 + glow * 0.15 + filament * 0.55 + dist * 0.2, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(aces(col), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(mix(depth, filament, 0.45), 0.0, 1.0), 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, st);
}
