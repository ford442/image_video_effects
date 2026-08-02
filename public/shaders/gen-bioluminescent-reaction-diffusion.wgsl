// ═══════════════════════════════════════════════════════════════════
//  Bioluminescent Reaction-Diffusion
//  Category: generative
//  Features: mouse-driven, audio-reactive, simulation, upgraded-rgba,
//            chromatic-species, temporal-mutation, depth-scaled-glow
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-08-01 (Batch 23 — bounded stencil, honest controls/palette)
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadStateClamped(coord: vec2<i32>, maxCoord: vec2<i32>) -> vec2<f32> {
  return textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), maxCoord), 0).xy;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let maxCoord = vec2<i32>(resolution) - vec2<i32>(1);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // The four legacy controls now drive the named mechanisms directly.
  let intensity = mix(0.45, 1.80, clamp(u.zoom_params.x, 0.0, 1.0));
  let simulationSpeed = mix(0.35, 1.65, clamp(u.zoom_params.y, 0.0, 1.0));
  let spatialScale = mix(0.65, 1.35, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseInfluence = clamp(u.zoom_params.w, 0.0, 1.0);

  let center = loadStateClamped(coord, maxCoord);
  var a = center.x;
  var b = center.y;

  if (time < 0.1) {
    a = 1.0;
    b = 0.0;
  }

  var lapl = vec2<f32>(0.0);
  let weightAdj = 0.2;
  let weightDiag = 0.05;
  let weightCenter = -1.0;

  lapl += center * weightCenter;
  lapl += loadStateClamped(coord + vec2<i32>(1, 0), maxCoord) * weightAdj;
  lapl += loadStateClamped(coord + vec2<i32>(-1, 0), maxCoord) * weightAdj;
  lapl += loadStateClamped(coord + vec2<i32>(0, 1), maxCoord) * weightAdj;
  lapl += loadStateClamped(coord + vec2<i32>(0, -1), maxCoord) * weightAdj;
  lapl += loadStateClamped(coord + vec2<i32>(1, 1), maxCoord) * weightDiag;
  lapl += loadStateClamped(coord + vec2<i32>(-1, -1), maxCoord) * weightDiag;
  lapl += loadStateClamped(coord + vec2<i32>(1, -1), maxCoord) * weightDiag;
  lapl += loadStateClamped(coord + vec2<i32>(-1, 1), maxCoord) * weightDiag;

  let video_color = textureLoad(readTexture, coord, 0);
  let luma = dot(video_color.rgb, vec3<f32>(0.299, 0.587, 0.114));

  // Temporal mutation: feed/kill slowly drift with audio and time
  let feed = mix(0.01, 0.08, clamp(luma + mids * 0.1 * sin(time * 0.2), 0.0, 1.0));
  let kill = mix(0.045, 0.065, clamp(luma + bass * 0.05 * cos(time * 0.15), 0.0, 1.0));

  // Larger spatial scale diffuses more slowly and grows broader structures;
  // the bounded 1.55..0.65 multiplier avoids unstable extreme-step kernels.
  let spatialDiffusion = mix(1.55, 0.65, (spatialScale - 0.65) / 0.70);
  let diffA = mix(1.0, 0.5, bass) * spatialDiffusion;
  let diffB = mix(0.5, 0.2, bass) * 0.5 * spatialDiffusion;

  let reaction = a * b * b;
  let newA = a + simulationSpeed * (diffA * lapl.x - reaction + feed * (1.0 - a));
  let newB = b + simulationSpeed * (diffB * lapl.y + reaction - (kill + feed) * b);

  var finalA = clamp(newA, 0.0, 1.0);
  var finalB = clamp(newB, 0.0, 1.0);

  let mouse = u.zoom_config.yz;
  let dist_to_mouse = distance(vec2<f32>(coord), mouse * resolution);
  let mouseRadius = mix(8.0, 72.0, mouseInfluence);
  let mouseStrength = mouseInfluence * mix(0.25, 1.0, step(0.5, u.zoom_config.w));
  let mouseSeed = smoothstep(mouseRadius, 0.0, dist_to_mouse) * mouseStrength;
  finalB = mix(finalB, 1.0, mouseSeed);

  let state = vec4<f32>(finalA, finalB, 0.0, 1.0);
  textureStore(dataTextureA, coord, state);

  let concDiff = clamp(finalA - finalB, 0.0, 1.0);
  let fftBin = min(u32(concDiff * 8.0), 7u) + 1u;
  let spectralVoice = plasmaBuffer[fftBin].x;

  // State-derived bioluminescence: deep water, cyan A-species, violet B-
  // species, with bins 1-8 supplying bounded regional shimmer (not a palette).
  let deepWater = vec3<f32>(0.008, 0.025, 0.075);
  let speciesA = vec3<f32>(0.08, 0.95, 0.68) * finalA * (1.0 + treble * 0.25);
  let speciesB = vec3<f32>(0.82, 0.18, 1.0) * finalB * (1.0 + mids * 0.30);
  let spectralPhase = f32(fftBin - 1u) / 8.0 + time * 0.015;
  let spectralTint = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.1, 4.2) + spectralPhase * 6.2831853);
  let mixedSpecies = (deepWater + speciesA + speciesB) * (0.7 + spectralVoice * 0.65)
    + spectralTint * spectralVoice * concDiff * 0.18;

  let glow = clamp(finalB * 2.0, 0.0, 1.0);

  // Depth-scaled glow intensity
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthScale = 0.5 + depth * 0.5;
  let alpha = mix(video_color.a, 1.0, glow * 0.7 * depthScale);
  let finalRGB = mixedSpecies * glow * depthScale * intensity;

  textureStore(writeTexture, coord, vec4<f32>(acesToneMap(finalRGB * 1.1), alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
