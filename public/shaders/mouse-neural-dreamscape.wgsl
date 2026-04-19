// ═══════════════════════════════════════════════════════════════════
//  mouse-neural-dreamscape
//  Category: interactive-mouse
//  Features: mouse-driven, network, generative
//  Complexity: High
//  Chunks From: chunk-library.md (hash12, palette)
//  Created: 2026-04-18
//  By: Agent 2C
// ═══════════════════════════════════════════════════════════════════
//  A grid of virtual neurons activates based on mouse proximity.
//  Connections pulse between nearby activated cells. Click ripples
//  send activation waves propagating through the neural network.
//  Alpha channel stores neuron activation level.
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

  let networkDensity = mix(8.0, 40.0, u.zoom_params.x);
  let activationRadius = mix(0.05, 0.3, u.zoom_params.y);
  let pulseSpeed = mix(1.0, 5.0, u.zoom_params.z);
  let synapseStrength = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Neuron grid coordinates
  let neuronUV = uv * networkDensity;
  let neuronId = floor(neuronUV);
  let neuronFrac = fract(neuronUV);

  // Neuron center in UV space
  let neuronCenter = (neuronId + 0.5) / networkDensity;

  // Distance from pixel to neuron center
  let toNeuron = (uv - neuronCenter) * vec2<f32>(aspect, 1.0);
  let distToNeuron = length(toNeuron);

  // Base activation from mouse proximity
  let mouseToNeuron = length((neuronCenter - mousePos) * vec2<f32>(aspect, 1.0));
  var activation = smoothstep(activationRadius, 0.0, mouseToNeuron);

  // Mouse down boosts activation
  activation = activation * (1.0 + mouseDown * 2.0);

  // Ripple activation waves
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 3.0) {
      let rippleToNeuron = length((neuronCenter - ripple.xy) * vec2<f32>(aspect, 1.0));
      let wave = sin(rippleToNeuron * 20.0 - elapsed * pulseSpeed * 5.0);
      let waveEnvelope = smoothstep(activationRadius * 3.0, 0.0, rippleToNeuron) * exp(-elapsed * 0.8);
      activation = activation + waveEnvelope * max(wave, 0.0) * 0.5;
    }
  }

  // Decay from previous state
  let prevActivation = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).r;
  activation = max(activation, prevActivation * 0.95);
  activation = clamp(activation, 0.0, 2.0);

  // Store activation
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(activation, 0.0, 0.0, 0.0));

  // Synapse connections: check neighboring neurons
  var connectionGlow = 0.0;
  for (var dx: i32 = -1; dx <= 1; dx = dx + 1) {
    for (var dy: i32 = -1; dy <= 1; dy = dy + 1) {
      if (dx == 0 && dy == 0) { continue; }
      let neighborId = neuronId + vec2<f32>(f32(dx), f32(dy));
      let neighborCenter = (neighborId + 0.5) / networkDensity;
      let neighborAct = smoothstep(activationRadius, 0.0, length((neighborCenter - mousePos) * vec2<f32>(aspect, 1.0)));

      // Connection line from this pixel to neighbor
      let lineDir = neighborCenter - neuronCenter;
      let lineLen = length(lineDir * vec2<f32>(aspect, 1.0));
      let lineDirNorm = select(vec2<f32>(0.0), normalize(lineDir), lineLen > 0.001);

      let toPixel = uv - neuronCenter;
      let projection = dot(toPixel, lineDirNorm);
      let perpDist = length(toPixel - lineDirNorm * projection);

      let onLine = step(0.0, projection) * step(projection, lineLen) * smoothstep(0.003, 0.0, perpDist);
      connectionGlow = connectionGlow + onLine * activation * neighborAct * synapseStrength * 2.0;
    }
  }

  // Neuron body glow
  let neuronGlow = smoothstep(0.02, 0.0, distToNeuron) * activation;

  // Color from activation level and neuron ID
  let neuronHash = hash12(neuronId * 0.1 + 100.0);
  let actColor = palette(
    fract(activation * 0.2 + neuronHash + time * 0.1),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(1.0, 1.0, 0.5),
    vec3<f32>(0.8, 0.9, 0.3)
  );

  // Base image visible through network
  let baseImage = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Combine: neurons and synapses overlaid on image
  var finalColor = baseImage * 0.6;
  finalColor = finalColor + actColor * neuronGlow;
  finalColor = finalColor + vec3<f32>(0.4, 0.8, 1.0) * connectionGlow;

  // Global network pulse
  let globalPulse = sin(time * pulseSpeed) * 0.5 + 0.5;
  finalColor = finalColor + actColor * globalPulse * activation * 0.1;

  // Alpha = neuron activation level
  let alpha = clamp(activation * 0.5 + connectionGlow, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
