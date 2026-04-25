// ═══════════════════════════════════════════════════════════════════
//  steamy-glass-volumetric
//  Category: advanced-hybrid
//  Features: steamy-glass, depth-fog, volumetric, mouse-driven
//  Complexity: High
//  Chunks From: steamy-glass.wgsl, alpha-depth-fog-volumetric.wgsl
//  Created: 2026-04-18
//  By: Agent CB-14 — Liquid Effects Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Steam condensation on glass merges with depth-aware volumetric
//  fog. Mouse wipes clear both steam and fog while depth drives
//  fog density and Beer-Lambert extinction unifies both media.
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

// ═══ CHUNK: valueNoise + fbm2 (from alpha-depth-fog-volumetric.wgsl) ═══
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  let a = hash12(i + vec2<f32>(0.0, 0.0));
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value = value + amplitude * valueNoise(p * frequency);
    amplitude = amplitude * 0.5;
    frequency = frequency * 2.0;
  }
  return value;
}

const SIGMA_T_STEAM: f32 = 1.5;
const SIGMA_S_STEAM: f32 = 1.3;
const STEP_SIZE: f32 = 0.025;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  var mouse = u.zoom_config.yz;
  let time = u.config.x;

  let steamDensityParam = u.zoom_params.x;
  let fogHeight = u.zoom_params.y;
  let turbulence = u.zoom_params.z;
  let wipeRadius = u.zoom_params.w * 0.3 + 0.05;

  // === STEAM SIMULATION (from steamy-glass) ===
  let prevSteam = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
  let steamNoise = hash12(uv * 50.0 + time * 0.01);
  let steamTurb = hash12(uv * 100.0 - time * 0.02) * 0.5 + 0.5;
  let accumulation = steamNoise * steamDensityParam * 0.02;
  var newSteam = min(prevSteam + accumulation, 1.0);
  newSteam = max(0.0, newSteam - 0.005 * (1.0 - steamDensityParam));

  // === DEPTH FOG (from alpha-depth-fog-volumetric) ===
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let noiseUV = uv * 3.0 + vec2<f32>(time * 0.02, time * 0.015);
  let fogNoise = fbm2(noiseUV, 4) * turbulence + (1.0 - turbulence);
  let distFactor = (1.0 - depth);
  let heightFactor = 1.0 - uv.y * fogHeight;
  let fogOpticalDepth = steamDensityParam * 2.0 * distFactor * heightFactor * fogNoise * 3.0;

  // === MOUSE WIPE (unified for steam + fog) ===
  let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let wipe = smoothstep(wipeRadius, wipeRadius - 0.1, dist);
  newSteam = max(0.0, newSteam - wipe);

  // === RIPPLE FOG SWIRL ===
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleDisturbance = 0.0;
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rDist = length(uv - ripple.xy);
    let age = time - ripple.z;
    if (age < 2.0 && rDist < 0.2) {
      rippleDisturbance += smoothstep(0.2, 0.0, rDist) * max(0.0, 1.0 - age * 0.5) * 0.3;
    }
  }

  // === UNIFIED VOLUMETRIC COMPOSITION ===
  // Combined optical depth: steam + depth fog
  let combinedOpticalDepth = newSteam * STEP_SIZE * SIGMA_T_STEAM + fogOpticalDepth * (1.0 - wipe);
  let modifiedOpticalDepth = mix(combinedOpticalDepth, combinedOpticalDepth * 0.5, rippleDisturbance);

  let transmittance = exp(-modifiedOpticalDepth);
  let alpha = 1.0 - transmittance;

  // Fog colors
  let nearFog = vec3<f32>(0.95, 0.97, 1.0);  // Steam white/blue
  let farFog = vec3<f32>(0.25, 0.35, 0.6);   // Cool blue fog
  let fogColor = mix(nearFog, farFog, distFactor);

  // Scene composite
  let sceneColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Blur from steam scattering
  let blurAmount = newSteam * 0.02;
  var blurColor = vec3<f32>(0.0);
  blurColor += textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(blurAmount, 0.0), 0.0).rgb;
  blurColor += textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(blurAmount, 0.0), 0.0).rgb;
  blurColor += textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, blurAmount), 0.0).rgb;
  blurColor += textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, blurAmount), 0.0).rgb;
  blurColor *= 0.25;

  let scatteredImage = mix(sceneColor, blurColor, newSteam);
  let inScattered = fogColor * newSteam * SIGMA_S_STEAM * (1.0 - transmittance);
  let finalColor = scatteredImage * transmittance + inScattered;

  // Condensation droplet highlights
  let dropletNoise = hash12(uv * 200.0 + time * 0.5);
  let droplets = smoothstep(0.98, 1.0, dropletNoise) * newSteam * 0.3;
  let finalWithDroplets = finalColor + vec3<f32>(droplets);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalWithDroplets, alpha));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(newSteam, fogOpticalDepth, 0.0, alpha));

  let steamDepth = mix(depth, 0.9, alpha * 0.3);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(steamDepth, modifiedOpticalDepth, 0.0, alpha));
}
