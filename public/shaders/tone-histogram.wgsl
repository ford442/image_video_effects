// ═══════════════════════════════════════════════════════════════════
//  Tone Histogram
//  Category: post-processing
//  Features: audio-reactive, mouse-driven, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09, 2026-11-21, 2026-11-22
//  Ideas: mouse local metering window; per-channel shoulder; density-weighted grain (§12.2A); Wallis local-brightness pull with edge-aware coarse mean (§12.2A); H&D exponential shoulder knee (§12.2A; Shoulder Strength now rolls highlights off and is live); chroma follows the tone curve (hue-preserving ratio)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesTone(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn filmCurve(x: f32, toe: f32, shoulder: f32) -> f32 {
  let t = toe * 0.3;
  let shadow = mix(x * (1.0 + t), x, smoothstep(0.0, 0.25, x));
  // ── Idea 5: H&D exponential shoulder knee (§12.2A) ───────────────────
  // HEAD's shoulder LIFTED highlights toward 1 by <= 0.3*(1-x) and ACES flattened it
  // (Shoulder Strength moved <= 2/255). A film shoulder ROLLS OFF: above the knee
  // k = 1 - 0.5*Shoulder the signal follows k + (1-k)(1 - exp(-(x-k)/(1-k))), which is
  // value- and slope-continuous at k. Shoulder 0 => k = 1 => identity (HEAD at 0).
  let k = 1.0 - 0.5 * clamp(shoulder, 0.0, 1.1);
  let room = max(1.0 - k, 1e-3);
  let over = max(shadow - k, 0.0);
  let highlight = shadow - over + room * (1.0 - exp(-over / room));
  return clamp(highlight, 0.0, 1.0);
}

fn grain(uv: vec2<f32>, time: f32) -> f32 {
  let n = fract(sin(dot(uv + time * 0.01, vec2<f32>(12.9898, 78.233))) * 43758.5453);
  return (n - 0.5) * 0.04;
}

fn localStats(uv: vec2<f32>, texel: vec2<f32>) -> vec2<f32> {
  var sum = 0.0;
  var sumSq = 0.0;
  for (var dy: i32 = -1; dy <= 1; dy = dy + 1) {
    for (var dx: i32 = -1; dx <= 1; dx = dx + 1) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * texel;
      let c = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
      let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
      sum = sum + l;
      sumSq = sumSq + l * l;
    }
  }
  let mean = sum / 9.0;
  let variance = max(0.0, sumSq / 9.0 - mean * mean);
  return vec2<f32>(mean, sqrt(variance));
}

// ── Idea 4 helper: edge-aware coarse regional mean ──────────────────
// The 3×3 window above measures texel-scale noise; adaptive equalisation needs the
// REGIONAL brightness. Four bilinear taps at ±3.5 texels (each already a 2×2 average),
// range-weighted so the mean never averages across a real edge (no halos).
fn coarseMean(uv: vec2<f32>, texel: vec2<f32>, centerLuma: f32) -> f32 {
  var sum = centerLuma;
  var wsum = 1.0;
  for (var k: i32 = 0; k < 4; k = k + 1) {
    let o = vec2<f32>(f32(k & 1) * 2.0 - 1.0, f32(k >> 1) * 2.0 - 1.0) * 3.5 * texel;
    let c = textureSampleLevel(readTexture, u_sampler, clamp(uv + o, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let d = (l - centerLuma) / 0.12;
    let w = 1.0 / (1.0 + d * d);
    sum = sum + l * w;
    wsum = wsum + w;
  }
  return sum / wsum;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);

  // Rescue: HEAD sampled at the texel corner (gid / res) — every tap was a half-texel-shifted 2×2 blend.
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let time = u.config.x;
  let texel = 1.0 / resolution;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let stretchAmount = u.zoom_params.x;
  let toeStrength = u.zoom_params.y;
  let shoulderStrength = u.zoom_params.z;
  let hazeRemoval = u.zoom_params.w;

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let stats = localStats(uv, texel);
  let localMean = stats.x;
  let localStd = stats.y;

  // Idea 1 — spot meter at the cursor biases the stretch target.
  let mousePos = u.zoom_config.yz;
  let meterUV = clamp(mousePos, vec2<f32>(0.001), vec2<f32>(0.999));
  let meterLuma = dot(textureSampleLevel(readTexture, u_sampler, meterUV, 0.0).rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let meterWeight = 0.35 + 0.25 * u.zoom_config.w;
  let stretchRef = mix(localMean, meterLuma, meterWeight);

  let targetStd = mix(0.12, 0.28, stretchAmount + bass * 0.12);
  // Rescue: HEAD hard-switched gain 1.0 → ×2.5 at localStd = 0.001, so 8-bit gradient band edges
  // (std ≥ 0.001) jumped straight to max gain while band interiors stayed at 1 (dashed banding, and
  // flat skies got the MOST boost). Same gain, now eased in continuously as real structure appears.
  let adaptGain = mix(1.0, targetStd / max(localStd, 0.01), smoothstep(0.002, 0.03, localStd));
  let adaptGainClamped = clamp(adaptGain, 0.5, 2.5);

  let luma = dot(src.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let chroma = src.rgb - vec3<f32>(luma);

  // ── Idea 4: Wallis local-brightness pull (§12.2A) ────────────────────
  // adaptGain is the std half of Wallis; this is the mean half: the target mean drifts
  // toward mid-grey by how far the REGIONAL mean sits from it. Rides Stretch Amount (0 → HEAD).
  let coarse = coarseMean(uv, texel, luma);
  let stretchTarget = stretchRef + (0.5 - coarse) * 0.3 * stretchAmount;
  var stretchedLuma = (luma - stretchRef) * adaptGainClamped + stretchTarget;
  stretchedLuma = clamp(stretchedLuma, 0.0, 1.0);
  let curvedLuma = filmCurve(stretchedLuma, toeStrength, shoulderStrength);

  // Idea 2 — per-channel shoulder (dye rolloff, luma curve still drives midtones).
  let rCurve = filmCurve(src.r, toeStrength, shoulderStrength * 1.08);
  let gCurve = filmCurve(src.g, toeStrength, shoulderStrength);
  let bCurve = filmCurve(src.b, toeStrength, shoulderStrength * 0.92);
  let dyeRgb = vec3<f32>(rCurve, gCurve, bCurve);
  let dyeLuma = dot(dyeRgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let dyeChroma = dyeRgb - vec3<f32>(dyeLuma);

  let shadowTint = vec3<f32>(0.06, 0.05, 0.10) * (1.0 - smoothstep(0.0, 0.3, curvedLuma));
  let highlightTint = vec3<f32>(0.10, 0.07, 0.03) * smoothstep(0.7, 1.0, curvedLuma);
  let splitTone = shadowTint + highlightTint;

  // ── Idea 6: chroma follows the tone curve (hue-preserving ratio) ─────
  // HEAD added the colour difference to the CURVED luma unchanged: a shadow lifted x2 kept its
  // old (now relatively thin) colour, a highlight the shoulder pulled down kept its old
  // (now relatively neon) colour. Scale the colour difference by the local tone gain
  // curvedLuma/luma, bounded 0.6..1.8, weighted by Stretch Amount (0 => HEAD).
  let toneGain = clamp((curvedLuma + 0.02) / (luma + 0.02), 0.6, 1.8);
  let chromaFollow = mix(1.0, toneGain, 0.75 * stretchAmount);

  var color = vec3<f32>(curvedLuma) + mix(chroma, dyeChroma, 0.55) * chromaFollow * mix(0.8, 1.4, stretchAmount) + splitTone * 0.3;

  // ── Idea 3: density-weighted grain (§12.2A) ──────────────────────────
  // Real grain peaks in the midtones and vanishes in clear base / dense blacks:
  // σ(L) = √(L(1−L)). The flat hash grain below is kept; only its amplitude follows density.
  let density = sqrt(max(curvedLuma * (1.0 - curvedLuma), 0.0)) * 2.0;
  let g1 = grain(uv, time) * (1.0 + mids * 0.5);
  let g2 = grain(uv * 1.7 + 0.3, time * 0.7) * 0.5;
  color = color + vec3<f32>(g1 + g2) * mix(0.25, 1.0, density);

  let mouseDown = u.zoom_config.w;
  let mouseDist = length(uv - mousePos);
  let exposureZone = smoothstep(0.25, 0.0, mouseDist) * mouseDown;
  color = color * (1.0 + exposureZone * 0.4);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  // Rescue: HEAD mixed the far pixels TOWARD the haze colour (the slider added haze).
  // Koschmieder inversion removes it: I = J·t + A·(1−t)  ⇒  J = (I − A·h)/(1 − h), h = 1 − t.
  let haze = (1.0 - depth) * hazeRemoval * 0.3;
  let hazeColor = vec3<f32>(0.75, 0.78, 0.82);
  color = (color - hazeColor * haze) / max(1.0 - haze, 0.05);

  let finalColor = acesTone(max(color, vec3<f32>(0.0)));
  let tonalConfidence = smoothstep(0.0, 0.15, abs(curvedLuma - localMean) + localStd);
  let localContrast = smoothstep(0.0, 0.2, localStd) * 0.5 + 0.5;
  let alpha = clamp(src.a * 0.25 + tonalConfidence * localContrast * depth + 0.18, 0.15, 0.95);
  let outColor = vec4<f32>(finalColor, alpha);

  textureStore(writeTexture, coord, outColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, outColor);
}
