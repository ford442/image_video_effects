// ---------------------------------------------------------------
//  Neural Network Dreamscaper – simulates neural network "dream state"
//  Cascading activations flow through artificial synapses, creating
//  surreal, ever-morphing landscapes that breathe with digital consciousness.
// ---------------------------------------------------------------
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var persistBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTexC:    texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------------------

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_params: vec4<f32>,       // x=neuronCount, y=synapseGlow, z=morphSpeed, w=feedbackStr
  zoom_config: vec4<f32>,       // x=distortion, y=activationStr, z=colorSpeed, w=depthInf
  ripples:     array<vec4<f32>, 50>,
};

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
//  Main compute shader
// ---------------------------------------------------------------
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dimsI = textureDimensions(videoTex);
  let dims = vec2<f32>(f32(dimsI.x), f32(dimsI.y));
  if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) {
    return;
  }
  
  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  
  // -----------------------------------------------------------------
  //  Parameters from uniforms
  // -----------------------------------------------------------------
  let neuronScale = u.zoom_params.x * 3.0 + 3.0;      // Number of neuron centers
  let synapseGlow = u.zoom_params.y;                   // Synapse brightness
  let morphSpeed = u.zoom_params.z * 0.5;              // Animation speed
  let feedbackStr = u.zoom_params.w * 0.1;             // Temporal feedback
  let distortionAmt = u.zoom_config.x * 0.05;          // UV distortion
  let activationStr = u.zoom_config.y * 3.0 + 1.0;     // Activation intensity
  let colorSpeed = u.zoom_config.z * 0.2;              // Color cycling speed
  let depthInf = u.zoom_config.w;                       // Depth influence
  
  // Read depth
  let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
  
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
  
  // Apply depth influence (closer = stronger activation)
  let depthBoost = 1.0 + (1.0 - depth) * depthInf;
  
  // -----------------------------------------------------------------
  //  Create synaptic connections (flowing pulses between neurons)
  // -----------------------------------------------------------------
  let synapse1 = synapticFlow(uv, center1, center2, time, 0.0);
  let synapse2 = synapticFlow(uv, center2, center3, time, 1.0);
  let synapse3 = synapticFlow(uv, center3, center1, time, 2.0);
  
  // -----------------------------------------------------------------
  //  Add neural noise for organic feel
  // -----------------------------------------------------------------
  let noise = neuralNoise(uv * 10.0 + vec2<f32>(time * 0.1, time * 0.05)) * 0.1;
  
  // -----------------------------------------------------------------
  //  Combine all neural activities
  // -----------------------------------------------------------------
  let totalActivation = (act1 + act2 + act3 + synapse1 + synapse2 + synapse3 + noise) * depthBoost;
  
  // Apply non-linear activation function
  let processedActivation = tanh(totalActivation * activationStr);
  
  // -----------------------------------------------------------------
  //  Create color based on activations (each neuron has distinct hue)
  // -----------------------------------------------------------------
  let color1 = neuralColor(act1, time * colorSpeed);
  let color2 = neuralColor(act2, time * colorSpeed + 0.33);
  let color3 = neuralColor(act3, time * colorSpeed + 0.66);
  
  // Combine colors with activation weights
  let totalAct = max(0.001, act1 + act2 + act3);
  let totalColor = (color1 * act1 + color2 * act2 + color3 * act3) / totalAct;
  
  // -----------------------------------------------------------------
  //  Sample input texture with neural distortion
  // -----------------------------------------------------------------
  let distortion = vec2<f32>(
    sin(uv.y * 20.0 + time) * distortionAmt,
    cos(uv.x * 15.0 + time * 1.2) * distortionAmt
  );
  
  let distortedUV = clamp(uv + distortion * processedActivation, vec2<f32>(0.0), vec2<f32>(1.0));
  let inputSample = textureSampleLevel(videoTex, videoSampler, distortedUV, 0.0).rgb;
  
  // -----------------------------------------------------------------
  //  Sample previous frame for temporal coherence
  // -----------------------------------------------------------------
  let prevSample = textureSampleLevel(dataTexC, videoSampler, uv, 0.0).rgb;
  
  // Create feedback with neural persistence
  let feedback = mix(prevSample, totalColor, feedbackStr);
  
  // Store for next frame
  textureStore(persistBuf, gid.xy, vec4<f32>(feedback, 1.0));
  
  // -----------------------------------------------------------------
  //  Morph between input and neural visualization
  // -----------------------------------------------------------------
  let morph = sin(time * 0.3 * morphSpeed) * 0.5 + 0.5;
  var finalColor = mix(inputSample, feedback, morph);
  finalColor = finalColor * (1.0 + processedActivation * 0.5);
  
  // -----------------------------------------------------------------
  //  Add glowing synapses
  // -----------------------------------------------------------------
  let synapseTotal = (synapse1 + synapse2 + synapse3) * synapseGlow * 2.0;
  let synapseColor = vec3<f32>(0.8, 0.6, 1.0) * synapseTotal;
  finalColor = finalColor + synapseColor;
  
  // -----------------------------------------------------------------
  //  Apply temporal evolution (breathing effect)
  // -----------------------------------------------------------------
  let evolution = sin(time * 2.0 + uv.x * 5.0) * cos(time * 1.7 + uv.y * 3.0) * 0.05;
  finalColor = finalColor * (1.0 + evolution);
  
  // Clamp for safety
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(2.0));
  
  // -----------------------------------------------------------------
  //  Output
  // -----------------------------------------------------------------
  textureStore(outTex, gid.xy, vec4<f32>(finalColor, 1.0));
  textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
