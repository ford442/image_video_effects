// ═══════════════════════════════════════════════════════════════════
//  Rain v2
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, atmospheric
//  Complexity: High
//  Chunks From: rain
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
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash13(p: vec3<f32>) -> f32 {
  return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
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
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let aspect = dims.x / dims.y;
  let time = u.config.x;
  let audio = plasmaBuffer[0].xyz;

  let rainDensity = mix(6.0, 72.0, u.zoom_params.x);
  let fallSpeed = mix(0.3, 4.2, u.zoom_params.y);
  let windBase = mix(-0.12, 0.12, u.zoom_params.z);
  let wetness = mix(0.06, 0.55, u.zoom_params.w);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthScale = mix(0.6, 1.4, depth);

  let mouseWind = (mouse.x - 0.5) * 0.08;
  let wind = windBase + mouseWind;
  let gust = audio.x * 0.04;

  let rainUV = vec2<f32>(uv.x * rainDensity * aspect + wind * time * 3.0, uv.y * rainDensity + time * fallSpeed);
  let cell = floor(rainUV);
  let local = fract(rainUV);

  let dropSeed = hash12(cell);
  let dropSeed2 = hash13(vec3<f32>(cell, time * 0.1));

  let gravity = 1.0 + dropSeed * 2.5;
  let streakY = local.y - (1.0 - exp(-local.y * gravity));
  let streakWidth = 0.005 + dropSeed * 0.012;
  let streakX = abs(local.x - 0.5 + wind * local.y * 0.3);
  let motionBlur = smoothstep(streakWidth * 2.0, 0.0, streakX) * smoothstep(1.0, 0.15, local.y) * (0.4 + 0.6 * gravity / 3.5);

  let dropletAlpha = motionBlur * step(0.65, dropSeed);
  let splash = step(0.92, local.y) * step(0.75, dropSeed) * smoothstep(0.0, 0.06, streakX) * smoothstep(0.12, 0.0, streakX);

  var dropCenter = cell / vec2<f32>(rainDensity * aspect, rainDensity);
  dropCenter.x -= wind * time * 3.0 / (rainDensity * aspect);
  let dropWorld = (uv - dropCenter) * vec2<f32>(aspect, 1.0);
  let dropDist = length(dropWorld);

  let lensStrength = dropletAlpha * 0.018 * depthScale;
  let lensR = lensStrength * (1.0 + dropSeed * 0.15);
  let lensG = lensStrength * (1.0 + dropSeed2 * 0.08);
  let lensB = lensStrength * (1.0 - dropSeed * 0.12);
  let displacedUV = clamp(uv + vec2<f32>(wind * 0.015, 0.008) * dropletAlpha + dropWorld * vec2<f32>(lensR - lensG, lensB - lensR) * 40.0, vec2<f32>(0.0), vec2<f32>(1.0));

  let src = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

  let lightSrc = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.002, 0.0), 0.0).rgb;
  let lightEnergy = dot(lightSrc, vec3<f32>(0.299, 0.587, 0.114));
  let bloom = pow(lightEnergy, 3.0) * 2.5 * dropletAlpha * (1.0 + audio.z * 0.5);

  let mistCell = floor(vec2<f32>(uv.x * rainDensity * 0.4 * aspect, uv.y * rainDensity * 0.4 + time * 0.3));
  let mistNoise = hash12(mistCell + vec2<f32>(floor(time * 2.0), 0.0));
  let mistLayer = smoothstep(0.45, 0.85, mistNoise) * wetness * 0.18 * depthScale;

  let rainTint = mix(vec3<f32>(0.62, 0.76, 0.94), vec3<f32>(0.52, 0.92, 1.0), audio.y * 0.4);
  let chromaR = src.rgb + rainTint * dropletAlpha * (0.22 + audio.z * 0.18) + vec3<f32>(bloom * 0.9, bloom * 0.4, bloom * 0.15);
  let chromaG = src.rgb + rainTint * dropletAlpha * (0.20 + audio.z * 0.16) + vec3<f32>(bloom * 0.3, bloom * 0.85, bloom * 0.25);
  let chromaB = src.rgb + rainTint * dropletAlpha * (0.18 + audio.z * 0.14) + vec3<f32>(bloom * 0.1, bloom * 0.35, bloom * 0.8);
  var hdrColor = vec3<f32>(chromaR.r, chromaG.g, chromaB.b);

  hdrColor = mix(hdrColor, hdrColor * 0.72 + rainTint * 0.28, mistLayer);
  hdrColor = mix(hdrColor, hdrColor + vec3<f32>(splash * 0.35), splash);
  let finalColor = acesToneMap(hdrColor * (0.9 + audio.x * 0.15));

  let motionBlurStrength = clamp(motionBlur + splash * 0.5, 0.0, 1.0);
  let finalAlpha = clamp(dropletAlpha * motionBlurStrength * depth + mistLayer * 0.6 + splash * 0.4, 0.04, 0.96);

  let outDepth = clamp(mix(depth, 0.18 + dropletAlpha * 0.68 + splash * 0.22, 0.22), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(dropletAlpha, motionBlurStrength, mistLayer, finalAlpha));
}
