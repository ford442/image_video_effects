// ═══════════════════════════════════════════════════════════════════
//  liquid-rainbow-prismatic — Upgraded with Alpha Translucency
//  Category: liquid-effects
//  Features: liquid-rainbow, prismatic-dispersion, upgraded-rgba
//  Complexity: High
//  Chunks From: liquid-rainbow.wgsl, spec-prismatic-dispersion.wgsl
//  Created: 2026-04-18
//  Upgraded: 2026-05-17
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

// ═══ Math Snippets ═══
fn tentAlpha(x: f32) -> f32 {
  return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
}

fn gaussianMask(dist: f32, sigma: f32) -> f32 {
  return exp(-dist * dist / (2.0 * sigma * sigma));
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  var r = 0.0; var g = 0.0; var b = 0.0;
  if (lambda < 440.0) { r = (440.0 - lambda) / 60.0; b = 1.0; }
  else if (lambda < 490.0) { g = (lambda - 440.0) / 50.0; b = 1.0; }
  else if (lambda < 510.0) { g = 1.0; b = (510.0 - lambda) / 20.0; }
  else if (lambda < 580.0) { r = (lambda - 510.0) / 70.0; g = 1.0; }
  else if (lambda < 645.0) { r = 1.0; g = (645.0 - lambda) / 65.0; }
  else { r = 1.0; }
  var intensity = 1.0;
  if (lambda < 420.0) { intensity = 0.3 + 0.7 * (lambda - 380.0) / 40.0; }
  else if (lambda > 700.0) { intensity = 0.3 + 0.7 * (780.0 - lambda) / 80.0; }
  return clamp(vec3(r, g, b) * intensity, vec3(0.0), vec3(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn smoothDepthBlend(depth: f32, baseColor: vec3<f32>, refColor: vec3<f32>, strength: f32) -> vec3<f32> {
  let nearFade = smoothstep(0.0, 0.3, depth);
  let farFade = 1.0 - smoothstep(0.5, 0.9, depth);
  return mix(baseColor, refColor, nearFade * farFade * strength);
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

  // ── Liquid displacement field ──
  var mouseDisplacement = vec2<f32>(0.0, 0.0);
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = currentTime - rippleData.z;
    if (timeSinceClick > 0.0 && timeSinceClick < 3.0) {
      let direction_vec = uv - rippleData.xy;
      let dist = length(direction_vec);
      if (dist > 0.0001) {
        let wave = sin(dist * 25.0 - timeSinceClick * 2.0);
        let attenuation = 1.0 - smoothstep(0.0, 1.0, timeSinceClick / 3.0);
        let falloff = 1.0 / (dist * 20.0 + 1.0);
        mouseDisplacement += (direction_vec / dist) * wave * 0.01 * ripple_strength * falloff * attenuation;
      }
    }
  }

  let noiseDisp = vec2<f32>(
    hash12(uv * 30.0 + currentTime * 0.1) - 0.5,
    hash12(uv * 30.0 + currentTime * 0.15 + 100.0) - 0.5
  ) * turbulence * 0.02;

  let totalDisplacement = mouseDisplacement + noiseDisp;
  let magnitude = length(totalDisplacement);

  // ── Single refraction with spectral tint ──
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

  let displacedUV = uv + totalDisplacement;
  let centerIOR = 1.5 + cauchyB;
  let refractedUV = refractThroughSurface(displacedUV, lensCenter, centerIOR, glassCurvature);
  let wrappedUV = fract(refractedUV);

  // Single unified RGB sample — no per-wavelength band splitting
  let baseColor = textureSampleLevel(readTexture, u_sampler, wrappedUV, 0.0).rgb;

  // Spectral tint from displacement magnitude mapped to wavelength
  let wavelength = mix(450.0, 680.0, clamp(magnitude * 10.0 + glassCurvature * 0.2, 0.0, 1.0));
  let spectralTint = wavelengthToRGB(wavelength);
  let tintStrength = tentAlpha(magnitude * 6.0) * spectral_sat * 0.5;
  var color = mix(baseColor, baseColor * spectralTint, tintStrength);

  // Chromatic glow from displacement using radial sample kernel
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
  color += glowColor * 0.08 * glassCurvature;

  // Tone map for HDR containment
  color = color / (1.0 + color * 0.3);

  // Audio-reactive sparkle from treble hitting displacement peaks
  let treble = plasmaBuffer[0].z;
  let bass = plasmaBuffer[0].x;
  color = color * (1.0 + treble * 0.25 * gaussianMask(magnitude, 0.1));
  color = color + vec3<f32>(0.1, 0.05, 0.2) * bass * gaussianMask(magnitude, 0.2);

  // Depth-aware compositing: background seeps through in deep regions
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFade = smoothstep(0.0, 0.6, depth);
  let depthMid = smoothstep(0.15, 0.55, depth);
  color = mix(color, baseColor, depthFade * 0.3);
  color = mix(color, color * 1.1, depthMid * bass * 0.3);

  // ── Alpha: Fresnel reflectance + liquid density ──
  let normal = normalize(vec3<f32>(
    -totalDisplacement.x * 30.0,
    -totalDisplacement.y * 30.0,
    1.0
  ));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let viewDotNormal = max(dot(viewDir, normal), 0.0);
  let F0 = 0.03;
  let fresnel = schlickFresnel(viewDotNormal, F0);
  let thickness = magnitude * 3.0 + glassThickness * 0.5 + 0.15;
  let absorptionAlpha = exp(-thickness * 1.2);
  let baseAlpha = mix(0.35, 0.8, absorptionAlpha);
  let avgColor = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let brightnessFactor = mix(0.9, 1.0, avgColor);
  let alpha = baseAlpha * brightnessFactor * (1.0 - fresnel * 0.3) * (0.8 + viscosity * 0.2);
  let finalAlpha = clamp(alpha, 0.2, 0.92);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, finalAlpha));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(color, finalAlpha));
  textureStore(dataTextureB, vec2<i32>(global_id.xy), vec4<f32>(magnitude, fresnel, depth, finalAlpha));

  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
