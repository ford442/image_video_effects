// ═══════════════════════════════════════════════════════════════════
//  hybrid-spectral-decomposed
//  Category: advanced-hybrid
//  Features: pixel-sorting, spectral-decomposition, 4-band-equalizer,
//            audio-reactive, mouse-driven
//  Complexity: Very High
//  Chunks From: hybrid-spectral-sorting (pixel sorting, spectral
//               color, hue shift), alpha-spectral-decompose (4-band
//               frequency decomposition, multi-scale Gaussian)
//  Created: 2026-04-18
//  By: Agent CB-7 — Flow & Multi-Pass Enhancer
// ═══════════════════════════════════════════════════════════════════
//  4-band spectral decomposition meets audio-reactive pixel sorting.
//  Image decomposed into low/mid-low/mid-high/high frequency bands.
//  Each band is pixel-sorted independently with different thresholds
//  and spectral color tints, then recomposed with per-band gains.
//  Mouse interaction boosts high-frequency detail; audio drives
//  band energy and sort intensity.
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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

// Sample and sort a single band
fn sortBand(uv: vec2<f32>, bandEnergy: f32, sortThreshold: f32, sortDir: vec2<f32>, pixel: vec2<f32>) -> vec3<f32> {
  let neighborDist = (2.0 + bandEnergy * 8.0) / 2048.0;
  let neighborUV = uv + sortDir * neighborDist;
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let neighbor = textureSampleLevel(readTexture, u_sampler, clamp(neighborUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
  let currentLuma = rgb2luma(current);
  let neighborLuma = rgb2luma(neighbor);
  let lumaDiff = abs(currentLuma - neighborLuma);
  if (lumaDiff > sortThreshold) {
    if (currentLuma > neighborLuma) {
      return mix(current, neighbor, 0.7);
    } else {
      return mix(neighbor, current, 0.7);
    }
  }
  return current;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let id = vec2<i32>(global_id.xy);
  let ps = 1.0 / resolution;

  // Audio input
  let audio = u.zoom_config.x;
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
    }
  }

  let norm = f32(sampleCount * 3);
  bandLow /= norm;
  bandMidLow /= norm;
  bandMidHigh /= norm;
  bandHigh /= norm;

  // Difference-of-Gaussians style bands
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let lowLuma = rgb2luma(bandLow);
  let midLowLuma = rgb2luma(bandMidLow);
  let midHighLuma = rgb2luma(bandMidHigh);
  let highLuma = rgb2luma(bandHigh);

  let bandR = lowLuma;
  let bandG = midLowLuma - lowLuma * 0.5;
  let bandB = midHighLuma - midLowLuma * 0.5;
  let bandA = highLuma - midHighLuma * 0.5;

  // Store decomposition
  textureStore(dataTextureA, id, vec4<f32>(bandR, bandG, bandB, bandA));

  // ═══ PER-BAND PIXEL SORTING ═══
  let sortDir = vec2<f32>(0.0, 1.0);
  let sortedLow = sortBand(uv, bandR, sortThresholdBase * 0.5, sortDir, ps);
  let sortedMidLow = sortBand(uv, bandG, sortThresholdBase * 0.8, sortDir, ps);
  let sortedMidHigh = sortBand(uv, bandB, sortThresholdBase * 1.2, sortDir, ps);
  let sortedHigh = sortBand(uv, bandA, sortThresholdBase * 1.8, sortDir, ps);

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
  var tintedLow = mix(sortedLow, sortedLow * colorLow, bandEnergy * 0.5);
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
  // zoom_params acts as per-band gain when mapped
  let gainLow = u.zoom_params.x * 2.0 + 0.5;
  let gainMidLow = u.zoom_params.y * 2.0 + 0.5;
  let gainMidHigh = u.zoom_params.z * 2.0 + 0.5;
  let gainHigh = u.zoom_params.w * 2.0 + 0.5;

  var recomposed = vec3<f32>(0.0);
  recomposed += vec3<f32>(1.0, 0.8, 0.6) * rgb2luma(tintedLow) * gainLow;
  recomposed += vec3<f32>(0.6, 1.0, 0.7) * rgb2luma(tintedMidLow) * gainMidLow;
  recomposed += vec3<f32>(0.5, 0.7, 1.0) * rgb2luma(tintedMidHigh) * gainMidHigh;
  recomposed += vec3<f32>(1.0, 1.0, 1.0) * rgb2luma(tintedHigh) * gainHigh;

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
  recomposed += colorHigh * mouseGravity * 0.3;

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

  textureStore(writeTexture, id, vec4<f32>(recomposed, alpha));
  textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - bandEnergy * 0.2), 0.0, 0.0, 0.0));
}
