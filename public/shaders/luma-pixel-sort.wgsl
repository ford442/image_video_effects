// ═══════════════════════════════════════════════════════════════════
//  Luma Pixel Sort — Optimized Upgrade
//  Category: post-processing
//  Features: upgraded-rgba, mouse-driven, audio-reactive, depth-aware
//  Complexity: Medium
//  Upgraded: 2026-06-14
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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, LUMA_WEIGHTS);
}

fn fibonacciDiskOffset(i: u32, n: u32, radius: f32) -> vec2<f32> {
  let angle = f32(i) * 2.3999632297;
  let r = radius * sqrt(f32(i + 1u) / f32(n + 1u));
  return vec2<f32>(cos(angle), sin(angle)) * r;
}

// Branchless swap of a color+luma pair into ascending luma order.
fn sortPair(lumas: ptr<function, array<f32, 9>>, colors: ptr<function, array<vec4<f32>, 9>>, a: u32, b: u32) {
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

// Explicit 9-element insertion-sort network: fixed comparison pattern,
// no divergent loops, and SIMD-friendly branchless swaps.
fn sortByLuma(lumas: ptr<function, array<f32, 9>>, colors: ptr<function, array<vec4<f32>, 9>>) {
  sortPair(lumas, colors, 1u, 0u);
  sortPair(lumas, colors, 2u, 1u); sortPair(lumas, colors, 1u, 0u);
  sortPair(lumas, colors, 3u, 2u); sortPair(lumas, colors, 2u, 1u); sortPair(lumas, colors, 1u, 0u);
  sortPair(lumas, colors, 4u, 3u); sortPair(lumas, colors, 3u, 2u); sortPair(lumas, colors, 2u, 1u); sortPair(lumas, colors, 1u, 0u);
  sortPair(lumas, colors, 5u, 4u); sortPair(lumas, colors, 4u, 3u); sortPair(lumas, colors, 3u, 2u); sortPair(lumas, colors, 2u, 1u); sortPair(lumas, colors, 1u, 0u);
  sortPair(lumas, colors, 6u, 5u); sortPair(lumas, colors, 5u, 4u); sortPair(lumas, colors, 4u, 3u); sortPair(lumas, colors, 3u, 2u); sortPair(lumas, colors, 2u, 1u); sortPair(lumas, colors, 1u, 0u);
  sortPair(lumas, colors, 7u, 6u); sortPair(lumas, colors, 6u, 5u); sortPair(lumas, colors, 5u, 4u); sortPair(lumas, colors, 4u, 3u); sortPair(lumas, colors, 3u, 2u); sortPair(lumas, colors, 2u, 1u); sortPair(lumas, colors, 1u, 0u);
  sortPair(lumas, colors, 8u, 7u); sortPair(lumas, colors, 7u, 6u); sortPair(lumas, colors, 6u, 5u); sortPair(lumas, colors, 5u, 4u); sortPair(lumas, colors, 4u, 3u); sortPair(lumas, colors, 3u, 2u); sortPair(lumas, colors, 2u, 1u); sortPair(lumas, colors, 1u, 0u);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  let threshold = u.zoom_params.x;
  let sortLengthBase = u.zoom_params.y;
  let depthBlend = u.zoom_params.z;
  let noiseMix = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Depth-aware early exit for sky / background pixels.
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let bgMask = step(0.99, depth) * step(0.01, depthBlend);
  if (bgMask > 0.5) {
    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    textureStore(writeTexture, pixel, c);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, c);
    return;
  }

  // Audio-reactive threshold modulation.
  let localThreshold = clamp(threshold - treble * 0.25 - mids * 0.1, 0.0, 1.0);

  // Bass expands sort radius; mouse proximity further boosts it.
  let mouseDist = length(uv - mouse);
  let mouseBoost = 1.0 + (1.0 - smoothstep(0.0, 0.35, mouseDist)) * 0.4;
  let sortLength = sortLengthBase * 64.0 * (1.0 + bass * 0.3) * mouseBoost;

  // Sample center pixel and gather Fibonacci-disk neighbors.
  let centerColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let centerLuma = luma(centerColor.rgb);

  var colors: array<vec4<f32>, 9>;
  var lumas: array<f32, 9>;

  colors[0] = centerColor;
  lumas[0] = centerLuma;

  for (var i: u32 = 0u; i < SAMPLES; i = i + 1u) {
    let offset = fibonacciDiskOffset(i, SAMPLES, sortLength);
    let n = (hash21(uv + f32(i) + time * 0.1) - 0.5) * noiseMix * sortLength * 0.5;
    let sampleUV = clamp(uv + (offset + n) / res, vec2<f32>(0.0), vec2<f32>(1.0));
    let c = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    colors[i + 1u] = c;
    lumas[i + 1u] = luma(c.rgb);
  }

  // Sort the disk by luma.
  sortByLuma(&lumas, &colors);

  // Far pixels (low depth) and mouse proximity sort more aggressively.
  let sortFactor = saturate(depthBlend * (1.0 - depth) + (1.0 - mouseDist) * 0.15);

  // Pick from sorted array: sortFactor=0 -> median, sortFactor=1 -> brightest.
  let sortedIdx = u32(mix(4.0, 8.0, sortFactor));
  let sortedColor = colors[clamp(sortedIdx, 0u, 8u)];

  // Branchless threshold selection and semantic alpha from sorted-luma intensity.
  let aboveThreshold = centerLuma >= localThreshold;
  let sortedRGB = mix(centerColor.rgb, sortedColor.rgb, sortFactor);
  let sortedAlpha = clamp(luma(sortedRGB) * 2.0, 0.2, 1.0);
  let finalColor = select(centerColor.rgb, sortedRGB, aboveThreshold);
  let outAlpha = select(centerColor.a * 0.3, sortedAlpha, aboveThreshold);

  textureStore(writeTexture, pixel, vec4<f32>(finalColor, outAlpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(finalColor, outAlpha));
}
