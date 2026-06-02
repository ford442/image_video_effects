// ═══════════════════════════════════════════════════════════════════
//  Volumetric God Rays v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-10
//  Upgraded: 2026-05-30
//  Chunks From: mie-scattering, ray-march-volume, chromatic-dispersion, aces-tonemap
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
  zoom_params: vec4<f32>,  // x=Density, y=Decay, z=Weight, w=Exposure
  ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Mie scattering phase function (Henyey-Greenstein approximation)
fn miePhase(g: f32, cosTheta: f32) -> f32 {
  let gg = g * g;
  let denom = 1.0 + gg - 2.0 * g * cosTheta;
  return (1.0 - gg) / (4.0 * 3.14159265 * pow(denom, 1.5));
}

fn hash12(p: vec2<f32>) -> f32 {
  var pp = fract(p * vec2<f32>(0.1031, 0.1030));
  pp = pp + dot(pp, pp.yx + 33.33);
  return fract((pp.x + pp.y) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coords = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let density = max(u.zoom_params.x, 0.001);
  let decay = clamp(u.zoom_params.y, 0.0, 1.0);
  let weight = u.zoom_params.z;
  let exposure = clamp(u.zoom_params.w, 0.0, 1.0);

  // Depth controls shaft occlusion and atmospheric extinction
  let srcDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthOcclusion = mix(0.3, 1.0, srcDepth);
  let extinction = mix(0.7, 1.0, srcDepth);

  // Bass drives dust density
  let dustDensity = density * (1.0 + bass * 0.8);
  let numSamples = 48;
  let deltaTextCoord = uv - mousePos;
  let stepSize = (deltaTextCoord * dustDensity) / f32(numSamples);

  var currentUV = uv;
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  var accumulatedR = 0.0;
  var accumulatedG = 0.0;
  var accumulatedB = 0.0;
  var illuminationDecay = depthOcclusion;

  // Ray direction for phase function
  let rayDir = normalize(deltaTextCoord + 0.0001);
  let lightDir = -rayDir;

  for (var i = 0; i < numSamples; i++) {
    currentUV = currentUV - stepSize;
    if (any(currentUV < vec2<f32>(0.0)) || any(currentUV > vec2<f32>(1.0))) { break; }
    if (illuminationDecay < 0.003) { break; }

    var sampleColor = textureSampleLevel(readTexture, u_sampler, currentUV, 0.0).rgb;

    // Dust particle scatter (procedural noise)
    let dustNoise = hash12(currentUV * 200.0 + f32(i) * 1.618);
    let dust = 0.85 + dustNoise * 0.3;

    // Mie scattering phase weighting
    let sampleRayDir = normalize(uv - currentUV + 0.0001);
    let cosTheta = dot(sampleRayDir, lightDir);
    let phase = miePhase(0.6, cosTheta);

    // Chromatic dispersion at shaft edges
    let edgeFade = length(currentUV - mousePos);
    let dispersion = 1.0 + edgeFade * 0.5;

    let contrib = illuminationDecay * weight * phase * dust * extinction;
    accumulatedR += sampleColor.r * contrib * dispersion;
    accumulatedG += sampleColor.g * contrib;
    accumulatedB += sampleColor.b * contrib / dispersion;

    illuminationDecay = illuminationDecay * decay;
  }

  let accumulatedColor = vec3<f32>(accumulatedR, accumulatedG, accumulatedB);

  // HDR bloom on light source (near mouse)
  let mouseDist = length(uv - mousePos);
  let bloom = exp(-mouseDist * 8.0) * (0.5 + treble * 0.5);
  var finalRGB = baseColor * ((1.0 - exposure) + 0.4) + accumulatedColor * exposure + vec3<f32>(bloom * 0.3, bloom * 0.25, bloom * 0.15);

  // Atmospheric haze (mids tint)
  let haze = mids * 0.15 * (1.0 - srcDepth);
  finalRGB += vec3<f32>(haze * 0.9, haze * 0.95, haze * 1.1);

  // ACES tone mapping
  finalRGB = acesToneMap(finalRGB);

  // Alpha: scattered_light × dust_density × depth_attenuation
  let scatteredLuma = dot(accumulatedColor, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(scatteredLuma * exposure * 2.0 * dustDensity * extinction, 0.0, 1.0);

  textureStore(writeTexture, coords, vec4<f32>(finalRGB, alpha));
  textureStore(writeDepthTexture, coords, vec4<f32>(srcDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coords, vec4<f32>(accumulatedColor, scatteredLuma));
}
