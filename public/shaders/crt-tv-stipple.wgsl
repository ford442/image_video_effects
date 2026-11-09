// ═══════════════════════════════════════════════════════════════════
//  CRT TV Stipple
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba, temporal-feedback
//  Complexity: Medium
//  Upgraded: 2026-11-09
//  Ideas: per-channel P22 afterglow (red slow, blue fast) from exact C; rolling hum bar up the tube; radial R/B stipple convergence error toward corners
//  A packing: ACES display RGBA (C read back as phosphor afterglow colour)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn curveUv(uv: vec2<f32>, curvature: f32) -> vec2<f32> {
  var centered = uv * 2.0 - 1.0;
  let distSq = dot(centered, centered);
  centered = centered * (1.0 + curvature * distSq);
  return centered * 0.5 + 0.5;
}

fn inverseCurveUv(uv: vec2<f32>, curvature: f32) -> vec2<f32> {
  var centered = uv * 2.0 - 1.0;
  let distSq = dot(centered, centered);
  centered = centered / (1.0 + curvature * distSq * 0.8);
  return centered * 0.5 + 0.5;
}

fn blueNoiseOffset(pixelCoord: vec2<f32>, frame: f32) -> vec2<f32> {
  let phi2 = vec2<f32>(1.3247179572, 1.7548776662);
  return fract(pixelCoord * phi2 + frame * phi2);
}

fn stippleGrille(uv: vec2<f32>, dotScale: f32, time: f32, conv: vec2<f32>) -> vec3<f32> {
  let cellId = floor(uv * dotScale);
  let cellLocal = fract(uv * dotScale) - 0.5;
  let sampleUV = (cellId + 0.5) / dotScale;
  let localColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
  let luma = dot(localColor, vec3<f32>(0.299, 0.587, 0.114));
  let triadX = fract(cellId.x / 3.0) * 3.0;
  var subpixelOffset = vec2<f32>(0.0);
  var mask = vec3<f32>(0.0);
  if (triadX < 1.0) { subpixelOffset = vec2<f32>(-0.25, 0.0); mask.r = 1.0; }
  else if (triadX < 2.0) { mask.g = 1.0; }
  else { subpixelOffset = vec2<f32>(0.25, 0.0); mask.b = 1.0; }
  let jitter = blueNoiseOffset(cellId + subpixelOffset * 10.0, time * 0.1);
  // Idea 3: convergence error — R and B guns land off-centre in opposite radial directions.
  let convShift = conv * (mask.r - mask.b);
  let dotCenter = (jitter - 0.5) * 0.6 + subpixelOffset * 0.3 + convShift;
  let dotSize = mix(0.45, 0.08, luma);
  let dist = length(cellLocal - dotCenter);
  let dotMask = 1.0 - smoothstep(dotSize - 0.06, dotSize + 0.06, dist);
  return mask * dotMask;
}

fn phosphorDecay(baseColor: vec3<f32>, time: f32, flicker: f32) -> vec3<f32> {
  let refreshFlicker = 1.0 - flicker * 0.03 * sin(time * 377.0);
  let humBar = 1.0 - flicker * 0.02 * sin(time * 6.28 * 0.5);
  // Rescue: HEAD lifted each channel with pow(c, 1/rate) (blue^0.1), a cyan-grey
  // wash. Decay now lives in the per-channel C afterglow in main().
  return baseColor * refreshFlicker * humBar;
}

fn halationGlow(uv: vec2<f32>, strength: f32, curvature: f32, resolution: vec2<f32>) -> vec3<f32> {
  if (strength < 0.01) { return vec3<f32>(0.0); }
  let invRes = 1.0 / resolution;
  var glow = vec3<f32>(0.0);
  var totalWeight = 0.0;
  let offsets = array<vec2<f32>, 5>(
    vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0) * invRes * 2.0, vec2<f32>(-1.0, 0.0) * invRes * 2.0,
    vec2<f32>(0.0, 1.0) * invRes * 2.0, vec2<f32>(0.0, -1.0) * invRes * 2.0
  );
  let weights = array<f32, 5>(0.4, 0.15, 0.15, 0.15, 0.15);
  for (var i = 0; i < 5; i = i + 1) {
    let sampleUV = uv + offsets[i];
    let flatSampleUV = inverseCurveUv(sampleUV, curvature);
    if (flatSampleUV.x >= 0.0 && flatSampleUV.x <= 1.0 && flatSampleUV.y >= 0.0 && flatSampleUV.y <= 1.0) {
      let sample = textureSampleLevel(readTexture, u_sampler, flatSampleUV, 0.0).rgb;
      let brightness = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
      glow += smoothstep(0.3, 0.8, brightness) * sample * weights[i];
      totalWeight += weights[i];
    }
  }
  if (totalWeight > 0.0) { glow /= totalWeight; }
  return glow * vec3<f32>(1.1, 0.95, 0.9) * strength * 2.0;
}

fn scanlines(uv: vec2<f32>, resolution: vec2<f32>, intensity: f32, time: f32, audioJitter: f32) -> f32 {
  let scanFreq = resolution.y * 0.5;
  let scanY = uv.y * scanFreq;
  let scanProfile = 0.5 + 0.5 * cos(fract(scanY) * 6.28318530718);
  let phosphorBright = smoothstep(0.0, 0.3, fract(scanY)) * smoothstep(1.0, 0.7, fract(scanY));
  let jitter = sin(time * 10.0 + uv.y * 100.0) * 0.02 * (1.0 + audioJitter * 5.0);
  let thickness = 0.85 + jitter;
  let scanDarken = 1.0 - intensity * 0.4 * (1.0 - smoothstep(thickness, 1.0, scanProfile));
  return scanDarken * (1.0 + intensity * 0.15 * phosphorBright);
}

fn crtVignette(uv: vec2<f32>, strength: f32) -> f32 {
  let centered = uv * 2.0 - 1.0;
  let dist = length(centered);
  let vig = 1.0 - smoothstep(0.6, 1.4, dist * (0.8 + strength * 0.4));
  return vig * (1.0 - abs(centered.x * centered.y) * 0.15 * strength);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let smoothMouse = mouse;

  let scanlineIntensity = u.zoom_params.x * (1.0 + mids * 0.5);
  let phosphorGlow = u.zoom_params.y * (1.0 + bass * 0.7);
  let stippleDensity = mix(20.0, 80.0, u.zoom_params.z) + treble * 20.0;
  let barrelAmount = u.zoom_params.w;

  var rippleFlash = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.0) {
      rippleFlash += smoothstep(0.15, 0.0, length((uv - rp.xy) * vec2<f32>(aspect, 1.0))) * (1.0 - age);
    }
  }

  let mouseBulge = smoothstep(0.25, 0.0, length((uv - smoothMouse) * vec2<f32>(aspect, 1.0))) * select(0.0, 0.12, held);
  let curvature = barrelAmount * 0.15 * (1.0 + bass * 0.5 + mouseBulge + rippleFlash * 0.08);
  let flickerAmount = 0.5 + barrelAmount * 0.5 + mids * 0.2;
  let chromaticStr = 0.002 * barrelAmount + treble * 0.005;

  var crtUV = select(uv, curveUv(uv, curvature), barrelAmount > 0.01);
  if (crtUV.x < 0.0 || crtUV.x > 1.0 || crtUV.y < 0.0 || crtUV.y > 1.0) {
    textureStore(writeTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, vec4<f32>(0.0, 0.0, 0.0, 1.0));
    let depth = textureLoad(readDepthTexture, coord, 0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    return;
  }

  let baseSample = textureSampleLevel(readTexture, u_sampler, crtUV, 0.0);
  // Idea 3 (cont.): misconvergence grows radially with barrel, so R/B separate at the corners.
  let radial = (crtUV - 0.5) * 2.0;
  let convDir = vec2<f32>(chromaticStr, 0.0) + radial * dot(radial, radial) * barrelAmount * 0.004;
  let r = textureSampleLevel(readTexture, u_sampler, crtUV + convDir, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, crtUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, crtUV - convDir, 0.0).b;
  var color = vec3<f32>(r, g, b);

  let stippleMask = stippleGrille(crtUV, stippleDensity, time, radial * dot(radial, radial) * barrelAmount * 0.18);
  color *= 0.3 + stippleMask * 0.7;
  color *= scanlines(crtUV, resolution, scanlineIntensity, time, mids);
  color += halationGlow(crtUV, phosphorGlow * 0.5, curvature, resolution);

  if (phosphorGlow > 0.01) {
    let brightness = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let bloom = smoothstep(0.4, 0.9, brightness) * phosphorGlow * 0.4;
    color = mix(color, pow(color, vec3<f32>(0.7)), phosphorGlow * 0.3);
    color += color * bloom;
  }

  color = phosphorDecay(color, time, flickerAmount);

  // Idea 2: rolling hum bar — a soft 60/50 Hz beat band drifting up the tube.
  let humPhase = fract(crtUV.y + time * (0.07 + mids * 0.05)) - 0.5;
  let humBand = exp(-humPhase * humPhase * 18.0);
  color *= 1.0 - flickerAmount * 0.07 + humBand * flickerAmount * 0.12;
  color *= crtVignette(uv, 0.5 + barrelAmount * 0.5);
  color *= vec3<f32>(1.05, 1.02, 0.98);

  // Idea 1: P22 afterglow — red phosphor persists longest, blue shortest. The
  // previous frame (exact C) decays per channel and only lifts dimmer pixels.
  // Applied in display space after ACES so persist < 1 always decays (no latch).
  // Exposure 1.9 restores the brightness HEAD's pow() lift gave the stipple.
  color = acesToneMap(color * (1.9 + bass * 0.1));
  let prev = textureLoad(dataTextureC, coord, 0).rgb;
  let persist = vec3<f32>(0.86, 0.72, 0.45) * (0.55 + u.zoom_params.y * 0.4);
  color = max(color, prev * persist);

  let maskScalar = dot(stippleMask, vec3<f32>(0.3333));
  let alpha = clamp(baseSample.a * 0.9 + rippleFlash * 0.15 + maskScalar * 0.1 + bass * 0.05, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
