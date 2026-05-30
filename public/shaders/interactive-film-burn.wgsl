// ================================================================
//  Interactive Film Burn
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Chunks From: interactive-film-burn
//  Created: 2026-05-30
//  By: Copilot
// ================================================================

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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=BurnRadius, y=BurnSpeed, z=GrainStrength, w=EdgeGlow
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var pos = p;
  let rot = mat2x2<f32>(0.8, 0.6, -0.6, 0.8);
  for (var i: i32 = 0; i < 5; i = i + 1) {
    value = value + amplitude * noise(pos);
    pos = rot * pos * 2.0;
    amplitude = amplitude * 0.5;
  }
  return value;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let audio = plasmaBuffer[0].xyz;

  let burnRadius = u.zoom_params.x * 0.80;
  let burnSpeed = u.zoom_params.y * 2.0;
  let grainStrength = u.zoom_params.z;
  let glowWidth = u.zoom_params.w * 0.20 + 0.01;

  let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let noiseScale = 10.0 + audio.z * 6.0;
  let noiseVal = fbm(uv * noiseScale + vec2<f32>(time * burnSpeed * 0.15, -time * burnSpeed * 0.11));
  let distortedDist = dist - noiseVal * (0.10 + audio.x * 0.30);

  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let filmGrain = (hash12(uv * 120.0 + vec2<f32>(time * 7.3, time * 13.1)) - 0.5) * grainStrength * 0.35;
  let gray = dot(sourceColor, vec3<f32>(0.299, 0.587, 0.114));
  let sepia = vec3<f32>(gray * 1.18, gray * 1.0, gray * 0.78);
  let intactColor = mix(sourceColor, sepia, 0.55) + vec3<f32>(filmGrain);

  let d = distortedDist - burnRadius;
  let holeMask = 1.0 - smoothstep(-0.015, 0.015, d);
  let fireMask = smoothstep(-glowWidth, 0.0, d) * (1.0 - smoothstep(0.0, glowWidth, d));
  let smokeMask = 1.0 - smoothstep(glowWidth * 0.5, glowWidth * 3.0, d);

  let emberNoise = noise(uv * 50.0 + vec2<f32>(time * 10.0, -time * 7.0));
  let emberGlow = smoothstep(-0.08, 0.0, d) * (0.4 + 0.6 * emberNoise);
  let fireT = clamp(d / glowWidth, 0.0, 1.0);
  var fireColor = mix(vec3<f32>(1.0, 0.98, 0.80), vec3<f32>(1.0, 0.30, 0.0), fireT);
  fireColor = mix(fireColor, vec3<f32>(0.08, 0.0, 0.0), fireT * fireT);
  fireColor = fireColor + vec3<f32>(1.0, 0.45, 0.10) * emberGlow * (0.4 + 0.6 * audio.x);
  let charColor = vec3<f32>(0.0) + vec3<f32>(1.0, 0.18, 0.02) * emberGlow * 0.45;

  var finalColor = intactColor * mix(0.55, 1.0, smokeMask);
  finalColor = mix(finalColor, fireColor, fireMask);
  finalColor = mix(finalColor, charColor, holeMask);

  var finalAlpha = (1.0 - holeMask) * (0.82 + 0.12 * smokeMask);
  finalAlpha = max(finalAlpha, fireMask * (0.35 + 0.45 * u.zoom_params.w));
  finalAlpha = clamp(finalAlpha, 0.0, 0.98);

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthOut = clamp(mix(baseDepth, baseDepth * 0.25, holeMask) + fireMask * 0.08, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(holeMask, fireMask, smokeMask, finalAlpha));
}
