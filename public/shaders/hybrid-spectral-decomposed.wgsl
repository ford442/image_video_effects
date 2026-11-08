// ═══════════════════════════════════════════════════════════════════
//  hybrid-spectral-decomposed
//  Category: advanced-hybrid
//  Features: pixel-sorting, spectral-decomposition, 4-band-equalizer,
//            audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Very High
//  Chunks From: hybrid-spectral-sorting (pixel sorting, spectral
//               color, hue shift), alpha-spectral-decompose (4-band
//               frequency decomposition, multi-scale Gaussian)
//  Created: 2026-04-18
//  By: Agent CB-7 — Flow & Multi-Pass Enhancer
//  Upgraded: 2026-11-08
//  Ideas: audio-spectrum band EQ (bass→low … treble→high); band-rotated
//         sort axes; threshold-gated streak runs
//  A packing: rgba = signed DoG band lumas (low, midLow, midHigh, high)
// ═══════════════════════════════════════════════════════════════════
//  4-band spectral decomposition meets audio-reactive pixel sorting.
//  Image decomposed into low/mid-low/mid-high/high frequency bands.
//  Each band is pixel-sorted independently with different thresholds
//  and spectral color tints, then recomposed with per-band gains.
//  Mouse interaction boosts high-frequency detail; audio drives
//  band energy and sort intensity.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735, 0.57735, 0.57735);
  let cosAngle = cos(hue);
  return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

fn rgb2luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// Sample and sort a single band.
// Idea: threshold-gated streak runs — instead of one neighbour swap, walk
// up to 6 steps along the band's sort axis while the luma step stays above
// threshold, dragging the brighter run end down the streak (pixel-sort run).
fn sortBand(uv: vec2<f32>, bandEnergy: f32, sortThreshold: f32, sortDir: vec2<f32>, pixel: vec2<f32>) -> vec3<f32> {
  let stepLen = (2.0 + abs(bandEnergy) * 8.0) * max(pixel.x, pixel.y) * 1.5;
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  var runCol = current;
  var runMax = current;
  var prevLuma = rgb2luma(current);
  var runLen = 0.0;
  for (var k = 1; k <= 6; k = k + 1) {
    let suv = clamp(uv - sortDir * stepLen * f32(k), vec2<f32>(0.0), vec2<f32>(1.0));
    let c = textureSampleLevel(readTexture, u_sampler, suv, 0.0).rgb;
    let l = rgb2luma(c);
    if (abs(l - prevLuma) < sortThreshold * 0.35 && k > 1) { break; }
    runCol += c;
    if (l > rgb2luma(runMax)) { runMax = c; }
    prevLuma = l;
    runLen += 1.0;
  }
  if (runLen < 1.0) { return current; }
  let runMean = runCol / (runLen + 1.0);
  // Brighter pixels sink along the run (sorted order), mean fills the body.
  return mix(current, mix(runMean, runMax, 0.55), clamp(runLen / 6.0, 0.0, 1.0) * 0.8);
}

fn acesFit(x: vec3<f32>) -> vec3<f32> {
  let c = max(x, vec3<f32>(0.0)); // negative input maps bright under the fit
  return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let id = vec2<i32>(global_id.xy);
  let ps = 1.0 / resolution;

  // Audio input (was u.zoom_config.x — not audio; plasmaBuffer[0] is)
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let audio = bass;
  let bassPulse = 1.0 + audio * 0.5;

  // Parameters
  let sortThresholdBase = mix(0.05, 0.35, u.zoom_params.x);
  let spectralBands = mix(4.0, 32.0, u.zoom_params.y);
  let displacement = mix(0.0, 0.15, u.zoom_params.z);
  let hueShiftAmount = u.zoom_params.w * 3.14159;

  // Mouse interaction
  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;
  let distToMouse = length(uv - mousePos);
  let mouseGravity = 1.0 - smoothstep(0.0, 0.3, distToMouse);
  let clickPulse = select(0.0, 1.0, isMouseDown) * sin(distToMouse * 30.0 - time * 6.0) * exp(-distToMouse * 4.0);

  // ═══ 4-BAND SPECTRAL DECOMPOSITION ═══
  var bandLow = vec3<f32>(0.0);
  var bandMidLow = vec3<f32>(0.0);
  var bandMidHigh = vec3<f32>(0.0);
  var bandHigh = vec3<f32>(0.0);

  var wsL = 0.0; var wsML = 0.0; var wsMH = 0.0; var wsH = 0.0;
  let sampleCount = 8;
  for (var i = 0; i < sampleCount; i = i + 1) {
    let angle = f32(i) * 6.283185307 / f32(sampleCount);
    for (var r = 1; r <= 3; r = r + 1) {
      let radius = f32(r) * 2.0 * ps.x;
      let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
      let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
      let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
      let dist = f32(r);
      let wLow = exp(-dist * dist / 8.0);
      let wMidLow = exp(-dist * dist / 3.0);
      let wMidHigh = exp(-dist * dist / 1.0);
      let wHigh = exp(-dist * dist / 0.3);
      bandLow += sampleColor * wLow;
      bandMidLow += sampleColor * wMidLow;
      bandMidHigh += sampleColor * wMidHigh;
      bandHigh += sampleColor * wHigh;
      wsL += wLow; wsML += wMidLow; wsMH += wMidHigh; wsH += wHigh;
    }
  }

  // Normalize each Gaussian (old /24 left bandHigh ≈ 0.036·L — dead band)
  // and include the centre tap so the narrow kernels converge to source.
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  bandLow = (bandLow + sourceColor) / (wsL + 1.0);
  bandMidLow = (bandMidLow + sourceColor) / (wsML + 1.0);
  bandMidHigh = (bandMidHigh + sourceColor) / (wsMH + 1.0);
  bandHigh = (bandHigh + sourceColor) / (wsH + 1.0);

  // Difference-of-Gaussians bands (sum exactly reconstructs source luma)
  let lowLuma = rgb2luma(bandLow);
  let midLowLuma = rgb2luma(bandMidLow);
  let midHighLuma = rgb2luma(bandMidHigh);
  let highLuma = rgb2luma(bandHigh);

  let srcLuma = rgb2luma(sourceColor);
  let bandR = lowLuma;
  let bandG = midLowLuma - lowLuma;
  let bandB = midHighLuma - midLowLuma;
  let bandA = (highLuma - midHighLuma) + (srcLuma - highLuma);

  // Store decomposition
  textureStore(dataTextureA, id, vec4<f32>(bandR, bandG, bandB, bandA));

  // ═══ PER-BAND PIXEL SORTING ═══
  // Idea: band-rotated sort axes — each frequency band sorts along its own
  // angle (low ↓, midLow ↘, midHigh →, high ↗) so streaks cross-hatch by
  // frequency; mids slowly precess the fan.
  let fan = mids * 0.4 + sin(time * 0.15) * 0.1;
  let dLow = vec2<f32>(sin(fan), cos(fan));
  let dMidLow = vec2<f32>(sin(0.785 + fan), cos(0.785 + fan));
  let dMidHigh = vec2<f32>(sin(1.571 + fan), cos(1.571 + fan));
  let dHigh = vec2<f32>(sin(2.356 + fan), cos(2.356 + fan));
  let sortedLow = sortBand(uv, bandR, sortThresholdBase * 0.5, dLow, ps);
  let sortedMidLow = sortBand(uv, bandG * 4.0, sortThresholdBase * 0.8, dMidLow, ps);
  let sortedMidHigh = sortBand(uv, bandB * 4.0, sortThresholdBase * 1.2, dMidHigh, ps);
  let sortedHigh = sortBand(uv, bandA * 4.0, sortThresholdBase * 1.8, dHigh, ps);

  // Spectral band index for coloring
  let band = floor(uv.y * spectralBands);
  let bandPhase = band / spectralBands;
  let spectralNoise = hash12(vec2<f32>(bandPhase * 10.0, time * 0.5)) * 0.5 + 0.5;
  let bandEnergy = spectralNoise * (0.5 + audio * 0.5);

  // ═══ PER-BAND SPECTRAL COLORING ═══
  let colorLow = palette(bandPhase + time * 0.05,
    vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0, 1.0, 0.5), vec3<f32>(0.0, 0.33, 0.67)
  );
  let colorMidLow = palette(bandPhase * 1.3 + time * 0.07,
    vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0, 0.5, 1.0), vec3<f32>(0.33, 0.67, 0.0)
  );
  let colorMidHigh = palette(bandPhase * 1.7 + time * 0.09,
    vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(0.5, 1.0, 1.0), vec3<f32>(0.67, 0.0, 0.33)
  );
  let colorHigh = palette(bandPhase * 2.1 + time * 0.11,
    vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0, 0.5, 0.5), vec3<f32>(0.0, 0.67, 0.33)
  );

  // Apply color tints to sorted bands
  var tintedLow = mix(sortedLow, sortedLow * colorLow * 1.6, bandEnergy * 0.8);
  var tintedMidLow = mix(sortedMidLow, sortedMidLow * colorMidLow, bandEnergy * 0.5);
  var tintedMidHigh = mix(sortedMidHigh, sortedMidHigh * colorMidHigh, bandEnergy * 0.5);
  var tintedHigh = mix(sortedHigh, sortedHigh * colorHigh, bandEnergy * 0.5);

  // Hue shift per band
  tintedLow = hueShift(tintedLow, hueShiftAmount * bandPhase * 0.5 + audio * 0.3);
  tintedMidLow = hueShift(tintedMidLow, hueShiftAmount * bandPhase * 0.8 + audio * 0.4);
  tintedMidHigh = hueShift(tintedMidHigh, hueShiftAmount * bandPhase * 1.2 + audio * 0.5);
  tintedHigh = hueShift(tintedHigh, hueShiftAmount * bandPhase * 1.5 + audio * 0.6);

  // ═══ DISPLACEMENT PER BAND ═══
  let dispVec = vec2<f32>(
    sin(bandPhase * 6.28318 + time) * bandEnergy,
    cos(bandPhase * 6.28318 + time * 0.7) * bandEnergy
  ) * displacement * (1.0 + mouseGravity * 2.0) + normalize(uv - mousePos + 0.001) * clickPulse * 0.05;

  let displacedUV = uv + dispVec * bassPulse;
  let displaced = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

  // ═══ RECOMPOSITION WITH PARAM GAINS ═══
  // Idea: audio-spectrum band EQ — the 4 image bands ride the matching
  // audio bands (bass→low, mids→mid bands, treble→high detail), so a kick
  // swells the soft base and hats crisp up edges. (Old gains re-used the
  // four sliders a second time and summed to ~5× luma → white wash.)
  let gainLow = 1.0 + bass * 0.35;
  let gainMidLow = 1.2 + mids * 0.8;
  let gainMidHigh = 1.4 + mids * 0.5 + treble * 0.5;
  let gainHigh = 1.6 + treble * 1.4;

  // Low band carries colour (sorted + tinted); the three DoG detail bands
  // are re-added as tinted signed luma so recomposition ≈ source at gain 1.
  let lowCol = tintedLow * (lowLuma / max(rgb2luma(sortedLow), 1e-3));
  var recomposed = vec3<f32>(0.0);
  recomposed += mix(sourceColor, lowCol, 0.85) * (srcLuma - bandG - bandB - bandA) / max(srcLuma, 1e-3) * gainLow;
  recomposed += vec3<f32>(0.6, 1.0, 0.7) * normalize(tintedMidLow + 1e-3) * 1.732 * bandG * gainMidLow;
  recomposed += vec3<f32>(0.5, 0.7, 1.0) * normalize(tintedMidHigh + 1e-3) * 1.732 * bandB * gainMidHigh;
  recomposed += normalize(tintedHigh + 1e-3) * 1.732 * bandA * gainHigh;
  // Sorted streaks of the detail bands show through as their own layer.
  let sortedDetail = (sortedMidLow + sortedMidHigh + sortedHigh) / 3.0 - sourceColor;
  recomposed += sortedDetail * 0.8;
  recomposed = max(recomposed, vec3<f32>(0.0));

  // Add back some original and displaced for recognizability
  recomposed = mix(recomposed, displaced, 0.25);
  recomposed = mix(recomposed, sourceColor, 0.15);
  recomposed = clamp(recomposed, vec3<f32>(0.0), vec3<f32>(1.5));

  // Mouse radial high-frequency boost
  let mouseInfluence = smoothstep(0.3, 0.0, distToMouse) * select(0.0, 1.0, isMouseDown);
  recomposed += vec3<f32>(bandA * mouseInfluence * 3.0);
  recomposed = clamp(recomposed, vec3<f32>(0.0), vec3<f32>(1.5));

  // Ripple pulses add high band energy
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rDist = length(uv - ripple.xy);
    let age = time - ripple.z;
    if (age < 0.8 && rDist < 0.15) {
      let pulse = smoothstep(0.15, 0.0, rDist) * max(0.0, 1.0 - age);
      recomposed += vec3<f32>(bandA * pulse * 3.0);
    }
  }
  recomposed = clamp(recomposed, vec3<f32>(0.0), vec3<f32>(1.5));

  // Audio-reactive glow
  let glow = bandEnergy * audio * 0.4;
  recomposed += colorMidHigh * glow;
  recomposed += colorHigh * mouseGravity * 0.3 * select(0.35, 1.0, isMouseDown);

  // Glitch on beat
  let beat = step(0.7, audio);
  if (beat > 0.0) {
    let glitchOffset = vec2<f32>(hash12(uv + time) - 0.5, 0.0) * 0.02 * beat;
    let glitchColor = textureSampleLevel(readTexture, u_sampler, uv + glitchOffset, 0.0).rgb;
    recomposed = mix(recomposed, glitchColor, 0.25);
  }

  recomposed = clamp(recomposed, vec3<f32>(0.0), vec3<f32>(2.0));

  let spectralEnergy = abs(bandR) + abs(bandG) + abs(bandB) + abs(bandA);
  let alpha = mix(0.7, 1.0, spectralEnergy * 0.2 + bandEnergy * 0.3);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, id, vec4<f32>(acesFit(recomposed * 1.15), alpha));
  textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - bandEnergy * 0.2), 0.0, 0.0, 0.0));
}
