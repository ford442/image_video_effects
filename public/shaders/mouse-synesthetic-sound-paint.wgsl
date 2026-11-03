// ═══════════════════════════════════════════════════════════════════
//  mouse-synesthetic-sound-paint
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, generative
//  Complexity: High
//  Chunks From: chunk-library.md (hash12, palette, fbm2, valueNoise)
//  Created: 2026-04-18
//  By: Agent 2C
//  Upgraded: 2026-11-01
//  Ideas: bass kick-ring expanding from the cursor; wet bleed diffuses stored energy to neighbours
//  A packing: colour.rgb + energy.a; texel (0,0) = (prevMouse.xy, 0, 0) state
// ═══════════════════════════════════════════════════════════════════
//  Combines mouse interaction with audio reactivity. Screen regions
//  map to different instruments. Without audio, falls back to mouse-
//  responsive color synthesis where position determines pattern and
//  drag speed determines energy. Alpha stores energy level.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: valueNoise (from gen_grid.wgsl) ═══
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  let a = hash12(i + vec2<f32>(0.0, 0.0));
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ═══ CHUNK: fbm2 (from gen_grid.wgsl) ═══
fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value = value + amplitude * valueNoise(p * frequency);
    amplitude = amplitude * 0.5;
    frequency = frequency * 2.0;
  }
  return value;
}

// ═══ CHUNK: palette (from gen-xeno-botanical-synth-flora.wgsl) ═══
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
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

  let audioSensitivity = mix(0.5, 3.0, u.zoom_params.x);
  let patternScale = mix(2.0, 20.0, u.zoom_params.y);
  let energyDecay = mix(0.8, 0.98, u.zoom_params.z);
  let colorShiftSpeed = u.zoom_params.w * 2.0;

  let mousePos = u.zoom_config.yz;
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let isStateTexel = global_id.x == 0u && global_id.y == 0u;
  let mouseVel = min(length((mousePos - prevMouse) * vec2<f32>(aspect, 1.0)) * 60.0, 4.0);

  // Read previous energy exactly from dataTextureC; Idea 2 — wet bleed: energy spreads to the 4 neighbours
  // (texel (0,0) holds mouse state, so it is never sampled as energy)
  let pc = vec2<i32>(global_id.xy);
  let maxPc = vec2<i32>(resolution) - vec2<i32>(1);
  var bleedSum = 0.0;
  var bleedN = 0.0;
  for (var k = 0; k < 4; k = k + 1) {
    var d = vec2<i32>(1, 0);
    if (k == 1) { d = vec2<i32>(-1, 0); }
    if (k == 2) { d = vec2<i32>(0, 1); }
    if (k == 3) { d = vec2<i32>(0, -1); }
    let q = clamp(pc + d, vec2<i32>(0), maxPc);
    if (q.x != 0 || q.y != 0) {
      bleedSum = bleedSum + textureLoad(dataTextureC, q, 0).a;
      bleedN = bleedN + 1.0;
    }
  }
  let ownEnergy = select(textureLoad(dataTextureC, pc, 0).a, 0.0, isStateTexel);
  let prevEnergy = mix(ownEnergy, bleedSum / max(bleedN, 1.0), 0.22);

  // Audio input (if available)
  let bass = plasmaBuffer[0].x * audioSensitivity;
  let mids = plasmaBuffer[0].y * audioSensitivity;
  let treble = plasmaBuffer[0].z * audioSensitivity;
  let hasAudio = bass + mids + treble > 0.01;

  // Mouse region determines instrument / pattern
  let region = mousePos.y; // 0=bottom (bass), 0.5=mids, 1.0=treble

  // Energy accumulates from mouse movement and audio
  var energy = prevEnergy * energyDecay;
  let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
  let mouseInfluence = exp(-mouseDist * mouseDist * 100.0);
  energy = energy + mouseVel * mouseInfluence * 0.5;

  if (hasAudio) {
    // Bass blob at bottom
    let bassRegion = smoothstep(0.4, 0.0, region) * bass;
    let bassBlob = exp(-mouseDist * mouseDist * 50.0) * bassRegion;

    // Treble sparkles at top
    let trebleRegion = smoothstep(0.6, 1.0, region) * treble;
    let sparkle = hash12(uv * 200.0 + time * 10.0);
    let trebleSparkle = step(0.97, sparkle) * trebleRegion * mouseInfluence * 5.0;

    // Mids = flowing waves
    let midRegion = smoothstep(0.3, 0.7, region) * mids;
    let midWave = sin(uv.x * 20.0 + time * 3.0) * midRegion * mouseInfluence;

    // Idea 1 — kick ring: each bass swell sends a ring out from the cursor
    let ringR = fract(time * 0.9) * 0.35;
    let kickRing = exp(-pow((mouseDist - ringR) * 40.0, 2.0)) * bass * smoothstep(0.4, 0.0, region) * (1.0 - ringR / 0.35);
    energy = energy + bassBlob + trebleSparkle + abs(midWave) + kickRing * 0.8;
  }

  // Ripple bursts add energy
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 2.0) {
      let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
      let rBurst = exp(-rDist * rDist * 200.0) * exp(-elapsed * 2.0);
      energy = energy + rBurst * 2.0;
    }
  }

  energy = clamp(energy, 0.0, 5.0);

  // Visual pattern based on mouse position and energy
  let patternUV = uv * patternScale;
  var pattern = 0.0;

  if (hasAudio) {
    // Audio-reactive patterns
    let noiseVal = fbm2(patternUV + time * 0.2 + mousePos * 5.0, 4);
    let waveVal = sin(patternUV.x * 3.0 + time + bass * 3.0) * cos(patternUV.y * 3.0 + time + treble * 3.0);
    pattern = noiseVal * 0.5 + waveVal * 0.3 + energy * 0.2;
  } else {
    // Fallback: mouse-driven synthesis
    let mousePattern = fbm2(patternUV + mousePos * patternScale, 4);
    let velocityPattern = sin(patternUV.x * 5.0 + mouseVel * 10.0) * cos(patternUV.y * 5.0 + mousePos.x * 10.0);
    pattern = mousePattern * 0.6 + velocityPattern * 0.3 + energy * 0.1;
  }

  // Color from pattern
  let colorT = fract(pattern + time * colorShiftSpeed * 0.1 + region * 0.3);
  let synthColor = palette(colorT,
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(1.0, 1.0, 1.0),
    vec3<f32>(0.0, 0.33, 0.67)
  );

  // Mix with input image
  let baseImage = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let blendFactor = smoothstep(0.0, 1.0, energy) * 0.6;
  var finalColor = mix(baseImage, synthColor * (0.5 + energy * 0.3), blendFactor);

  // HDR energy burst
  finalColor = finalColor + vec3<f32>(0.5, 0.3, 0.8) * energy * mouseInfluence * 0.3;

  // Store energy for temporal continuity
  textureStore(dataTextureA, vec2<i32>(global_id.xy), select(vec4<f32>(finalColor, energy), vec4<f32>(mousePos, 0.0, 0.0), isStateTexel));

  // Alpha = energy level
  let alpha = clamp(energy * 0.3, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
