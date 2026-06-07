// ═══════════════════════════════════════════════════════════════════
//  Static Reveal v2
//  Category: image
//  Features: mouse-driven, audio-reactive, multi-layer-static, temporal,
//            chromatic-displacement, upgraded-rgba, film-grain
//  Complexity: Very High
//  Chunks From: static-reveal, perlin, blue-noise, aces
//  Created: 2026-05-31
//  By: 4-Agent Shader Upgrade Swarm
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

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn perlinOctaves(p: vec2<f32>, t: f32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i = 0; i < 4; i = i + 1) {
    v += a * noise2(pp + t * 0.05 * f32(i + 1));
    pp = pp * 2.03;
    a *= 0.5;
  }
  return v;
}

fn blueNoise(p: vec2<f32>) -> f32 {
  let bayer = hash12(p * 73.0) * 0.25 + hash12(p * 137.0) * 0.25 +
              hash12(p * 251.0) * 0.25 + hash12(p * 379.0) * 0.25;
  return bayer;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let uv = vec2<f32>(global_id.xy) / u.config.zw;
  let aspect = u.config.z / u.config.w;
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let decaySpeed = u.zoom_params.x * 0.05;
  let brushRadius = u.zoom_params.y * 0.3 + 0.05;
  let noiseIntensity = u.zoom_params.z;
  let noiseScale = 30.0 + u.zoom_params.w * 250.0;

  let mouse = u.zoom_config.yz;
  let revealThreshold = u.zoom_config.y;
  let dist = distance((uv - mouse) * aspectVec, vec2<f32>(0.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthDecay = mix(0.7, 1.3, depth);
  let parallax = depth * 0.02;

  let reactiveRadius = brushRadius * (1.0 + bass * 0.3 + mids * 0.1);
  let prevMask = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

  let brush = smoothstep(reactiveRadius, reactiveRadius * 0.5, dist);
  let mask = clamp(max(prevMask - decaySpeed * depthDecay, brush), 0.0, 1.0);

  let staticTime = time * 2.0;
  let layer1 = perlinOctaves(uv * noiseScale + vec2<f32>(parallax, 0.0), staticTime);
  let layer2 = perlinOctaves(uv * (noiseScale * 0.3) + vec2<f32>(0.0, parallax * 2.0), staticTime * 0.7);
  let layer3 = perlinOctaves(uv * (noiseScale * 0.08) + vec2<f32>(parallax * 4.0, parallax * 4.0), staticTime * 0.4);

  let staticFlicker = 1.0 + bass * 0.6 + mids * 0.2;
  let combinedNoise = (layer1 * 0.5 + layer2 * 0.35 + layer3 * 0.15) * noiseIntensity * staticFlicker;

  let dither = blueNoise(vec2<f32>(f32(global_id.x), f32(global_id.y)) + floor(time * 30.0));
  let ditheredNoise = combinedNoise + (dither - 0.5) * 0.04;

  let chromaShift = treble * 0.025 + mids * 0.01;
  let rNoise = perlinOctaves((uv + vec2<f32>(chromaShift, 0.0)) * noiseScale, staticTime);
  let bNoise = perlinOctaves((uv - vec2<f32>(chromaShift, 0.0)) * noiseScale, staticTime);

  let grainR = ditheredNoise * (0.9 + rNoise * 0.2);
  let grainG = ditheredNoise;
  let grainB = ditheredNoise * (0.9 + bNoise * 0.2);
  let grainColor = vec3<f32>(grainR, grainG, grainB);

  let vig = smoothstep(1.0, 0.3, length(uv - 0.5) * 1.5);
  let unrevealedVig = (1.0 - mask) * vig * 0.4;
  let tintedGrain = mix(grainColor, grainColor * vec3<f32>(0.7, 0.75, 0.9), unrevealedVig);

  let videoColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let revealBias = smoothstep(revealThreshold, revealThreshold + 0.2, mask);
  var finalColor = mix(tintedGrain, videoColor, revealBias);

  finalColor = finalColor + vec3<f32>(unrevealedVig * 0.08, unrevealedVig * 0.05, 0.0);
  finalColor = acesToneMap(finalColor * 1.1);

  let staticStrength = 1.0 - revealBias;
  let alpha = clamp(mask * (1.0 - staticStrength * 0.7) + 0.15, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
