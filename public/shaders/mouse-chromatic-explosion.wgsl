// ═══════════════════════════════════════════════════════════════════
//  mouse-chromatic-explosion
//  Category: interactive-mouse
//  Features: mouse-driven, chromatic, prism, upgraded-rgba
//  Complexity: Medium
//  Chunks From: chunk-library.md (none)
//  Created: 2026-04-18
//  By: Agent 2C
//  Upgraded: Single displacement field + spectral tint via mix
// ═══════════════════════════════════════════════════════════════════
//  The mouse drives a smooth displacement field. Spectral variation
//  is applied via mix() with wavelengthToRGB, not per-channel UV
//  sampling. Alpha encodes total displacement magnitude for
//  translucency compositing. Audio-reactive bass pulses the field.
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

fn tentAlpha(x: f32) -> f32 {
  return smoothstep(0.0, 0.4, x) * (1.0 - smoothstep(0.4, 1.0, x));
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

fn gaussianMask(dist: f32, sigma: f32) -> f32 {
  return exp(-dist * dist / (2.0 * sigma * sigma));
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

  let prismStrength = mix(0.02, 0.12, u.zoom_params.x);
  let dispersion = mix(0.5, 3.0, u.zoom_params.y);
  let rippleStrength = u.zoom_params.z;
  let saturationBoost = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Audio-reactive bass pulse displaces the entire field
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let bassPulse = 1.0 + bass * 0.5 + mids * 0.15;

  // Compute SINGLE smooth displacement field from mouse
  let toMouse = uv - mousePos;
  let distToMouse = length(toMouse * vec2<f32>(aspect, 1.0));
  let prismAngle = atan2(toMouse.y, toMouse.x);

  // Deflection proportional to distance (inverse) with bass pulse
  let deflection = prismStrength * bassPulse / max(distToMouse, 0.02);
  let perpendicular = vec2<f32>(-sin(prismAngle), cos(prismAngle));
  let smoothOffset = perpendicular * deflection;

  // Ripple contributions: accumulate into single offset (not per-channel)
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleOffset = vec2<f32>(0.0);

  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.5) {
      let rPos = ripple.xy;
      let rDist = length((uv - rPos) * vec2<f32>(aspect, 1.0));
      let wave = sin(rDist * 30.0 - elapsed * 10.0) * exp(-elapsed * 1.5) * smoothstep(0.5, 0.0, rDist);
      let dir = select(vec2<f32>(0.0), normalize((uv - rPos) * vec2<f32>(aspect, 1.0)), rDist > 0.001);
      rippleOffset = rippleOffset + dir * wave * rippleStrength * 0.03;
    }
  }

  // Mouse down intensifies effect
  let intensity = 1.0 + mouseDown * 1.5;

  // Add treble-driven micro-wobble for high-frequency texture shimmer
  let treble = plasmaBuffer[0].z;
  let microWobble = vec2<f32>(
    sin(uv.x * 40.0 + time * 5.0) * treble * 0.003,
    cos(uv.y * 40.0 + time * 4.0) * treble * 0.003
  );

  // Single displaced UV — sample full RGB once
  let totalOffset = (smoothOffset + rippleOffset + microWobble) * intensity;
  let displacedUV = uv + totalOffset;
  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  // Spectral tint via mix(), NOT per-channel sampling
  let wavelength = mix(380.0, 780.0, dispersion * 0.5 + length(totalOffset) * 3.0);
  let spectralTint = wavelengthToRGB(wavelength);
  let tintStrength = clamp(length(totalOffset) * 4.0, 0.0, 1.0);
  let color = mix(baseColor, baseColor * spectralTint, tintStrength);

  // Saturation boost for psychedelic effect
  let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  var finalColor = mix(vec3<f32>(lum), color, 1.0 + saturationBoost);

  // Add spectral glow near mouse
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let glow = exp(-mouseDist * mouseDist * 100.0) * prismStrength * 10.0;
  finalColor = finalColor + vec3<f32>(0.5, 0.3, 0.8) * glow;

  // Second harmonic glow for richer halo
  let halo = gaussianMask(mouseDist, 0.15) * prismStrength * 3.0;
  finalColor = finalColor + vec3<f32>(0.2, 0.5, 0.9) * halo;

  // Time-based breathing pulse across entire field
  let breathe = 1.0 + sin(time * 1.2) * 0.03 * bassPulse;
  finalColor = finalColor * breathe;

  // Depth-aware blending: attenuate displacement on distant geometry
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(0.4, 1.0, 1.0 - depth * 0.6);
  var depthBlended = mix(baseColor, finalColor, depthFactor);

  // Subtle radial chromatic darkening at extreme edges
  let edgeDarken = 1.0 - smoothstep(0.3, 0.8, mouseDist);
  depthBlended = depthBlended * mix(0.9, 1.0, edgeDarken);

  // Alpha = total displacement * intensity + ripple contribution
  let totalDisp = length(totalOffset);
  let alpha = clamp(totalDisp * 5.0 + tentAlpha(totalDisp * 3.0) * 0.4 + gaussianMask(mouseDist, 0.25) * 0.2, 0.0, 1.0);
  let depthAlpha = alpha * mix(0.5, 1.0, 1.0 - depth * 0.5);

  // Store color with translucency alpha for compositing
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(depthBlended, depthAlpha));

  // Depth passthrough to preserve depth pipeline
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
