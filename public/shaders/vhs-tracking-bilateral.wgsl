// ═══════════════════════════════════════════════════════════════════
//  VHS Tracking Bilateral
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: lagging chroma bandwidth; dropout comet streaks; bass tape-stretch wow
//  A packing: ACES display RGBA in A (alpha = tracking band/click/depth coverage)
// ═══════════════════════════════════════════════════════════════════
// AR(1) capstan jitter, chroma phase noise, control-track dropouts, tracking-band
// bilateral smoothing at the cursor row, held freeze, click dropout pulses, C smear.

#include "_prelude.wgsl"

fn hash2(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn rgbToYuv(rgb: vec3<f32>) -> vec3<f32> {
  return vec3<f32>(
    dot(rgb, vec3<f32>(0.299, 0.587, 0.114)),
    dot(rgb, vec3<f32>(-0.14713, -0.28886, 0.436)),
    dot(rgb, vec3<f32>(0.615, -0.51499, -0.10001))
  );
}

fn yuvToRgb(yuv: vec3<f32>) -> vec3<f32> {
  return vec3<f32>(
    yuv.x + 1.13983 * yuv.z,
    yuv.x - 0.39465 * yuv.y - 0.58060 * yuv.z,
    yuv.x + 2.03211 * yuv.y
  );
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

  // extraBuffer[133..138] is re-uploaded as zeros each frame; the old spring never ran.
  let smoothMouse = mouse;

  let trackingError = u.zoom_params.x;
  let chromaNoiseAmt = u.zoom_params.y;
  let spatialSigma = mix(0.5, 4.0, u.zoom_params.z);
  let colorSigma = mix(0.05, 0.5, u.zoom_params.w);
  let pixelSize = 1.0 / resolution;

  let trackingY = smoothMouse.y;
  let bandDist = abs(uv.y - trackingY);
  let inTrackingBand = 1.0 - smoothstep(0.0, 0.08 + trackingError * 0.12, bandDist);
  let freezeMix = select(1.0, 0.35, held);

  let scanlineIndex = floor(uv.y * resolution.y);
  let arJitter = (noise(vec2<f32>(scanlineIndex * 0.1, time * 0.3)) - 0.5) * trackingError * 0.02 * freezeMix;
  // Idea 3 — bass tape-stretch wow: line timebase stretches about centre with slow flutter
  let wow = (sin(time * 1.3 + uv.y * 2.0) * 0.6 + sin(time * 3.7) * 0.4) * (0.004 + bass * 0.012) * trackingError * freezeMix;
  let jitteredUV = vec2<f32>((uv.x - 0.5) * (1.0 + wow) + 0.5 + arJitter, uv.y);

  var yuv = rgbToYuv(textureSampleLevel(readTexture, u_sampler, jitteredUV, 0.0).rgb);
  // Idea 1 — lagging chroma bandwidth: U/V come from a low-pass, delayed tap row (luma stays sharp)
  let lag = (1.5 + chromaNoiseAmt * 4.0) * pixelSize.x;
  var uvLow = vec2<f32>(0.0);
  for (var k = 0; k < 5; k++) {
    let tap = rgbToYuv(textureSampleLevel(readTexture, u_sampler, jitteredUV - vec2<f32>(lag * (1.0 + f32(k) * 0.6), 0.0), 0.0).rgb);
    uvLow += tap.yz * 0.2;
  }
  yuv = vec3<f32>(yuv.x, mix(yuv.yz, uvLow, 0.35 + chromaNoiseAmt * 0.5));
  let phaseNoise = sin(uv.y * 120.0 + time * (2.0 + trackingError * 5.0)) * chromaNoiseAmt * 0.1;
  yuv.y += (noise(uv * 300.0 + vec2<f32>(time * 50.0, 0.0)) - 0.5) * chromaNoiseAmt * 0.4 + phaseNoise;
  yuv.z += (noise(uv * 320.0 + vec2<f32>(0.0, time * 45.0)) - 0.5) * chromaNoiseAmt * 0.4 + phaseNoise * 0.7;
  yuv.x += (noise(uv * 200.0 + time * 60.0) - 0.5) * chromaNoiseAmt * 0.08;

  var color = yuvToRgb(yuv);

  let dropoutBase = uv.y * 20.0 - time * 2.0;
  let dropoutPhase = fract(dropoutBase);
  let dropoutEnvelope = exp(-dropoutPhase * 10.0);
  let dropoutRand = hash2(vec2<f32>(floor(dropoutBase), time * 0.5));
  let dropoutActive = step(1.0 - trackingError * 0.3, dropoutRand);
  color += (noise(uv * 500.0 + time * 100.0) - 0.5) * dropoutEnvelope * dropoutActive * 0.5;

  // Idea 2 — dropout comet streaks: oxide-loss flashes that start white and decay rightward along the line
  let cometSeed = vec2<f32>(scanlineIndex, floor(time * 12.0));
  let cometOn = step(1.0 - (0.004 + treble * 0.01) * (0.3 + trackingError * 2.0), hash2(cometSeed));
  let cometX = hash2(cometSeed + 7.1);
  let cometT = (uv.x - cometX) / (0.06 + 0.2 * hash2(cometSeed + 3.3));
  let comet = cometOn * step(0.0, cometT) * exp(-cometT * 3.0) * freezeMix;
  color = mix(color, vec3<f32>(0.95), clamp(comet, 0.0, 1.0) * 0.85);

  let headSwitchY = trackingY + sin(time * 2.0) * 0.02;
  let headSwitchBand = smoothstep(0.03, 0.0, abs(uv.y - headSwitchY));
  color += (hash2(vec2<f32>(uv.x * 100.0, time * 30.0)) - 0.5) * headSwitchBand * trackingError * 0.3;

  let center = color;
  var accumColor = vec3<f32>(0.0);
  var accumWeight = 0.0;
  let maxRadius = min(i32(ceil(spatialSigma * 2.5)), 5);
  for (var dy = -maxRadius; dy <= maxRadius; dy++) {
    for (var dx = -maxRadius; dx <= maxRadius; dx++) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let neighbor = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
      let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
      let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * spatialSigma * spatialSigma + 0.001));
      let colorDist = length(neighbor - center);
      let rangeWeight = exp(-colorDist * colorDist / (2.0 * colorSigma * colorSigma + 0.001));
      let weight = spatialWeight * rangeWeight * inTrackingBand;
      accumColor += neighbor * weight;
      accumWeight += weight;
    }
  }
  if (accumWeight > 0.001) {
    color = mix(color, accumColor / accumWeight, 0.6 * inTrackingBand);
  }

  var clickPulse = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.5) {
      let radius = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      clickPulse = max(clickPulse, exp(-age * 2.0) * (1.0 - smoothstep(0.0, 0.1, radius)));
    }
  }
  color += vec3<f32>(0.9, 0.85, 0.75) * clickPulse * 0.4;

  let scanline = sin(uv.y * resolution.y * 0.5 * 3.14159) * 0.5 + 0.5;
  let luma = rgbToYuv(color).x;
  color *= mix(1.0, scanline * mix(0.7, 1.0, luma), 0.15);

  let quantizationSteps = 32.0 + (1.0 - chromaNoiseAmt) * 64.0;
  color = floor(color * quantizationSteps) / quantizationSteps;
  color = mix(vec3<f32>(luma), color, 0.85) * 0.92 + 0.05;

  let prev = textureLoad(dataTextureC, coord, 0).rgb;
  color = mix(color, prev, 0.06 * trackingError + clickPulse * 0.08);

  color = acesToneMap(color * (0.95 + bass * 0.05));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  // Rescue: alpha was depth*0.85 (≈0 on flat/zero depth → output vanished); keep depth as a minor term
  let alpha = clamp(0.82 + depth * 0.08 + inTrackingBand * 0.06 + clickPulse * 0.1 + mids * 0.03, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
