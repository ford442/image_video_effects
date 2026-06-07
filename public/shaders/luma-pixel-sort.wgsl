// ═══════════════════════════════════════════════════════════════════
//  Luma Pixel Sort — Batch D Upgraded
//  Category: post-processing
//  Features: upgraded-rgba, mouse-driven, audio-reactive, depth-aware
//  Complexity: Medium
//  Chunks From: luma-pixel-sort
//  Created: 2026-05-02
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const LUMA_WEIGHTS: vec3<f32> = vec3<f32>(0.299, 0.587, 0.114);
const HASH_A: vec2<f32> = vec2<f32>(12.9898, 78.233);
const HASH_B: f32 = 43758.5453;
const SAMPLES: u32 = 8u;

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, HASH_A)) * HASH_B);
}

fn fibonacciDiskOffset(i: u32, n: u32, radius: f32) -> vec2<f32> {
  let angle = f32(i) * 2.3999632297;
  let r = radius * sqrt(f32(i + 1u) / f32(n + 1u));
  return vec2<f32>(cos(angle), sin(angle)) * r;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  let threshold = u.zoom_params.x;
  let depthBlend = u.zoom_params.z;
  let noiseMix = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let localThreshold = threshold - treble * 0.25 - mids * 0.1;

  // Bass expands sort radius for beat-locked scatter
  let sortLength = u.zoom_params.y * 64.0 * (1.0 + bass * 0.3);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let centerColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let centerLuma = dot(centerColor.rgb, LUMA_WEIGHTS);

  var colors: array<vec4<f32>, 9>;
  var lumas: array<f32, 9>;

  colors[0] = centerColor;
  lumas[0] = centerLuma;

  for (var i: u32 = 0u; i < SAMPLES; i = i + 1u) {
    let offset = fibonacciDiskOffset(i, SAMPLES, sortLength);
    let n = (hash12(uv + f32(i) + time * 0.1) - 0.5) * noiseMix * sortLength * 0.5;
    let sampleUV = clamp(uv + (offset + n) / resolution, vec2<f32>(0.0), vec2<f32>(1.0));
    let c = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    colors[i + 1u] = c;
    lumas[i + 1u] = dot(c.rgb, LUMA_WEIGHTS);
  }

  // Bubble sort by luma (ascending)
  for (var i: u32 = 0u; i < 9u; i = i + 1u) {
    for (var j: u32 = 0u; j < 8u - i; j = j + 1u) {
      if (lumas[j] > lumas[j + 1u]) {
        let tl = lumas[j];
        lumas[j] = lumas[j + 1u];
        lumas[j + 1u] = tl;
        let tc = colors[j];
        colors[j] = colors[j + 1u];
        colors[j + 1u] = tc;
      }
    }
  }

  // Far pixels (low depth) = more sorted
  let sortFactor = depthBlend * (1.0 - depth);

  // Pick from sorted array: sortFactor=0 -> median, sortFactor=1 -> brightest
  let sortedIdx = u32(mix(4.0, 8.0, sortFactor));
  let sortedColor = colors[clamp(sortedIdx, 0u, 8u)];

  // Branchless threshold selection
  let aboveThreshold = centerLuma >= localThreshold;
  let sortedRGB = mix(centerColor.rgb, sortedColor.rgb, sortFactor);
  let sortedAlpha = clamp(dot(sortedRGB, LUMA_WEIGHTS) * 2.0, 0.2, 1.0);
  let finalColor = select(centerColor.rgb, sortedRGB, aboveThreshold);
  let outAlpha = select(centerColor.a * 0.3, sortedAlpha, aboveThreshold);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, outAlpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, outAlpha));
}
