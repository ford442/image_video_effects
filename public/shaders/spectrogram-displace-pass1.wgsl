// ═════════════════════════════════════════════════════════════════════════════
//  Spectrogram Displace – Pass 1: Spectrogram Field Generation
//  Category: image
//  Features: multi-pass-1, frequency analysis, magnitude field, color mapping
//  Outputs: dataTextureA (spectroColor*mag, mag, displacementX, displacementY)
// ═════════════════════════════════════════════════════════════════════════════

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

const PI: f32 = 3.14159265359;
const NUM_BINS: u32 = 128u;
const MAX_HARMONICS: i32 = 8;

fn hash(n: f32) -> f32 {
  return fract(sin(n) * 43758.5453123);
}

fn hash2(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: f32) -> f32 {
  let fl = floor(p);
  let fc = fract(p);
  return mix(hash(fl), hash(fl + 1.0), fc * fc * (3.0 - 2.0 * fc));
}

fn linearToLogFreq(t: f32) -> f32 {
  let minFreq = 20.0;
  let maxFreq = 20000.0;
  return minFreq * pow(maxFreq / minFreq, t);
}

fn getFrequency(y: f32, freqRange: f32) -> f32 {
  let invY = 1.0 - y;
  return linearToLogFreq(invY * freqRange);
}

fn generateAudioSignal(time: f32, frequency: f32) -> f32 {
  var amplitude: f32 = 0.0;
  let baseFreq1 = 110.0;
  let baseFreq2 = 220.0;
  let baseFreq3 = 440.0;
  let mod1 = sin(time * 0.5) * 0.5 + 0.5;
  let mod2 = sin(time * 0.7 + 1.0) * 0.5 + 0.5;
  let mod3 = sin(time * 0.3 + 2.0) * 0.5 + 0.5;
  let beat = sin(time * 8.0) * 0.5 + 0.5;

  for (var h: i32 = 1; h <= MAX_HARMONICS; h = h + 1) {
    let harmonic = f32(h);
    let harmonicDecay = 1.0 / harmonic;
    if (frequency < 300.0) {
      let ratio = frequency / (baseFreq1 * harmonic);
      let proximity = exp(-ratio * ratio * 100.0);
      amplitude = amplitude + proximity * harmonicDecay * mod1 * (0.3 + 0.7 * beat);
    }
    if (frequency > 200.0 && frequency < 2000.0) {
      let ratio = frequency / (baseFreq2 * harmonic);
      let proximity = exp(-ratio * ratio * 200.0);
      amplitude = amplitude + proximity * harmonicDecay * mod2 * 0.6;
    }
    if (frequency > 1000.0) {
      let ratio = frequency / (baseFreq3 * harmonic);
      let proximity = exp(-ratio * ratio * 400.0);
      amplitude = amplitude + proximity * harmonicDecay * mod3 * 0.4;
    }
  }

  let noiseFloor = 0.02 * noise(time * 100.0 + frequency * 0.01);
  if (hash(time * 10.0) > 0.95) {
    amplitude = amplitude + 0.3 * hash(frequency + time);
  }
  return clamp(amplitude + noiseFloor, 0.0, 1.0);
}

fn calculateFrequencyBin(binIndex: u32, numBins: u32, time: f32) -> f32 {
  let normalizedBin = f32(binIndex) / f32(numBins);
  let frequency = getFrequency(normalizedBin, 1.0);
  var magnitude = generateAudioSignal(time, frequency);
  let aWeight = 1.0 + 0.5 * exp(-pow((frequency - 4000.0) / 2000.0, 2.0));
  magnitude = magnitude * aWeight;
  let timeMod = sin(time * 2.0 + normalizedBin * 10.0) * 0.1;
  magnitude = magnitude + timeMod * magnitude;
  return clamp(magnitude, 0.0, 1.0);
}

fn heatmapColor(t: f32) -> vec3<f32> {
  if (t < 0.16) { return mix(vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.0, 0.0, 0.5), t / 0.16); }
  else if (t < 0.33) { return mix(vec3<f32>(0.0, 0.0, 0.5), vec3<f32>(0.0, 1.0, 0.0), (t - 0.16) / 0.17); }
  else if (t < 0.5) { return mix(vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(1.0, 1.0, 0.0), (t - 0.33) / 0.17); }
  else if (t < 0.66) { return mix(vec3<f32>(1.0, 1.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), (t - 0.5) / 0.16); }
  else if (t < 0.83) { return mix(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(1.0, 1.0, 1.0), (t - 0.66) / 0.17); }
  else { return vec3<f32>(1.0, 1.0, 1.0); }
}

fn neonColor(t: f32) -> vec3<f32> {
  if (t < 0.5) { return mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), t * 2.0); }
  else { return mix(vec3<f32>(1.0, 0.0, 1.0), vec3<f32>(0.6, 0.0, 1.0), (t - 0.5) * 2.0); }
}

fn oceanColor(t: f32) -> vec3<f32> {
  if (t < 0.33) { return mix(vec3<f32>(0.0, 0.1, 0.3), vec3<f32>(0.0, 0.4, 0.6), t / 0.33); }
  else if (t < 0.66) { return mix(vec3<f32>(0.0, 0.4, 0.6), vec3<f32>(0.0, 0.8, 0.8), (t - 0.33) / 0.33); }
  else { return mix(vec3<f32>(0.0, 0.8, 0.8), vec3<f32>(0.2, 1.0, 0.8), (t - 0.66) / 0.34); }
}

fn fireColor(t: f32) -> vec3<f32> {
  if (t < 0.16) { return mix(vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(0.5, 0.0, 0.0), t / 0.16); }
  else if (t < 0.33) { return mix(vec3<f32>(0.5, 0.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), (t - 0.16) / 0.17); }
  else if (t < 0.5) { return mix(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(1.0, 0.5, 0.0), (t - 0.33) / 0.17); }
  else if (t < 0.66) { return mix(vec3<f32>(1.0, 0.5, 0.0), vec3<f32>(1.0, 1.0, 0.0), (t - 0.5) / 0.16); }
  else if (t < 0.83) { return mix(vec3<f32>(1.0, 1.0, 0.0), vec3<f32>(1.0, 1.0, 1.0), (t - 0.66) / 0.17); }
  else { return vec3<f32>(1.0, 1.0, 1.0); }
}

fn getColor(magnitude: f32, scheme: f32) -> vec3<f32> {
  let t = clamp(magnitude, 0.0, 1.0);
  let schemeIndex = u32(scheme * 3.0) % 4u;
  switch(schemeIndex) {
    case 0u: { return heatmapColor(t); }
    case 1u: { return neonColor(t); }
    case 2u: { return oceanColor(t); }
    case 3u: { return fireColor(t); }
    default: { return heatmapColor(t); }
  }
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<u32>(gid.xy);
  let dim = textureDimensions(readTexture);
  if (coord.x >= dim.x || coord.y >= dim.y) { return; }

  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
  let time = u.config.x;
  let freqRange = u.zoom_params.x;
  let timeWindow = u.zoom_params.y;
  let magnification = u.zoom_params.z;
  let colorScheme = u.zoom_params.w;

  let effectiveFreqRange = select(freqRange, 1.0, freqRange < 0.01);
  let effectiveTimeWindow = select(timeWindow, 0.5, timeWindow < 0.01);
  let effectiveMag = select(magnification, 1.0, magnification < 0.01);

  let scrollOffset = time * effectiveTimeWindow;
  let scrolledX = fract(uv.x + scrollOffset);
  let frequency = getFrequency(uv.y, effectiveFreqRange);
  let timeSample = time + scrolledX * 2.0;
  var magnitude = generateAudioSignal(timeSample, frequency);
  let binIndex = u32(uv.y * f32(NUM_BINS)) % NUM_BINS;
  let binMagnitude = calculateFrequencyBin(binIndex, NUM_BINS, timeSample);
  magnitude = mix(magnitude, binMagnitude, 0.7);
  magnitude = pow(magnitude, 0.5) * effectiveMag;

  let mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  if (mousePos.y > 0.0 && mousePos.y < 1.0) {
    let mouseFreq = getFrequency(mousePos.y, effectiveFreqRange);
    let freqDist = abs(frequency - mouseFreq) / mouseFreq;
    if (freqDist < 0.3) {
      let highlight = 1.0 + (0.3 - freqDist) / 0.3 * 1.5;
      magnitude = magnitude * highlight;
    }
  }

  for (var i: i32 = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 3.0) {
        let distToRipple = distance(uv, ripple.xy);
        if (distToRipple < 0.15) {
          let rippleInfluence = (1.0 - rippleAge / 3.0) * (1.0 - distToRipple / 0.15);
          magnitude = magnitude * (1.0 + rippleInfluence * 2.0);
        }
      }
    }
  }

  magnitude = clamp(magnitude, 0.0, 1.0);
  let spectroColor = getColor(magnitude, colorScheme);

  let src = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0);
  let freqFactor = 1.0 - uv.y;
  let displacementX = magnitude * (src.r - src.b) * 50.0 * effectiveMag;
  let displacementY = magnitude * (src.g - 0.5) * 30.0 * effectiveMag * freqFactor;
  let waveDisp = sin(uv.y * 20.0 + time * 3.0) * magnitude * 10.0;

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), inputColor);
  textureStore(dataTextureA, vec2<i32>(i32(coord.x), i32(coord.y)),
    vec4<f32>(spectroColor, magnitude));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
