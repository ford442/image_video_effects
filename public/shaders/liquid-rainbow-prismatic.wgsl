// ═══════════════════════════════════════════════════════════════════
//  liquid-rainbow-prismatic
//  Category: advanced-hybrid
//  Features: liquid-rainbow, prismatic-dispersion, spectral-rendering, mouse-driven
//  Complexity: High
//  Chunks From: liquid-rainbow.wgsl, spec-prismatic-dispersion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-14 — Liquid Effects Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Combines liquid rainbow chromatic aberration with physical prismatic
//  dispersion via Cauchy's equation. Mouse ripples create rainbow waves
//  while a dynamic lens refracts 4 wavelength bands independently.
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

// ═══ CHUNK: schlickFresnel (from liquid-rainbow.wgsl) ═══
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// ═══ CHUNK: cauchyIOR (from spec-prismatic-dispersion.wgsl) ═══
fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
  let lambdaUm = wavelengthNm * 0.001;
  return A + B / (lambdaUm * lambdaUm);
}

// ═══ CHUNK: wavelengthToRGB (from spec-prismatic-dispersion.wgsl) ═══
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
  let g = 1.0 - abs(t - 0.4) * 3.0;
  let b = 1.0 - smoothstep(0.0, 0.4, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn refractThroughSurface(uv: vec2<f32>, center: vec2<f32>, ior: f32, curvature: f32) -> vec2<f32> {
  let toCenter = uv - center;
  let dist = length(toCenter);
  let lensStrength = curvature * 0.4;
  let offset = toCenter * (1.0 - 1.0 / ior) * lensStrength * (1.0 + dist * 2.0);
  return uv + offset;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;

  let viscosity = mix(0.1, 0.9, u.zoom_params.x);
  let turbulence = u.zoom_params.y;
  let ripple_strength = u.zoom_params.z;
  let spectral_sat = mix(0.3, 1.5, u.zoom_params.w);

  // --- Liquid Rainbow: Mouse-driven Ripples ---
  var mouseDisplacement = vec2<f32>(0.0, 0.0);
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = currentTime - rippleData.z;
    if (timeSinceClick > 0.0 && timeSinceClick < 3.0) {
      let direction_vec = uv - rippleData.xy;
      let dist = length(direction_vec);
      if (dist > 0.0001) {
        let ripple_speed = 2.0;
        let ripple_amplitude = 0.01 * ripple_strength;
        let wave = sin(dist * 25.0 - timeSinceClick * ripple_speed);
        let attenuation = 1.0 - smoothstep(0.0, 1.0, timeSinceClick / 3.0);
        let falloff = 1.0 / (dist * 20.0 + 1.0);
        mouseDisplacement += (direction_vec / dist) * wave * ripple_amplitude * falloff * attenuation;
      }
    }
  }

  // Add turbulent noise displacement
  let noiseDisp = vec2<f32>(
    hash12(uv * 30.0 + currentTime * 0.1) - 0.5,
    hash12(uv * 30.0 + currentTime * 0.15 + 100.0) - 0.5
  ) * turbulence * 0.02;

  let totalDisplacement = mouseDisplacement + noiseDisp;
  let magnitude = length(totalDisplacement);

  // --- Prismatic Dispersion: 4-Band Spectral Refraction ---
  let glassCurvature = mix(0.1, 1.0, viscosity);
  let cauchyB = mix(0.01, 0.08, turbulence);
  let glassThickness = mix(0.3, 1.2, ripple_strength);

  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;

  var lensCenter = vec2<f32>(0.5, 0.5);
  if (isMouseDown) {
    lensCenter = mousePos;
  } else {
    lensCenter = vec2<f32>(
      0.5 + sin(currentTime * 0.2) * 0.25,
      0.5 + cos(currentTime * 0.15) * 0.2
    );
  }

  // Apply liquid displacement to UV before prismatic sampling
  let displacedUV = uv + totalDisplacement;

  let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
  var finalColor = vec3<f32>(0.0);
  var spectralResponse = vec4<f32>(0.0);

  for (var i: i32 = 0; i < 4; i = i + 1) {
    let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyB);
    let refractedUV = refractThroughSurface(displacedUV, lensCenter, ior, glassCurvature);
    let wrappedUV = fract(refractedUV);
    let sample = textureSampleLevel(readTexture, u_sampler, wrappedUV, 0.0);

    let absorption = exp(-glassThickness * (4.0 - f32(i)) * 0.15);
    let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[i])) * absorption;

    spectralResponse[i] = bandIntensity;
    finalColor += wavelengthToRGB(WAVELENGTHS[i]) * bandIntensity * spectral_sat;
  }

  // Chromatic aberration glow from liquid displacement
  let glowRadius = magnitude * 0.05 + glassCurvature * 0.01;
  var glowColor = vec3<f32>(0.0);
  let glowSamples = 8;
  for (var j: i32 = 0; j < glowSamples; j = j + 1) {
    let angle = f32(j) * 0.785398 + currentTime * 0.5;
    let offset = vec2<f32>(cos(angle), sin(angle)) * glowRadius;
    let gSample = textureSampleLevel(readTexture, u_sampler, fract(displacedUV + offset), 0.0);
    glowColor += gSample.rgb;
  }
  glowColor /= f32(glowSamples);
  finalColor += glowColor * 0.08 * glassCurvature;

  // Tone map
  finalColor = finalColor / (1.0 + finalColor * 0.3);

  // --- Alpha: Liquid Rainbow Fresnel ---
  let dispersionMag = magnitude + glassCurvature * 0.5;
  let normal = normalize(vec3<f32>(
    -totalDisplacement.x * 30.0,
    -totalDisplacement.y * 30.0,
    1.0
  ));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let viewDotNormal = dot(viewDir, normal);
  let F0 = 0.03;
  let fresnel = schlickFresnel(max(0.0, viewDotNormal), F0);
  let thickness = dispersionMag * 3.0 + 0.15;
  let absorptionAlpha = exp(-thickness * 1.2);
  let baseAlpha = mix(0.4, 0.85, absorptionAlpha);
  let avgColor = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
  let brightnessFactor = mix(0.9, 1.0, avgColor);
  let alpha = baseAlpha * brightnessFactor * (1.0 - fresnel * 0.25);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, clamp(alpha, 0.0, 1.0)));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), spectralResponse);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
