// ═══════════════════════════════════════════════════════════════════
//  data-stream-corruption-hdr
//  Category: advanced-hybrid
//  Features: mouse-driven, data-stream-corruption, hdr-bloom, temporal
//  Complexity: High
//  Chunks From: data-stream-corruption.wgsl, alpha-hdr-bloom-chain.wgsl
//  Created: 2026-04-18
//  By: Agent CB-18
// ═══════════════════════════════════════════════════════════════════
//  Matrix rain corruption enhanced with HDR bloom. Corrupted regions
//  emit luminous green bloom. Mouse brush adds corruption that builds
//  HDR exposure over time. Ripple flashes create HDR bursts. Alpha
//  stores exposure/overdrive value.
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  let streamSpeed = mix(2.0, 20.0, u.zoom_params.x);
  let brushRadius = mix(0.02, 0.4, u.zoom_params.y);
  let maxCorruption = mix(0.0, 1.0, u.zoom_params.z);
  let bloomIntensity = u.zoom_params.w * 2.0;

  // Persistence
  let oldState = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  var corruption = oldState.r;
  var alphaHistory = oldState.a;

  let mouse = u.zoom_config.yz;
  var dist = 10.0;
  if (mouse.x >= 0.0) {
    let p = (uv - mouse);
    dist = length(vec2<f32>(p.x * aspect, p.y));
  }

  let persistence = 0.92;
  if (dist < brushRadius) {
    let strength = smoothstep(brushRadius, brushRadius * 0.5, dist);
    corruption += strength * 0.5;
    alphaHistory = min(alphaHistory + strength * 0.3, 1.0);
  }
  corruption = clamp(corruption * persistence, 0.0, 1.0);
  alphaHistory = alphaHistory * persistence;

  textureStore(dataTextureA, global_id.xy, vec4<f32>(corruption, 0.0, 0.0, alphaHistory));

  let effectiveCorruption = corruption * maxCorruption;

  // Matrix rain
  let numColumns = 80.0;
  let colIndex = floor(uv.x * numColumns + 0.5);
  let colRandom = hash12(vec2<f32>(colIndex, 42.0));
  let rainSpeed = streamSpeed * (0.5 + 0.5 * colRandom);
  let rainY = uv.y + time * rainSpeed * 0.1;
  let numRows = 40.0 * (resolution.y / resolution.x);
  let rowIndex = floor(rainY * numRows + 0.5);
  let charRandom = hash12(vec2<f32>(colIndex, rowIndex));
  let isChar = step(0.4, charRandom);

  var sampleUV = uv;
  var finalColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

  if (effectiveCorruption > 0.01) {
    let blockSize = 0.05;
    let blockX = floor(uv.x / blockSize) * blockSize;
    let blockRandom = hash12(vec2<f32>(blockX, floor(time * 10.0)));
    let displaceY = (blockRandom - 0.5) * 0.1 * effectiveCorruption;
    sampleUV.y += displaceY;

    let displacedSample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let rgbSplit = 0.02 * effectiveCorruption;
    let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(rgbSplit, 0.0), 0.0).r;
    let g = displacedSample.g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(rgbSplit, 0.0), 0.0).b;
    let corruptedAlpha = mix(displacedSample.a, alphaHistory, effectiveCorruption * 0.5);
    finalColor = vec4<f32>(r, g, b, corruptedAlpha);

    let streamColor = vec3<f32>(0.2, 1.0, 0.4);
    let streamIntensity = isChar * effectiveCorruption * colRandom;
    let streamBlend = streamIntensity * 0.8;
    let newRGB = mix(finalColor.rgb, streamColor, streamBlend);
    let newA = mix(finalColor.a, 0.9 + streamIntensity * 0.1, streamBlend);
    finalColor = vec4<f32>(newRGB, newA);

    if (isChar < 0.5) {
      finalColor = mix(finalColor, vec4<f32>(0.0, 0.0, 0.0, finalColor.a * 0.5), effectiveCorruption * 0.5);
    }
  }

  finalColor = vec4<f32>(finalColor.rgb, clamp(finalColor.a, 0.0, 1.0));

  // HDR bloom on corrupted/green regions
  let sourceColor = finalColor.rgb;
  let maxChannel = max(sourceColor.r, max(sourceColor.g, sourceColor.b));
  let exposure = max(0.0, maxChannel - 1.0);

  var bloom = vec3<f32>(0.0);
  var totalWeight = 0.0;
  let bloomSamples = 12;
  let bloomRadius = 0.02 + effectiveCorruption * 0.04;

  for (var i = 0; i < bloomSamples; i = i + 1) {
    let angle = f32(i) * 6.283185307 / f32(bloomSamples);
    let radius = bloomRadius * (1.0 + f32(i % 4) * 0.5);
    let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
    let sampleUV2 = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let neighbor = textureSampleLevel(readTexture, u_sampler, sampleUV2, 0.0).rgb;
    let neighborMax = max(neighbor.r, max(neighbor.g, neighbor.b));
    let neighborExposure = max(0.0, neighborMax - 1.0);
    let weight = exp(-f32(i % 4) * 0.5);
    bloom += neighbor * neighborExposure * weight;
    totalWeight += neighborExposure * weight;
  }

  if (totalWeight > 0.001) {
    bloom /= totalWeight;
  }
  bloom *= bloomIntensity;

  var hdrColor = sourceColor + bloom;

  // Ripple HDR flash
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rDist = length(uv - ripple.xy);
    let age = time - ripple.z;
    if (age < 0.5 && rDist < 0.1) {
      let flash = smoothstep(0.1, 0.0, rDist) * max(0.0, 1.0 - age * 2.0);
      hdrColor += vec3<f32>(flash * 2.0, flash * 1.5, flash);
    }
  }

  let toneMapExp = 0.8 + effectiveCorruption;
  let ldrColor = toneMapACES(hdrColor * toneMapExp);

  textureStore(writeTexture, global_id.xy, vec4<f32>(ldrColor, exposure + 0.1));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
