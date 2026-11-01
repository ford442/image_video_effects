// ---------------------------------------------------------------
//  Neural Network Dreamscaper – simulates neural network "dream state"
//  Cascading activations flow through artificial synapses, creating
//  surreal, ever-morphing landscapes that breathe with digital consciousness.
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-31
//  Ideas: soft inverse-square soma nuclei (F); golden-angle dendritic spines sized by Neuron Count (E); additive domain twist swirling the photo around each neuron (E)
//  A packing: rgb = neuron colour feedback history, a = tanh activation (display is ACES in writeTexture)
// ---------------------------------------------------------------
#include "_prelude.wgsl"
// zoom_params: x=Neuron Count, y=Synapse Glow, z=Morph Speed, w=Feedback Strength
// Mouse: held cursor stimulates an extra neuron; clicks fire action-potential fronts.

// ---------------------------------------------------------------
//  Neural activation functions
// ---------------------------------------------------------------
fn relu(x: f32) -> f32 {
  return max(0.0, x);
}

fn sigmoid(x: f32) -> f32 {
  return 1.0 / (1.0 + exp(-x));
}

// Use built-in tanh directly

// ---------------------------------------------------------------
//  Generate pseudo-random values for neural noise
// ---------------------------------------------------------------
fn neuralNoise(seed: vec2<f32>) -> f32 {
  return fract(sin(dot(seed, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3))));
  return fract(n * 43758.5453);
}

// ---------------------------------------------------------------
//  Simulate neural activation spreading (Gaussian blob)
// ---------------------------------------------------------------
fn neuralActivation(uv: vec2<f32>, center: vec2<f32>, strength: f32, radius: f32) -> f32 {
  let dist = length(uv - center);
  let activation = exp(-dist * dist / (2.0 * radius * radius));
  return strength * activation;
}

// ---------------------------------------------------------------
//  Create synaptic connections visualization (pulsing line)
// ---------------------------------------------------------------
fn synapticFlow(uv: vec2<f32>, frm: vec2<f32>, to: vec2<f32>, time: f32, timeOffset: f32) -> f32 {
  let direction = to - frm;
  let lengthDir = length(direction);
  if (lengthDir < 0.001) {
    return 0.0;
  }
  
  let normDir = direction / lengthDir;
  let toUV = uv - frm;
  let projection = dot(toUV, normDir);
  
  if (projection < 0.0 || projection > lengthDir) {
    return 0.0;
  }
  
  let distanceFromLine = length(toUV - normDir * projection);
  let pulse = sin(projection * 20.0 - time * 5.0 - timeOffset) * 0.5 + 0.5;
  return exp(-distanceFromLine * 30.0) * pulse * 0.5;
}

// ---------------------------------------------------------------
//  Color mapping for neural activations (rainbow cycling)
// ---------------------------------------------------------------
fn neuralColor(activation: f32, hueShift: f32) -> vec3<f32> {
  let t = activation * 0.5 + hueShift;
  let r = sin(t * 6.283 + 0.0) * 0.5 + 0.5;
  let g = sin(t * 6.283 + 2.094) * 0.5 + 0.5;
  let b = sin(t * 6.283 + 4.188) * 0.5 + 0.5;
  return vec3<f32>(r, g, b) * activation;
}

// ---------------------------------------------------------------
//  Idea 1: soma nucleus – softened inverse-square core (no singularity)
// ---------------------------------------------------------------
fn somaCore(uv: vec2<f32>, center: vec2<f32>, r0: f32) -> f32 {
  let d = (uv - center) * vec2<f32>(u.config.z / max(u.config.w, 1.0), 1.0);
  return (r0 * r0) / (dot(d, d) + r0 * r0);
}

// ---------------------------------------------------------------
//  Idea 2: dendritic spines on a golden-angle spiral around a neuron.
//  Each bouton pulses with a phase that travels outward along the arbor.
// ---------------------------------------------------------------
fn dendriticSpines(uv: vec2<f32>, center: vec2<f32>, count: i32, spin: f32, time: f32, phase: f32) -> f32 {
  let aspect = u.config.z / max(u.config.w, 1.0);
  let rel = (uv - center) * vec2<f32>(aspect, 1.0);
  var acc = 0.0;
  if (dot(rel, rel) < 0.045) {
    for (var k = 0; k < 12; k = k + 1) {
      let on = select(0.0, 1.0, k < count);
      let a = f32(k) * 2.39996323 + spin;
      let rr = 0.045 * sqrt(f32(k) + 0.5);
      let pos = vec2<f32>(cos(a), sin(a)) * rr;
      let d = length(rel - pos);
      let pulse = 0.5 + 0.5 * sin(time * 3.0 - f32(k) * 0.9 + phase);
      acc = acc + on * exp(-d * d * 1800.0) * (0.3 + 0.7 * pulse);
    }
  }
  return acc;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ---------------------------------------------------------------
//  Main compute shader
// ---------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }
  let coord = vec2<i32>(gid.xy);

  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let aspect = dims.x / dims.y;

  // -----------------------------------------------------------------
  //  Parameters (JSON order: Neuron Count / Synapse Glow / Morph Speed / Feedback)
  //  distortion / activation / colorSpeed / depthInf have no slider; pinned to
  //  the values HEAD produced at the 0.5 slider default.
  // -----------------------------------------------------------------
  let neuronCount = u.zoom_params.x;
  let synapseGlow = u.zoom_params.y * (1.0 + mids * 0.4);
  let morphSpeed = u.zoom_params.z * 0.5;
  let feedbackStr = max(u.zoom_params.w * 0.1, 0.01);
  let distortionAmt = 0.025;
  let activationStr = 2.5 * (1.0 + bass * 0.3);
  let colorSpeed = 0.1;
  let depthInf = 0.5;
  let spineCount = 4 + i32(neuronCount * 8.0 + 0.5);

  let mouse = u.zoom_config.yz;
  let held = step(0.5, u.zoom_config.w);

  // Read depth (exact load; sampler would be filtering on r32float)
  let depth = textureLoad(readDepthTexture, coord, 0).r;

  // -----------------------------------------------------------------
  //  Create dynamic neural centers (3 main neurons)
  // -----------------------------------------------------------------
  let center1 = vec2<f32>(
    0.5 + sin(time * 0.2 * morphSpeed) * 0.3,
    0.5 + cos(time * 0.3 * morphSpeed) * 0.3
  );

  let center2 = vec2<f32>(
    0.5 + cos(time * 0.15 * morphSpeed) * 0.4,
    0.5 + sin(time * 0.25 * morphSpeed) * 0.4
  );

  let center3 = vec2<f32>(
    0.5 + sin(time * 0.1 * morphSpeed) * 0.2,
    0.5 + cos(time * 0.2 * morphSpeed) * 0.2
  );

  // -----------------------------------------------------------------
  //  Calculate neural activations (Gaussian blobs)
  // -----------------------------------------------------------------
  let act1 = neuralActivation(uv, center1, 1.0, 0.3 + sin(time * 0.5) * 0.1);
  let act2 = neuralActivation(uv, center2, 0.8, 0.25 + cos(time * 0.4) * 0.05);
  let act3 = neuralActivation(uv, center3, 0.6, 0.2 + sin(time * 0.3) * 0.05);

  // Held cursor stimulates a fourth neuron (additive; zero when not held)
  let actM = neuralActivation(uv, mouse, 0.9 * held, 0.12);

  // Idea 1: soma nuclei (soft inverse-square)
  let r0 = 0.03 * (1.0 + bass * 0.5);
  let core1 = somaCore(uv, center1, r0);
  let core2 = somaCore(uv, center2, r0) * 0.8;
  let core3 = somaCore(uv, center3, r0) * 0.6;
  let coreTotal = core1 + core2 + core3 + somaCore(uv, mouse, r0) * held;

  // Idea 2: dendritic spines (golden-angle), count from Neuron Count
  let spin = time * morphSpeed * 0.5;
  let spines = dendriticSpines(uv, center1, spineCount, spin, time, 0.0)
             + dendriticSpines(uv, center2, spineCount, -spin, time, 2.1)
             + dendriticSpines(uv, center3, spineCount, spin, time, 4.2);

  // Apply depth influence (closer = stronger activation)
  let depthBoost = 1.0 + (1.0 - depth) * depthInf;

  // -----------------------------------------------------------------
  //  Create synaptic connections (flowing pulses between neurons)
  // -----------------------------------------------------------------
  let synapse1 = synapticFlow(uv, center1, center2, time, 0.0);
  let synapse2 = synapticFlow(uv, center2, center3, time, 1.0);
  let synapse3 = synapticFlow(uv, center3, center1, time, 2.0);

  // -----------------------------------------------------------------
  //  Click = action potential: an expanding front that excites the net
  // -----------------------------------------------------------------
  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = max(time - event.z, 0.0);
    clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.38) * 58.0);
  }

  // -----------------------------------------------------------------
  //  Add neural noise for organic feel
  // -----------------------------------------------------------------
  let noise = neuralNoise(uv * 10.0 + vec2<f32>(time * 0.1, time * 0.05)) * 0.1;

  // -----------------------------------------------------------------
  //  Combine all neural activities
  // -----------------------------------------------------------------
  let totalActivation = (act1 + act2 + act3 + actM + synapse1 + synapse2 + synapse3 + noise
                         + coreTotal * 0.35 + spines * 0.25 + clickFront * 0.4) * depthBoost;

  // Apply non-linear activation function
  let processedActivation = tanh(totalActivation * activationStr);

  // -----------------------------------------------------------------
  //  Create color based on activations (each neuron has distinct hue)
  // -----------------------------------------------------------------
  let color1 = neuralColor(act1, time * colorSpeed);
  let color2 = neuralColor(act2, time * colorSpeed + 0.33);
  let color3 = neuralColor(act3, time * colorSpeed + 0.66);
  let colorM = neuralColor(actM, time * colorSpeed + 0.5);

  // Combine colors with activation weights
  let totalAct = max(0.001, act1 + act2 + act3 + actM);
  let totalColor = (color1 * act1 + color2 * act2 + color3 * act3 + colorM * actM) / totalAct;

  // -----------------------------------------------------------------
  //  Sample input texture with neural distortion
  //  Idea 3: additive domain twist – the photo is swirled around each neuron
  //  by that neuron's own activation (alternating hand per neuron).
  // -----------------------------------------------------------------
  let distortion = vec2<f32>(
    sin(uv.y * 20.0 + time) * distortionAmt,
    cos(uv.x * 15.0 + time * 1.2) * distortionAmt
  );
  let d1 = uv - center1;
  let d2 = uv - center2;
  let d3 = uv - center3;
  let twist = vec2<f32>(-d1.y, d1.x) * act1 - vec2<f32>(-d2.y, d2.x) * act2 * 0.8
            + vec2<f32>(-d3.y, d3.x) * act3 * 0.6;
  let twistedUV = uv + twist * 0.3 * (1.0 + bass * 0.4);

  let distortedUV = clamp(twistedUV + distortion * processedActivation, vec2<f32>(0.0), vec2<f32>(1.0));
  let inputSample = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0).rgb;

  // -----------------------------------------------------------------
  //  Sample previous frame for temporal coherence (exact load)
  // -----------------------------------------------------------------
  let prevSample = max(textureLoad(dataTextureC, coord, 0).rgb, vec3<f32>(0.0));

  // Create feedback with neural persistence
  let feedback = mix(prevSample, totalColor, feedbackStr);

  // Store for next frame
  textureStore(dataTextureA, coord, vec4<f32>(feedback, processedActivation));

  // -----------------------------------------------------------------
  //  Morph between input and neural visualization
  // -----------------------------------------------------------------
  let morph = sin(time * 0.3 * morphSpeed) * 0.5 + 0.5;
  var finalColor = mix(inputSample, feedback, morph);
  finalColor = finalColor * (1.0 + processedActivation * 0.5);

  // -----------------------------------------------------------------
  //  Add glowing synapses (+ hot warm soma nuclei and spine boutons)
  // -----------------------------------------------------------------
  let synapseTotal = (synapse1 + synapse2 + synapse3) * synapseGlow * 2.0;
  let synapseColor = vec3<f32>(0.8, 0.6, 1.0) * synapseTotal;
  finalColor = finalColor + synapseColor;
  finalColor = finalColor + vec3<f32>(1.0, 0.85, 0.7) * coreTotal * 0.22 * (0.5 + synapseGlow);
  finalColor = finalColor + neuralColor(1.0, time * colorSpeed + 0.2) * spines * 0.35 * (0.5 + synapseGlow);
  finalColor = finalColor + vec3<f32>(0.6, 0.9, 1.0) * clickFront * (0.25 + treble * 0.3);

  // -----------------------------------------------------------------
  //  Apply temporal evolution (breathing effect)
  // -----------------------------------------------------------------
  let evolution = sin(time * 2.0 + uv.x * 5.0) * cos(time * 1.7 + uv.y * 3.0) * 0.05;
  finalColor = finalColor * (1.0 + evolution);

  // Clamp for safety, then tone-map the display
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(2.0));
  let displayRGB = acesToneMap(finalColor);
  let outAlpha = clamp(0.35 + processedActivation * 0.65, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(displayRGB, outAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
