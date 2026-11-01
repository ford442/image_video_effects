// ═══════════════════════════════════════════════════════════════════
//  PP Bloom
//  Category: post-processing
//  Features: audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-06, 2026-10-31
//  Ideas: hue-preserving bright extract; horizontal anamorphic streak; energy-conserving composite (§12.2F); Cauchy fringe on the streak (§12.2F)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const QUALITY_LOW: i32 = 4;
const QUALITY_MED: i32 = 8;
const QUALITY_HIGH: i32 = 16;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn cauchyScale(bDisp: f32) -> vec3<f32> {
  let lam2 = vec3<f32>(0.4225, 0.3025, 0.2025);
  let n = 1.0 + bDisp / lam2;
  return n / max(n.y, 1e-4);
}

fn extractBright(color: vec3<f32>, threshold: f32) -> vec3<f32> {
  let l = luma(color);
  let knee = threshold * 0.5;
  let soft = max(l - threshold + knee, 0.0);
  let softContribution = min(soft, knee) * (soft / max(knee, 0.001));
  let contribution = max(l - threshold, 0.0) + softContribution;
  return color * (contribution / max(l, 0.001));
}

fn sampleBright(uv: vec2<f32>, threshold: f32) -> vec3<f32> {
  let s = textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  return extractBright(s.rgb, threshold);
}

fn getWeights(taps: i32) -> array<f32, 16> {
  if (taps == 4) {
    return array<f32, 16>(0.383, 0.242, 0.061, 0.006, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
  }
  if (taps == 8) {
    return array<f32, 16>(0.199, 0.176, 0.121, 0.065, 0.028, 0.009, 0.002, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
  }
  return array<f32, 16>(0.088, 0.085, 0.079, 0.070, 0.059, 0.047, 0.035, 0.024, 0.015, 0.008, 0.004, 0.002, 0.001, 0.0, 0.0, 0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let invRes = 1.0 / res;

  let bass = plasmaBuffer[0].x;
  let treble = plasmaBuffer[0].z;

  let intensity = u.zoom_params.x * (1.0 + treble * 0.25);
  let anamorphic = u.zoom_params.y;
  let threshold = clamp(u.zoom_params.z - bass * 0.08, 0.0, 1.0);
  let qualityParam = u.zoom_params.w;

  var taps: i32 = QUALITY_MED;
  if (qualityParam < 0.33) {
    taps = QUALITY_LOW;
  } else if (qualityParam >= 0.66) {
    taps = QUALITY_HIGH;
  }

  let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let bright0 = extractBright(original.rgb, threshold);
  let weights = getWeights(taps);
  let radius = 4.0 + intensity * 8.0;
  let stretch = 1.0 + anamorphic * 2.0;

  var blurred = bright0 * weights[0];
  var totalWeight = weights[0];

  for (var i: i32 = 0; i < taps; i = i + 1) {
    let dist = f32(i + 1) / f32(taps);
    let ox = invRes.x * dist * radius;
    let oy = invRes.y * dist * radius * stretch;
    let offset = vec2<f32>(ox, oy);
    let h1 = sampleBright(uv + vec2<f32>(ox, 0.0), threshold);
    let h2 = sampleBright(uv - vec2<f32>(ox, 0.0), threshold);
    let v1 = sampleBright(uv + vec2<f32>(0.0, oy), threshold);
    let v2 = sampleBright(uv - vec2<f32>(0.0, oy), threshold);
    let d1 = sampleBright(uv + offset, threshold);
    let d2 = sampleBright(uv - offset, threshold);
    let d3 = sampleBright(uv + vec2<f32>(ox, -oy), threshold);
    let d4 = sampleBright(uv + vec2<f32>(-ox, oy), threshold);
    let avg = (h1 + h2 + v1 + v2 + d1 + d2 + d3 + d4) * 0.125;
    blurred += avg * weights[i];
    totalWeight += weights[i];
  }
  blurred = blurred / max(totalWeight, 1e-4);

  // Idea 2: extra 1D horizontal streak using the anamorphic control
  var streak = bright0 * 0.35;
  let streakTaps = 6;
  for (var s: i32 = 1; s <= streakTaps; s = s + 1) {
    let t = f32(s) / f32(streakTaps);
    let w = exp(-t * t * 4.0);
    let sx = invRes.x * t * radius * (1.5 + anamorphic * 4.0);
    // ── Idea 4: Cauchy fringe on the horizontal streak (§12.2F) ────
    let scales = cauchyScale(0.04 + 0.22 * anamorphic);
    let sxR = sx * scales.x;
    let sxB = sx * scales.z;
    let plusR = sampleBright(uv + vec2<f32>(sxR, 0.0), threshold);
    let plusG = sampleBright(uv + vec2<f32>(sx, 0.0), threshold);
    let plusB = sampleBright(uv + vec2<f32>(sxB, 0.0), threshold);
    let minusR = sampleBright(uv - vec2<f32>(sxR, 0.0), threshold);
    let minusG = sampleBright(uv - vec2<f32>(sx, 0.0), threshold);
    let minusB = sampleBright(uv - vec2<f32>(sxB, 0.0), threshold);
    streak += vec3<f32>(plusR.r + minusR.r, plusG.g + minusG.g, plusB.b + minusB.b) * w;
  }
  streak = streak / (0.35 + 2.0 * 6.0 * 0.4);
  let streakMix = anamorphic * intensity;

  let lensDirt = 1.0 - length(uv - 0.5) * 0.5;
  let spread = blurred * intensity * 2.0 + streak * streakMix * 1.4 + blurred * intensity * 0.3 * lensDirt;
  // ── Idea 3: energy-conserving composite (§12.2F) ────────────────
  // Highlights that bloom give some of that light up instead of doubling.
  let take = clamp(luma(spread) * 0.28, 0.0, 0.45);
  var hdr = original.rgb * (1.0 - take) + spread;

  let display = acesToneMap(hdr);
  let bloomLuma = luma(blurred + streak * streakMix);
  let alpha = clamp(original.a * 0.5 + bloomLuma * 0.8, 0.0, 1.0);
  let outCol = vec4<f32>(display, alpha);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
