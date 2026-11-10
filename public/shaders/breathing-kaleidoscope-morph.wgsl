// ═══════════════════════════════════════════════════════════════════
//  breathing-kaleidoscope-morph
//  Category: advanced-hybrid
//  Features: kaleidoscope, morphological, erosion-dilation, mouse-driven, audio-reactive
//  Complexity: Very High
//  Upgraded: 2026-11-10
//  Ideas: mirror-seam bevel along every reflecting edge; white top-hat detail re-injection
//  A packing: display RGB + top-hat luma in alpha
//  Chunks From: breathing-kaleidoscope, conv-morphological-erosion-dilation
//  Created: 2026-04-18
//  By: Agent CB-15 — Visual Effects & Distortion Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Breathing kaleidoscope mirrors combined with morphological
//  erosion/dilation. Each kaleidoscope segment can show a different
//  morphological operation, creating a living crystalline structure
//  that pulses between erosion and dilation with the breathing cycle.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn ping_pong(t: f32) -> f32 {
  return 1.0 - abs(fract(t * 0.5) * 2.0 - 1.0);
}

@compute @workgroup_size(16, 16, 1)
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
  // ── Idea 2: white top-hat detail re-injection ───────────────────────
  // topHat = centre - erosion is the small bright structure the erosion
  // removed. It was only feeding alpha; here it is added back on the
  // dilation side of the per-segment blend (morphBlend), scaled by the breath,
  // so eroded segments stay eroded and dilated ones keep their fine highlights.
  let detail = clamp(topHat, vec3<f32>(0.0), vec3<f32>(1.0)) * morphBlend * (0.2 + 0.3 * strength);
  var finalRGB = blendRGB + gradient * 0.3 + detail;

  // ── Idea 1: mirror-seam bevel ───────────────────────────────────────
  // A mirror tube shows a bright bevelled line wherever two reflecting
  // mirrors meet. mirroredAngle is 1 on a wedge boundary and 0 on the
  // in-wedge mirror, so both seams are min(m, 1 - m) away from 0. Distance is
  // converted to arc length in pixels so the line keeps a constant width at any
  // radius, fades at the apex, and only exists while the kaleidoscope does.
  let seamAngle = min(mirroredAngle, 1.0 - mirroredAngle) * segmentAngle * 0.5;
  let seamPx = seamAngle * radius * resolution.y;
  let seam = exp(-seamPx * 0.7) * smoothstep(0.005, 0.04, radius) * blend;
  finalRGB += (vec3<f32>(0.9, 0.95, 1.0) * 0.5 + centerSample.rgb * 0.5) * seam * 0.45;

  let topHatLuma = dot(topHat, vec3<f32>(0.299, 0.587, 0.114));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clampedUV, 0.0).r;

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, topHatLuma));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
