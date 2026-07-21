// ═══════════════════════════════════════════════════════════════════
//  Luma Pixel Sort — Swarm Optimizer Upgrade (2026-07-21)
//  Category: post-processing
//  Features: upgraded-rgba, mouse-driven, audio-reactive, depth-aware,
//            branchless-sort, threshold-early-exit, param-sort-angle,
//            cosine-palette-tint
//  Complexity: Medium
//  Upgraded: 2026-07-08 (Phase B) → 2026-07-21 (Optimizer pass)
//
//  Optimizer notes (2026-07-21):
//  • Sort direction is now param-wired: Param3 (0–1) maps to 0–180°
//    and rotates the Fibonacci disk sampling axis, so sorted spans can
//    be steered instead of staying on a fixed orientation.
//  • Audio-reactive threshold refinement: bass energy smoothly lowers
//    the luma threshold (on top of the existing treble/mids terms) so
//    beats extend the sorted spans into darker material.
//  • Cosine-palette tint on sorted spans, blended by Param4 (Palette
//    Mix). 0 disables the tint; small values grade the spans subtly.
//  • Depth Blend and Noise Mix are now tuned constants (the two least
//    interactive sliders), freeing Param3/Param4 for angle + palette.
//  • UNCHANGED: the 25-comparator sorting network, the threshold
//    early exit, the zero-radius early exit, and all write paths.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const LUMA_WEIGHTS: vec3<f32> = vec3<f32>(0.2126, 0.7152, 0.0722);
const SAMPLES: u32 = 8u;
const SORT_SAMPLE_COUNT: u32 = 9u;

// Tuned constants for the two sliders retired by the Optimizer pass.
// DEPTH_BLEND keeps its original 0.5 default; NOISE_MIX keeps 0.3.
const DEPTH_BLEND: f32 = 0.5;
const NOISE_MIX: f32 = 0.3;
// Bass threshold-drop shaping: beats pull the luma threshold down by
// up to this amount, letting sorted spans grow on the low end.
const BASS_THRESHOLD_DROP: f32 = 0.2;
// Span-width range (in luma units) over which the palette tint fades in.
const SPAN_TINT_LO: f32 = 0.02;
const SPAN_TINT_HI: f32 = 0.35;

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, LUMA_WEIGHTS);
}

fn fibonacciDiskOffset(i: u32, radius: f32) -> vec2<f32> {
  let angle = f32(i) * 2.3999632297;
  let r = radius * sqrt(f32(i + 1u) / f32(SAMPLES + 1u));
  return vec2<f32>(cos(angle), sin(angle)) * r;
}

// Rotate a 2D offset by `angle` radians. Used to steer the sort axis.
fn rotateOffset(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let c = cos(angle);
  let s = sin(angle);
  return vec2<f32>(c * v.x - s * v.y, s * v.x + c * v.y);
}

// Cosine palette (IQ-style): cheap periodic grade for tinting spans.
fn cosinePalette(t: f32) -> vec3<f32> {
  let a = vec3<f32>(0.5, 0.5, 0.5);
  let b = vec3<f32>(0.5, 0.5, 0.5);
  let c = vec3<f32>(1.0, 1.0, 1.0);
  let d = vec3<f32>(0.0, 0.33, 0.67);
  return a + b * cos(TAU * (c * t + d));
}

// Branchless swap of a color+luma pair into ascending luma order.
fn sortPair(
  lumas: ptr<function, array<f32, 9>>,
  colors: ptr<function, array<vec4<f32>, 9>>,
  a: u32,
  b: u32
) {
  let la = (*lumas)[a];
  let lb = (*lumas)[b];
  let ca = (*colors)[a];
  let cb = (*colors)[b];
  let swap = la > lb;
  (*lumas)[a] = select(la, lb, swap);
  (*lumas)[b] = select(lb, la, swap);
  (*colors)[a] = select(ca, cb, swap);
  (*colors)[b] = select(cb, ca, swap);
}

// Optimal 25-comparator sorting network for 9 elements.
// Verified to sort all 9! permutations; replaces the prior 36-comparator
// insertion-sort network with identical output semantics.
// DO NOT MODIFY — compare-exchange sequence is load-bearing (see brief).
fn sortByLuma(lumas: ptr<function, array<f32, 9>>, colors: ptr<function, array<vec4<f32>, 9>>) {
  // Layer 1
  sortPair(lumas, colors, 0u, 3u); sortPair(lumas, colors, 1u, 7u);
  sortPair(lumas, colors, 2u, 5u); sortPair(lumas, colors, 4u, 8u);
  // Layer 2
  sortPair(lumas, colors, 0u, 7u); sortPair(lumas, colors, 2u, 4u);
  sortPair(lumas, colors, 3u, 8u); sortPair(lumas, colors, 5u, 6u);
  // Layer 3
  sortPair(lumas, colors, 0u, 2u); sortPair(lumas, colors, 1u, 3u);
  sortPair(lumas, colors, 4u, 5u); sortPair(lumas, colors, 7u, 8u);
  // Layer 4
  sortPair(lumas, colors, 1u, 4u); sortPair(lumas, colors, 3u, 6u);
  sortPair(lumas, colors, 5u, 7u);
  // Layer 5
  sortPair(lumas, colors, 0u, 1u); sortPair(lumas, colors, 2u, 4u);
  sortPair(lumas, colors, 3u, 5u); sortPair(lumas, colors, 6u, 8u);
  // Layer 6
  sortPair(lumas, colors, 2u, 3u); sortPair(lumas, colors, 4u, 5u);
  sortPair(lumas, colors, 6u, 7u);
  // Layer 7
  sortPair(lumas, colors, 1u, 2u); sortPair(lumas, colors, 3u, 4u);
  sortPair(lumas, colors, 5u, 6u);
}

// Convenience writer used by every early-exit path so that all three
// required outputs are always populated.
fn writeOutputs(pixel: vec2<i32>, color: vec4<f32>, depth: f32) {
  textureStore(writeTexture, pixel, color);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, color);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / res;
  let invRes = 1.0 / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  // Parameter unpacking (exactly four sliders, index 0–3).
  //   x = Luma Threshold  (base cutoff for the sort pipeline)
  //   y = Sort Length     (Fibonacci disk radius, 0–64 px)
  //   z = Sort Angle      (0–1 mapped to 0–180°, steers the span axis)
  //   w = Palette Mix     (cosine-palette tint strength on sorted spans)
  let threshold = u.zoom_params.x;
  let sortLengthBase = u.zoom_params.y;
  let sortAngleParam = u.zoom_params.z;
  let paletteMix = clamp(u.zoom_params.w, 0.0, 1.0);

  // Audio analysis (hoisted out of the sampling loop).
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Depth-aware early exit for sky / background pixels.
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let bgMask = step(0.99, depth) * step(0.01, DEPTH_BLEND);
  if (bgMask > 0.5) {
    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    writeOutputs(pixel, c, depth);
    return;
  }

  // Centre pixel and luma.
  let centerColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let centerLuma = luma(centerColor.rgb);

  // Audio-reactive threshold modulation: treble/mids shave the cutoff as
  // before, and bass now smoothly drops it further so beats extend spans.
  // smoothstep keeps the bass term soft instead of twitchy.
  let bassDrop = smoothstep(0.15, 1.2, bass) * BASS_THRESHOLD_DROP;
  let localThreshold = clamp(threshold - treble * 0.25 - mids * 0.1 - bassDrop, 0.0, 1.0);

  // Early exit: dark pixels never get sorted, so skip the whole kernel.
  let aboveThreshold = centerLuma >= localThreshold;
  if (!aboveThreshold) {
    let dimColor = vec4<f32>(centerColor.rgb, centerColor.a * 0.3);
    writeOutputs(pixel, dimColor, depth);
    return;
  }

  // Bass expands sort radius; mouse proximity further boosts it.
  let mouseDist = length(uv - mouse);
  let mouseBoost = 1.0 + (1.0 - smoothstep(0.0, 0.35, mouseDist)) * 0.4;
  let sortLength = sortLengthBase * 64.0 * (1.0 + bass * 0.3) * mouseBoost;

  // Early exit: zero effective radius means every sample is the centre pixel.
  if (sortLength < 0.5) {
    let alpha = clamp(centerLuma * 2.0, 0.2, 1.0);
    writeOutputs(pixel, vec4<f32>(centerColor.rgb, alpha), depth);
    return;
  }

  // Far pixels (low depth) and mouse proximity sort more aggressively.
  let sortFactor = clamp(DEPTH_BLEND * (1.0 - depth) + (1.0 - mouseDist) * 0.15, 0.0, 1.0);

  // Param-wired sort direction: 0–1 slider sweeps 0–180°. Angle 0 is the
  // identity rotation, so the default preset reproduces the classic look.
  let sortAngle = sortAngleParam * PI;
  let noiseScale = NOISE_MIX * sortLength * 0.5;

  // Gather Fibonacci-disk neighbours into register arrays.
  var colors: array<vec4<f32>, 9>;
  var lumas: array<f32, 9>;

  colors[0] = centerColor;
  lumas[0] = centerLuma;

  for (var i: u32 = 0u; i < SAMPLES; i = i + 1u) {
    let diskOffset = fibonacciDiskOffset(i, sortLength);
    let offset = rotateOffset(diskOffset, sortAngle);
    let n = (hash21(uv + f32(i) + time * 0.1) - 0.5) * noiseScale;
    let sampleUV = clamp(uv + (offset + n) * invRes, vec2<f32>(0.0), vec2<f32>(1.0));
    let c = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    colors[i + 1u] = c;
    lumas[i + 1u] = luma(c.rgb);
  }

  // Sort the disk by luma (25-comparator network, untouched).
  sortByLuma(&lumas, &colors);

  // Pick from sorted array: sortFactor=0 -> median, sortFactor=1 -> brightest.
  let sortedIdx = u32(mix(4.0, 8.0, sortFactor));
  let sortedColor = colors[clamp(sortedIdx, 0u, 8u)];

  // Branchless threshold selection and semantic alpha from sorted-luma intensity.
  let sortedRGB = mix(centerColor.rgb, sortedColor.rgb, sortFactor);
  let sortedAlpha = clamp(luma(sortedRGB) * 2.0, 0.2, 1.0);

  // Cosine-palette tint on sorted spans. Keyed by the sorted luma so the
  // grade follows the span's brightness, and gated by the span width so
  // flat regions stay clean. Palette Mix = 0 disables the tint entirely.
  let spanWidth = max(lumas[8] - lumas[0], 0.0);
  let spanMask = smoothstep(SPAN_TINT_LO, SPAN_TINT_HI, spanWidth);
  let paletteT = fract(luma(sortedRGB) + time * 0.05);
  let paletteRGB = cosinePalette(paletteT) * max(luma(sortedRGB), 0.05);
  let tintAmount = paletteMix * spanMask * sortFactor;
  let tintedRGB = mix(sortedRGB, paletteRGB, tintAmount);

  let finalColor = select(centerColor.rgb, tintedRGB, aboveThreshold);
  let outAlpha = select(centerColor.a * 0.3, sortedAlpha, aboveThreshold);

  writeOutputs(pixel, vec4<f32>(finalColor, outAlpha), depth);
}
