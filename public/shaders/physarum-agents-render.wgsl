// ═══ PHYSARUM AGENTS — RENDER (pixels) ════════════════════════════════════
//  Reads the trail field after the agents deposited (dataA → dataC barrier) and composites it over
//  the source image. Changes no state: the field the next frame diffuses is already in dataA.
//    · nutrient map        — the image, dimmed, warmer where its red channel (the agents' food) is high
//    · bioluminescent veins — trail density through a teal → cyan → white-hot glow, with a soft halo
//    · iridescent flow     — vein hue follows the trail gradient's orientation, drifting slowly
//    · living front        — texels deposited in the last ~0.15 s flare: the network's growing tips
//  A/C packing: .r trail, .g time of the last deposit on the texel

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hsv(h: f32, s: f32, v: f32) -> vec3<f32> {
  let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let p = abs(fract(vec3<f32>(h) + k) * 6.0 - vec3<f32>(3.0));
  return v * mix(vec3<f32>(1.0), clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)), s);
}

fn trailAt(p: vec2<i32>, ri: vec2<i32>) -> f32 {
  return textureLoad(dataTextureC, ((p % ri) + ri) % ri, 0).r;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let ri = vec2<i32>(u.config.zw);
  if (gid.x >= u32(ri.x) || gid.y >= u32(ri.y)) { return; }
  let p = vec2<i32>(gid.xy);
  let res = vec2<f32>(ri);
  let uv = (vec2<f32>(p) + 0.5) / res;
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let here = textureLoad(dataTextureC, p, 0);
  let trail = here.r;

  // Halo: eight taps on a ring a few texels out (the glow bleeds past the vein).
  let rr = max(2, i32(round(res.y / 360.0)));
  var halo = 0.0;
  for (var k = 0; k < 8; k = k + 1) {
    let a = f32(k) * TAU / 8.0;
    halo = halo + trailAt(p + vec2<i32>(round(vec2<f32>(cos(a), sin(a)) * f32(rr * 2))), ri);
  }
  halo = halo / 8.0;

  // Trail gradient: its orientation (mod π, so both sides of a vein agree) picks the hue.
  let gx = trailAt(p + vec2<i32>(rr, 0), ri) - trailAt(p - vec2<i32>(rr, 0), ri);
  let gy = trailAt(p + vec2<i32>(0, rr), ri) - trailAt(p - vec2<i32>(0, rr), ri);
  let orient = atan2(gy, gx) / TAU * 2.0;

  // Nutrient map.
  let src = textureLoad(readTexture, p, 0).rgb;
  let luma = dot(src, vec3<f32>(0.299, 0.587, 0.114));
  let food = clamp(src.r, 0.0, 1.0);
  var col = mix(vec3<f32>(luma), src, 0.55) * 0.32;
  col = col + vec3<f32>(0.10, 0.035, 0.0) * food;

  // Bioluminescent veins.
  let glow = 1.0 - exp(-trail * 0.9);
  let hot = smoothstep(1.2, 4.0, trail);
  let tint = hsv(fract(0.47 + orient * 0.18 + time * 0.015 + bass * 0.05), 0.75 - 0.5 * hot, 1.0);
  col = col + tint * glow * (0.9 + 0.6 * bass) + vec3<f32>(1.0, 0.95, 0.85) * hot * 0.6;
  col = col + tint * (1.0 - exp(-halo * 0.6)) * 0.35;

  // Living front.
  if (here.g > 0.0) {
    let fresh = exp(-max(time - here.g, 0.0) * 14.0);
    col = col + vec3<f32>(1.0, 0.85, 0.55) * fresh * glow * (0.5 + 0.8 * treble);
  }

  textureStore(writeTexture, p, vec4<f32>(aces(col * 1.1), 1.0));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, p, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
