// ═══════════════════════════════════════════════════════════════════
//  breathing-kaleidoscope-morph
//  Category: advanced-hybrid
//  Features: kaleidoscope, morphological, erosion-dilation, mouse-driven, audio-reactive
//  Complexity: Very High
//  Chunks From: breathing-kaleidoscope, conv-morphological-erosion-dilation
//  Created: 2026-04-18
//  By: Agent CB-15 — Visual Effects & Distortion Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Breathing kaleidoscope mirrors combined with morphological
//  erosion/dilation. Each kaleidoscope segment can show a different
//  morphological operation, creating a living crystalline structure
//  that pulses between erosion and dilation with the breathing cycle.
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

fn ping_pong(t: f32) -> f32 {
  return 1.0 - abs(fract(t * 0.5) * 2.0 - 1.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let pixelSize = 1.0 / resolution;

  let cycleSpeed = u.zoom_params.x;
  let segments = max(1.0, u.zoom_params.y);
  let rotationSpeed = u.zoom_params.z;
  let maxRotationPercent = clamp(u.zoom_params.w, 0.0, 1.0);

  let kernelRadius = i32(mix(2.0, 6.0, u.zoom_params.x));
  let gradientBoost = mix(0.5, 3.0, u.zoom_params.z);

  let mousePos = u.zoom_config.yz;
  var center = mousePos;

  // Ripple distortion
  let rippleCount = min(u32(u.config.y), 50u);
  var mouseDisplacement = vec2<f32>(0.0);
  for (var i: u32 = 0u; i < rippleCount; i++) {
    let ripple = u.ripples[i];
    let timeSinceClick = time - ripple.z;
    if (timeSinceClick > 0.0 && timeSinceClick < 2.0) {
      let direction = uv - ripple.xy;
      let dist = length(direction);
      if (dist > 0.001) {
        let wave = sin(dist * 30.0 - timeSinceClick * 5.0);
        let falloff = exp(-timeSinceClick * 2.0) / (dist * 10.0 + 1.0);
        mouseDisplacement += (direction / dist) * wave * falloff * 0.05;
      }
    }
  }

  // Breathing strength
  let audioOverall = u.zoom_config.x;
  let audioReactivity = 1.0 + audioOverall * 0.3;
  let strength = ping_pong(time * cycleSpeed * audioReactivity);

  // Kaleidoscope geometry
  let segmentAngle = 6.28318530718 / segments;
  let maxRotation = segmentAngle * maxRotationPercent;
  let rotation = ping_pong(time * rotationSpeed * audioReactivity) * maxRotation;

  let delta = (uv + mouseDisplacement) - center;
  let angle = atan2(delta.y, delta.x);
  let radius = length(delta);

  let normalizedAngle = angle / segmentAngle;
  let mirroredAngle = abs(fract(normalizedAngle) * 2.0 - 1.0);
  let kaleidoAngle = (mirroredAngle * segmentAngle) + rotation;
  let kaleidoUV = center + vec2<f32>(cos(kaleidoAngle), sin(kaleidoAngle)) * radius;

  let blend = smoothstep(0.0, 1.0, strength);
  let finalUV = mix(uv, kaleidoUV, blend);
  let clampedUV = clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0));

  // ═══ MORPHOLOGICAL OPERATION ON KALEIDO SAMPLE ═══
  // Per-segment erosion/dilation blend based on segment index
  let segmentIndex = floor(normalizedAngle);
  let erosionDilationBlend = fract(segmentIndex * 0.618034) + strength * 0.3;

  let mouseDist = length(uv - mousePos);
  let mouseAngle = atan2(uv.y - mousePos.y, uv.x - mousePos.x);
  let mouseFactor = exp(-mouseDist * mouseDist * 6.0) * 0.5;

  let maxRadius = min(kernelRadius, 8);
  let centerSample = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0);
  let centerLuma = dot(centerSample.rgb, vec3<f32>(0.299, 0.587, 0.114));

  var minVal = vec3<f32>(999.0);
  var maxVal = vec3<f32>(-999.0);
  var minLuma = 999.0;
  var maxLuma = -999.0;

  for (var dy = -maxRadius; dy <= maxRadius; dy++) {
    for (var dx = -maxRadius; dx <= maxRadius; dx++) {
      var dxF = f32(dx);
      var dyF = f32(dy);
      if (mouseFactor > 0.01) {
        let cosA = cos(mouseAngle);
        let sinA = sin(mouseAngle);
        let rotX = dxF * cosA - dyF * sinA;
        let rotY = dxF * sinA + dyF * cosA;
        dxF = mix(dxF, rotX * 1.5, mouseFactor);
        dyF = mix(dyF, rotY * 0.6, mouseFactor);
      }
      if (dxF*dxF + dyF*dyF > f32(maxRadius*maxRadius)) { continue; }
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let sample = textureSampleLevel(readTexture, u_sampler, clampedUV + offset, 0.0).rgb;
      let luma = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
      minVal = min(minVal, sample);
      maxVal = max(maxVal, sample);
      minLuma = min(minLuma, luma);
      maxLuma = max(maxLuma, luma);
    }
  }

  let erosion = minVal;
  let dilation = maxVal;
  let gradient = (dilation - erosion) * gradientBoost;
  let topHat = centerSample.rgb - erosion;

  // Blend based on breathing cycle and segment
  let morphBlend = clamp(erosionDilationBlend, 0.0, 1.0);
  let blendRGB = mix(erosion, dilation, morphBlend);
  let finalRGB = blendRGB + gradient * 0.3;

  let topHatLuma = dot(topHat, vec3<f32>(0.299, 0.587, 0.114));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampedUV, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, topHatLuma));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
