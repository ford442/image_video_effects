// ═══════════════════════════════════════════════════════════════════
//  mouse-synesthetic-sound-paint
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, generative
//  Complexity: High
//  Chunks From: chunk-library.md (hash12, palette, fbm2, valueNoise)
//  Created: 2026-04-18
//  By: Agent 2C
// ═══════════════════════════════════════════════════════════════════
//  Combines mouse interaction with audio reactivity. Screen regions
//  map to different instruments. Without audio, falls back to mouse-
//  responsive color synthesis where position determines pattern and
//  drag speed determines energy. Alpha stores energy level.
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

@compute @workgroup_size(8, 8, 1)
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
  let mouseVel = length((mousePos - prevMouse) * vec2<f32>(aspect, 1.0)) * 60.0;

  // Store mouse position
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  // Read previous energy from dataTextureC
  let prevEnergy = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).a;

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

    energy = energy + bassBlob + trebleSparkle + abs(midWave);
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
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, energy));

  // Alpha = energy level
  let alpha = clamp(energy * 0.3, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
