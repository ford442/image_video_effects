// ═══════════════════════════════════════════════════════════════════
//  Quantum Ghost v2
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, temporal-ghosting, interference-fringes,
//            upgraded-rgba, quantum-uncertainty, wave-packet, entanglement-correlation
//  Ideas:    1. packet re-emission — wave packets are re-emitted from the cursor every few
//               seconds (HEAD's packets used absolute time and left the screen for good)
//            2. fringe visibility — double-slit fringes only show where ghost and source
//               overlap coherently, V = 2√(I₁I₂)/(I₁+I₂)
//            3. click collapse — a click measures the state: ghosts snap back into the
//               source with a flash
//  A packing: chromatic ghost history (raw linear RGB) + alpha; C reads it back.
//  Complexity: Very High
//  Chunks From: quantum-ghost.wgsl v1
//  Created: 2026-05-31
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn gaussianWavePacket(uv: vec2<f32>, center: vec2<f32>, sigma: f32, momentum: vec2<f32>, time: f32) -> f32 {
  let drift = momentum * time * 0.1;
  let d = uv - center - drift;
  let spread = sigma + time * 0.02;
  let amp = exp(-dot(d, d) / (2.0 * spread * spread));
  let phase = dot(d, momentum) * 20.0 - time * 3.0;
  return amp * cos(phase);
}

fn quantumNumberGlow(n: i32, uv: vec2<f32>, time: f32) -> vec3<f32> {
  let col = select(select(vec3<f32>(0.0, 1.0, 0.8), vec3<f32>(1.0, 0.2, 0.9), n == 2), vec3<f32>(0.2, 0.6, 1.0), n == 1);
  let pulse = 0.7 + 0.3 * sin(time * 4.0 + f32(n) * 1.7);
  return col * pulse;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Idea 3: click collapse. A fresh click measures the state; the ghost offset
  // falls to zero (ghosts snap back into the source) and the click point flashes.
  var collapse = 0.0;
  var collapseFlash = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age < 0.0 || age > 1.5) { continue; }
    let c = exp(-age * 4.0);
    collapse = max(collapse, c);
    let rd = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
    collapseFlash += c * exp(-rd * rd * 40.0);
  }

  let offsetStrength = u.zoom_params.x * 0.06 * (1.0 + bass * 0.4) * (1.0 - collapse);
  let fringeFreq = u.zoom_params.y * 60.0;
  let ghostDecay = 0.82 + u.zoom_params.z * 0.16;
  let chromaticShift = u.zoom_params.w * 0.012;

  let uncertaintySpread = (1.0 - depth) * 0.15 * (1.0 + bass * 0.5);
  let measurementCertainty = select(0.3 + depth * 0.5, 1.0, mouseDown > 0.5);

  let dir = normalize(uv - mousePos + vec2<f32>(0.001));
  let offset = dir * offsetStrength;

  let mainColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Idea 1: packet re-emission. Each packet runs on a local clock that resets
  // every 4 s, so new packets keep leaving the cursor; two are staggered, and
  // each fades as it spreads.
  let period = 4.0;
  let tA = fract(time / period) * period;
  let tB = fract(time / period + 0.5) * period;
  let wave1 = gaussianWavePacket(uv, mousePos, 0.08 + uncertaintySpread, dir, tA * 2.5) * (1.0 - tA / period);
  let wave2 = gaussianWavePacket(uv, mousePos + offset * 2.0, 0.06, dir * 1.3, tB * 2.5) * (1.0 - tB / period);
  let interference = (wave1 + wave2) * 0.5;

  let ghostUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
  let ghostColor = textureSampleLevel(readTexture, u_sampler, ghostUV, 0.0);

  let prevGhost = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
  let temporalGhost = mix(ghostColor, prevGhost, ghostDecay);

  let fringePhase = dot(uv - 0.5, dir) * fringeFreq * (1.0 + treble * 0.6);
  let fringeRaw = cos(fringePhase) * 0.5 + 0.5;
  // Idea 2: fringe visibility. Two beams interfere with contrast
  // V = 2√(I₁I₂)/(I₁+I₂): equal intensities give full fringes, and a bright
  // ghost over a dark source washes them out.
  let i1 = dot(mainColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let i2 = dot(ghostColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  // Raised to the 6th power so the falloff reads on screen: physical V stays
  // above 0.9 for most photo pairs.
  let visibility = pow(2.0 * sqrt(max(i1 * i2, 0.0)) / max(i1 + i2, 1e-3), 6.0);
  let fringe = mix(0.5, fringeRaw, visibility);

  let rGhostUV = clamp(ghostUV + vec2<f32>(chromaticShift * (1.0 + uncertaintySpread * 3.0), 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let bGhostUV = clamp(ghostUV - vec2<f32>(chromaticShift * (1.0 + uncertaintySpread * 3.0), 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  // Decay now applies to all three channels (HEAD only trailed green).
  let rGhost = mix(textureSampleLevel(readTexture, u_sampler, rGhostUV, 0.0).r, prevGhost.r, ghostDecay);
  let bGhost = mix(textureSampleLevel(readTexture, u_sampler, bGhostUV, 0.0).b, prevGhost.b, ghostDecay);

  let depthAtten = mix(1.0, 0.25, depth);
  let ghostMix = temporalGhost.rgb;

  // Entanglement line through the cursor along a slowly turning axis. HEAD
  // measured distance along the radial direction's own normal, which is 0
  // everywhere and washed the whole frame.
  let axis = vec2<f32>(cos(time * 0.2), sin(time * 0.2));
  let entangleLine = smoothstep(0.02, 0.0, abs(dot((uv - mousePos) * vec2<f32>(aspect, 1.0), vec2<f32>(-axis.y, axis.x))));
  let entangleGlow = entangleLine * 0.4 * (0.5 + 0.5 * sin(time * 6.0)) * (1.0 - measurementCertainty);

  let qn = i32(fract(time * 0.3) * 3.0) + 1;
  let qnGlow = quantumNumberGlow(qn, uv, time) * entangleGlow * 2.0;

  var rgb = vec3<f32>(
    mix(mainColor.r, rGhost, fringe * 0.35 * depthAtten),
    mix(mainColor.g, ghostMix.g, fringe * 0.28 * depthAtten),
    mix(mainColor.b, bGhost, fringe * 0.35 * depthAtten)
  );

  rgb = rgb + vec3<f32>(interference * 0.15 * depthAtten);
  rgb = rgb + qnGlow;

  let bloom = max(entangleGlow * 3.0, 0.0) * vec3<f32>(1.0, 0.9, 0.6);
  rgb = rgb + bloom * (1.0 + bass * 0.5);

  let fringeTint = vec3<f32>(0.0, mids * 0.12, mids * 0.18) * fringe;
  var finalRGB = rgb + fringeTint + vec3<f32>(0.7, 0.85, 1.0) * collapseFlash * 0.9;

  // Clamp first: packet troughs go negative on dark pixels, and this ACES fit
  // maps negatives to bright values.
  finalRGB = acesToneMap(max(finalRGB, vec3<f32>(0.0)) * 1.2);

  let waveAmp = abs(interference) * depthAtten;
  // Semantic alpha: the frame is covered; packets, ghost fringes and the
  // collapse flash add emission on top (HEAD sat at ~0.03-0.12).
  let alpha = clamp(0.6 + waveAmp * measurementCertainty * 0.4 + fringe * 0.1 * depthAtten + collapseFlash * 0.2 + bass * 0.04, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(rGhost, temporalGhost.g, bGhost, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
