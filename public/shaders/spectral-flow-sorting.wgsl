// ═══════════════════════════════════════════════════════════════════
//  Spectral Flow Sorting
//  Category: distortion
//  Features: advanced-hybrid, pixel-sorting, optical-flow, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09, 2026-11-01
//  Ideas: exact-C Lucas-Kanade; Asendorf close along the flow; aperture gate; flow barb
//  A packing: raw previous RGB (LK history). ACES on writeTexture only.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn luma3(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyCoord(uv: vec2<f32>, dims: vec2<i32>) -> vec2<i32> {
  return clamp(vec2<i32>(uv * vec2<f32>(dims)), vec2<i32>(0), dims - vec2<i32>(1));
}

fn loadC(uv: vec2<f32>, dims: vec2<i32>) -> vec3<f32> {
  return textureLoad(dataTextureC, historyCoord(uv, dims), 0).rgb;
}

// Idea 1 — exact-C Lucas-Kanade (no filtering sampler on history).
// Returns flow.xy and .z = gradient confidence (aperture gate).
fn calculateOpticalFlow(uv: vec2<f32>, pixel: vec2<f32>, dims: vec2<i32>, current: vec3<f32>) -> vec3<f32> {
  let currLuma = luma3(current);
  let prevLuma = luma3(loadC(uv, dims));
  let right = luma3(loadC(uv + vec2<f32>(pixel.x, 0.0), dims));
  let left = luma3(loadC(uv - vec2<f32>(pixel.x, 0.0), dims));
  let up = luma3(loadC(uv + vec2<f32>(0.0, pixel.y), dims));
  let down = luma3(loadC(uv - vec2<f32>(0.0, pixel.y), dims));
  let dx = (right - left) * 0.5;
  let dy = (up - down) * 0.5;
  let dt = currLuma - prevLuma;
  let grad = length(vec2<f32>(dx, dy));
  let conf = grad / (grad + 0.02);
  return vec3<f32>(vec2<f32>(dx, dy) * dt * 10.0, conf);
}

fn analyzeFrequency(uv: vec2<f32>, pixel: vec2<f32>) -> f32 {
  var gradientSum = 0.0;
  var sampleCount = 0.0;
  for (var i: i32 = -2; i <= 2; i++) {
    for (var j: i32 = -2; j <= 2; j++) {
      let offset = vec2<f32>(f32(i), f32(j)) * pixel * 3.0;
      let sample = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
      let nextSample = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset + vec2<f32>(pixel.x * 3.0, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
      gradientSum += abs(luma3(sample) - luma3(nextSample));
      sampleCount += 1.0;
    }
  }
  return gradientSum / max(sampleCount, 1.0);
}

// Idea 2 — Asendorf close along the flow: stop when luma drops; keep brightest.
fn sortAlongFlow(uv: vec2<f32>, flowDir: vec2<f32>, threshold: f32) -> vec3<f32> {
  let here = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  var best = here;
  var bestL = luma3(here);
  if (bestL < threshold) {
    return here;
  }
  for (var i: i32 = 1; i <= 8; i++) {
    let t = f32(i) / 8.0;
    let sampleUV = uv + flowDir * t * 0.1;
    if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) {
      break;
    }
    let sample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let sl = luma3(sample);
    if (sl < threshold) {
      break;
    }
    if (sl > bestL) {
      bestL = sl;
      best = sample;
    }
  }
  return best;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let pixel = 1.0 / resolution;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let id = vec2<i32>(global_id.xy);
  let dims = vec2<i32>(textureDimensions(dataTextureC));

  let flowSensitivity = mix(0.0, 5.0, u.zoom_params.x);
  let sortThreshold = u.zoom_params.y;
  let freqInfluence = u.zoom_params.z;
  let smoothing = mix(0.0, 0.9, u.zoom_params.w);

  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;
  let distToMouse = length(uv - mousePos);
  let mouseGravity = 1.0 - smoothstep(0.0, 0.35, distToMouse);
  let clickPulse = select(0.0, 1.0, isMouseDown) * sin(distToMouse * 25.0 - time * 5.0) * exp(-distToMouse * 3.0);

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let mouseDir = normalize(uv - mousePos + vec2<f32>(0.001));
  let cursorFlow = mouseDir * mouseGravity * 3.0 * (1.0 + select(0.0, 3.0, isMouseDown));
  // ── Idea 3: aperture gate ──────────────────────────────────────
  // Flat regions have no reliable LK gradient. Confidence scales only
  // the optical term. Cursor flow and the click pulse stay.
  let lk = calculateOpticalFlow(uv, pixel, dims, baseColor.rgb);
  let flow = lk.xy * flowSensitivity * (1.0 + bass * 0.35) * lk.z + cursorFlow + vec2<f32>(clickPulse);
  let flowMag = length(flow);
  let flowDir = select(vec2<f32>(0.0), flow / max(flowMag, 0.001), flowMag > 0.001);

  let dominantFreq = analyzeFrequency(uv, pixel);
  let sortedColor = sortAlongFlow(uv, flowDir, sortThreshold);
  let freqColor = vec3<f32>(dominantFreq * 2.0, dominantFreq * 1.5, dominantFreq * 3.0);

  var color = mix(baseColor.rgb, sortedColor, clamp(flowMag * smoothing, 0.0, 1.0));
  color = mix(color, freqColor, clamp(dominantFreq * freqInfluence, 0.0, 1.0));

  let flowAngle = atan2(flow.y, flow.x) / 6.28 + 0.5;
  let flowColor = vec3<f32>(
    0.5 + 0.5 * cos(flowAngle * 6.28),
    0.5 + 0.5 * cos(flowAngle * 6.28 + 2.09),
    0.5 + 0.5 * cos(flowAngle * 6.28 + 4.18)
  );
  color = mix(color, flowColor, clamp(flowMag * 0.3, 0.0, 1.0));

  // ── Idea 4: flow barb ──────────────────────────────────────────
  // A short tick across the flow where the vector is strong and the
  // pixel is inside the sort threshold. Frequency Influence still
  // owns the false-colour mix above.
  let perpFlow = vec2<f32>(-flowDir.y, flowDir.x);
  let barbPhase = fract(dot(uv * resolution, perpFlow) / 7.0);
  let barb = smoothstep(0.86, 1.0, barbPhase) * smoothstep(0.15, 0.6, flowMag) * f32(luma3(sortedColor) > sortThreshold);
  color = color * (1.0 - 0.18 * barb);

  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = max(time - event.z, 0.0);
    clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(u.config.z / max(u.config.w, 1.0), 1.0)) - age * 0.38) * 58.0);
  }
  let clockRings = sin(length(uv - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
  let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));
  color = color + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = clamp(mix(0.8, 1.0, flowMag * 0.5) + mouseGravity * 0.2 + f32(luma3(sortedColor) > sortThreshold) * 0.1 + barb * 0.1 + lk.z * 0.05, 0.0, 1.0);
  let display = acesToneMap(color);

  // Raw previous RGB in A for next LK — do not ACES stored fields.
  textureStore(dataTextureA, id, vec4<f32>(baseColor.rgb, baseColor.a));
  textureStore(writeTexture, id, vec4<f32>(display, alpha));
  textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
