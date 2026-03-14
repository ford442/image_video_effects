// ═════════════════════════════════════════════════════════════════════════════
//  Spectrogram Displacement - Time-Frequency Analysis with FFT-inspired bins
//  Category: distortion
//  Features: audio-reactive, time-scrolling, frequency-domain visualization
// ═════════════════════════════════════════════════════════════════════════════
//
//  SCIENTIFIC CONCEPT:
//  Spectrograms visualize audio in time-frequency domain:
//  - X axis: Time (scrolling)
//  - Y axis: Frequency (log scale, perceptual)
//  - Color: Magnitude/Intensity
//  
//  FFT (Fast Fourier Transform) converts time-domain signal to frequency bins.
//  This shader simulates real-time frequency analysis with synthetic audio data
//  and applies the spectrogram as a displacement map to the input image.
//
//  PARAMETERS (zoom_params):
//  - x: Frequency range multiplier (0.5 - 2.0)
//  - y: Time window/scrolling speed (0.1 - 2.0)
//  - z: Magnification/boost (0.5 - 3.0)
//  - w: Color scheme selector (0=heatmap, 1=neon, 2=ocean, 3=fire)
//
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
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // audio texture input
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=FreqRange, y=TimeWindow, z=Magnification, w=ColorScheme
  ripples: array<vec4<f32>, 50>,
};

// ═════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═════════════════════════════════════════════════════════════════════════════

const PI: f32 = 3.14159265359;
const TWO_PI: f32 = 6.28318530718;
const NUM_BINS: u32 = 128u;          // Number of frequency bins
const MAX_HARMONICS: i32 = 8;        // Max harmonics for synthesis

// ═════════════════════════════════════════════════════════════════════════════
// UTILITY FUNCTIONS
// ═════════════════════════════════════════════════════════════════════════════

// Hash function for pseudo-random values
fn hash(n: f32) -> f32 {
  return fract(sin(n) * 43758.5453123);
}

// 2D hash for spatial randomness
fn hash2(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Smooth noise function
fn noise(p: f32) -> f32 {
  let fl = floor(p);
  let fc = fract(p);
  return mix(hash(fl), hash(fl + 1.0), fc * fc * (3.0 - 2.0 * fc));
}

// 2D value noise
fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  
  return mix(
    mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// FREQUENCY UTILITIES
// ═════════════════════════════════════════════════════════════════════════════

// Convert linear frequency to logarithmic (perceptual) scale
// Maps 0-1 to 20Hz-20kHz range on log scale
fn linearToLogFreq(t: f32) -> f32 {
  // Human hearing range: 20Hz - 20000Hz
  let minFreq = 20.0;
  let maxFreq = 20000.0;
  return minFreq * pow(maxFreq / minFreq, t);
}

// Get normalized frequency from Y coordinate (log scale)
fn getFrequency(y: f32, freqRange: f32) -> f32 {
  // Invert Y so low frequencies at bottom
  let invY = 1.0 - y;
  // Apply frequency range multiplier
  return linearToLogFreq(invY * freqRange);
}

// ═════════════════════════════════════════════════════════════════════════════
// SYNTHETIC AUDIO GENERATION
// ═════════════════════════════════════════════════════════════════════════════

// Generate synthetic audio signal with multiple frequency components
// Simulates what an FFT would analyze in real audio
fn generateAudioSignal(time: f32, frequency: f32) -> f32 {
  var signal: f32 = 0.0;
  var amplitude: f32 = 0.0;
  
  // Base frequency components with harmonic series
  let baseFreq1 = 110.0;  // A2
  let baseFreq2 = 220.0;  // A3
  let baseFreq3 = 440.0;  // A4
  
  // Time-varying modulation for animation
  let mod1 = sin(time * 0.5) * 0.5 + 0.5;
  let mod2 = sin(time * 0.7 + 1.0) * 0.5 + 0.5;
  let mod3 = sin(time * 0.3 + 2.0) * 0.5 + 0.5;
  
  // Beat pattern for rhythmic variation
  let beat = sin(time * 8.0) * 0.5 + 0.5;
  
  // Sum of harmonics simulating DFT/FFT analysis
  for (var h: i32 = 1; h <= MAX_HARMONICS; h = h + 1) {
    let harmonic = f32(h);
    let harmonicDecay = 1.0 / harmonic;
    
    // First instrument (bass)
    if (frequency < 300.0) {
      let ratio = frequency / (baseFreq1 * harmonic);
      let proximity = exp(-ratio * ratio * 100.0);
      amplitude = amplitude + proximity * harmonicDecay * mod1 * (0.3 + 0.7 * beat);
    }
    
    // Second instrument (mid)
    if (frequency > 200.0 && frequency < 2000.0) {
      let ratio = frequency / (baseFreq2 * harmonic);
      let proximity = exp(-ratio * ratio * 200.0);
      amplitude = amplitude + proximity * harmonicDecay * mod2 * 0.6;
    }
    
    // Third instrument (high)
    if (frequency > 1000.0) {
      let ratio = frequency / (baseFreq3 * harmonic);
      let proximity = exp(-ratio * ratio * 400.0);
      amplitude = amplitude + proximity * harmonicDecay * mod3 * 0.4;
    }
  }
  
  // Add noise floor for realistic spectrum
  let noiseFloor = 0.02 * noise(time * 100.0 + frequency * 0.01);
  
  // Add some random peaks for transients
  let transient = 0.0;
  if (hash(time * 10.0) > 0.95) {
    amplitude = amplitude + 0.3 * hash(frequency + time);
  }
  
  return clamp(amplitude + noiseFloor, 0.0, 1.0);
}

// DFT-inspired frequency bin calculation
// Simulates frequency bin magnitude using sum of sines approach
fn calculateFrequencyBin(binIndex: u32, numBins: u32, time: f32) -> f32 {
  let binF = f32(binIndex);
  let numBinsF = f32(numBins);
  
  // Normalize bin to 0-1 range
  let normalizedBin = binF / numBinsF;
  
  // Get frequency for this bin (log scale)
  let frequency = getFrequency(normalizedBin, 1.0);
  
  // Generate magnitude for this frequency bin
  var magnitude = generateAudioSignal(time, frequency);
  
  // Apply perceptual weighting (A-weighting approximation)
  // Human ear is most sensitive around 2-5kHz
  let aWeight = 1.0 + 0.5 * exp(-pow((frequency - 4000.0) / 2000.0, 2.0));
  magnitude = magnitude * aWeight;
  
  // Add some frequency-dependent modulation for animation
  let timeMod = sin(time * 2.0 + normalizedBin * 10.0) * 0.1;
  magnitude = magnitude + timeMod * magnitude;
  
  return clamp(magnitude, 0.0, 1.0);
}

// ═════════════════════════════════════════════════════════════════════════════
// SPECTROGRAM RENDERING
// ═════════════════════════════════════════════════════════════════════════════

// Color scheme functions
fn heatmapColor(t: f32) -> vec3<f32> {
  // Classic spectrogram: black -> blue -> green -> yellow -> red -> white
  let c1 = vec3<f32>(0.0, 0.0, 0.0);      // black
  let c2 = vec3<f32>(0.0, 0.0, 0.5);      // dark blue
  let c3 = vec3<f32>(0.0, 1.0, 0.0);      // green
  let c4 = vec3<f32>(1.0, 1.0, 0.0);      // yellow
  let c5 = vec3<f32>(1.0, 0.0, 0.0);      // red
  let c6 = vec3<f32>(1.0, 1.0, 1.0);      // white
  
  if (t < 0.16) {
    return mix(c1, c2, t / 0.16);
  } else if (t < 0.33) {
    return mix(c2, c3, (t - 0.16) / 0.17);
  } else if (t < 0.5) {
    return mix(c3, c4, (t - 0.33) / 0.17);
  } else if (t < 0.66) {
    return mix(c4, c5, (t - 0.5) / 0.16);
  } else if (t < 0.83) {
    return mix(c5, c6, (t - 0.66) / 0.17);
  } else {
    return c6;
  }
}

fn neonColor(t: f32) -> vec3<f32> {
  // Cyberpunk neon: cyan -> magenta -> purple
  let c1 = vec3<f32>(0.0, 1.0, 1.0);      // cyan
  let c2 = vec3<f32>(1.0, 0.0, 1.0);      // magenta
  let c3 = vec3<f32>(0.6, 0.0, 1.0);      // purple
  
  if (t < 0.5) {
    return mix(c1, c2, t * 2.0);
  } else {
    return mix(c2, c3, (t - 0.5) * 2.0);
  }
}

fn oceanColor(t: f32) -> vec3<f32> {
  // Ocean depths: deep blue -> cyan -> teal
  let c1 = vec3<f32>(0.0, 0.1, 0.3);      // deep blue
  let c2 = vec3<f32>(0.0, 0.4, 0.6);      // medium blue
  let c3 = vec3<f32>(0.0, 0.8, 0.8);      // cyan
  let c4 = vec3<f32>(0.2, 1.0, 0.8);      // bright teal
  
  if (t < 0.33) {
    return mix(c1, c2, t / 0.33);
  } else if (t < 0.66) {
    return mix(c2, c3, (t - 0.33) / 0.33);
  } else {
    return mix(c3, c4, (t - 0.66) / 0.34);
  }
}

fn fireColor(t: f32) -> vec3<f32> {
  // Fire: black -> red -> orange -> yellow -> white
  let c1 = vec3<f32>(0.0, 0.0, 0.0);      // black
  let c2 = vec3<f32>(0.5, 0.0, 0.0);      // dark red
  let c3 = vec3<f32>(1.0, 0.0, 0.0);      // red
  let c4 = vec3<f32>(1.0, 0.5, 0.0);      // orange
  let c5 = vec3<f32>(1.0, 1.0, 0.0);      // yellow
  let c6 = vec3<f32>(1.0, 1.0, 1.0);      // white
  
  if (t < 0.16) {
    return mix(c1, c2, t / 0.16);
  } else if (t < 0.33) {
    return mix(c2, c3, (t - 0.16) / 0.17);
  } else if (t < 0.5) {
    return mix(c3, c4, (t - 0.33) / 0.17);
  } else if (t < 0.66) {
    return mix(c4, c5, (t - 0.5) / 0.16);
  } else if (t < 0.83) {
    return mix(c5, c6, (t - 0.66) / 0.17);
  } else {
    return c6;
  }
}

// Select color based on scheme
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

// ═════════════════════════════════════════════════════════════════════════════
// MAIN SHADER
// ═════════════════════════════════════════════════════════════════════════════

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<u32>(gid.xy);
  let dim = textureDimensions(readTexture);
  
  // Early out if outside texture bounds
  if (coord.x >= dim.x || coord.y >= dim.y) {
    return;
  }
  
  // Normalized UV coordinates
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
  
  // Time and parameters
  let time = u.config.x;
  let frameCount = u.config.y;
  let freqRange = u.zoom_params.x;        // Frequency range multiplier
  let timeWindow = u.zoom_params.y;       // Time window / scrolling speed
  let magnification = u.zoom_params.z;    // Magnification/boost
  let colorScheme = u.zoom_params.w;      // Color scheme selector
  
  // Default parameter values if not set
  let effectiveFreqRange = select(freqRange, 1.0, freqRange < 0.01);
  let effectiveTimeWindow = select(timeWindow, 0.5, timeWindow < 0.01);
  let effectiveMag = select(magnification, 1.0, magnification < 0.01);
  
  // ═══════════════════════════════════════════════════════════════════════════
  // SPECTROGRAM CALCULATION
  // ═══════════════════════════════════════════════════════════════════════════
  
  // Time-scrolling: offset X based on time for scrolling effect
  let scrollOffset = time * effectiveTimeWindow;
  let scrolledX = fract(uv.x + scrollOffset);
  
  // Calculate frequency for this Y position (log scale)
  let frequency = getFrequency(uv.y, effectiveFreqRange);
  
  // Calculate magnitude using DFT-inspired frequency bin
  // We use the scrolled position to create time-varying spectrum
  let timeSample = time + scrolledX * 2.0;
  var magnitude = generateAudioSignal(timeSample, frequency);
  
  // Apply frequency bin calculation for more realistic FFT look
  let binIndex = u32(uv.y * f32(NUM_BINS)) % NUM_BINS;
  let binMagnitude = calculateFrequencyBin(binIndex, NUM_BINS, timeSample);
  
  // Combine magnitudes
  magnitude = mix(magnitude, binMagnitude, 0.7);
  
  // Apply magnification/boost
  magnitude = pow(magnitude, 0.5) * effectiveMag;
  magnitude = clamp(magnitude, 0.0, 1.0);
  
  // ═══════════════════════════════════════════════════════════════════════════
  // MOUSE INTERACTION - Focus frequency bands
  // ═══════════════════════════════════════════════════════════════════════════
  
  let mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let isMouseDown = u.zoom_config.w > 0.5;
  
  if (mousePos.y > 0.0 && mousePos.y < 1.0) {
    let mouseFreq = getFrequency(mousePos.y, effectiveFreqRange);
    let freqDist = abs(frequency - mouseFreq) / mouseFreq;
    
    // Highlight frequencies near mouse
    if (freqDist < 0.3) {
      let highlight = 1.0 + (0.3 - freqDist) / 0.3 * 1.5;
      magnitude = magnitude * highlight;
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // RIPPLE INTERACTION - Audio-reactive smears
  // ═══════════════════════════════════════════════════════════════════════════
  
  for (var i: i32 = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 3.0) {
        let distToRipple = distance(uv, ripple.xy);
        if (distToRipple < 0.15) {
          // Ripple affects local frequency response
          let rippleInfluence = (1.0 - rippleAge / 3.0) * (1.0 - distToRipple / 0.15);
          magnitude = magnitude * (1.0 + rippleInfluence * 2.0);
        }
      }
    }
  }
  
  // Final magnitude clamp
  magnitude = clamp(magnitude, 0.0, 1.0);
  
  // ═══════════════════════════════════════════════════════════════════════════
  // COLOR MAPPING
  // ═══════════════════════════════════════════════════════════════════════════
  
  let spectroColor = getColor(magnitude, colorScheme);
  
  // ═══════════════════════════════════════════════════════════════════════════
  // DISPLACEMENT EFFECT
  // ═══════════════════════════════════════════════════════════════════════════
  
  // Sample original texture
  let src = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0);
  
  // Calculate displacement based on spectrogram magnitude
  // Higher frequencies (top of screen) create different displacement
  let freqFactor = 1.0 - uv.y;  // 1 at bottom (low freq), 0 at top (high freq)
  
  // Displacement amount varies by frequency
  let displacementX = magnitude * (src.r - src.b) * 50.0 * effectiveMag;
  let displacementY = magnitude * (src.g - 0.5) * 30.0 * effectiveMag * freqFactor;
  
  // Time-varying displacement for "waving" effect
  let waveDisp = sin(uv.y * 20.0 + time * 3.0) * magnitude * 10.0;
  
  // Calculate displaced coordinates
  var displacedX = i32(coord.x) + i32(displacementX + waveDisp);
  var displacedY = i32(coord.y) + i32(displacementY);
  
  // Wrap around (toroidal mapping)
  displacedX = (displacedX + i32(dim.x)) % i32(dim.x);
  displacedY = (displacedY + i32(dim.y)) % i32(dim.y);
  
  // Sample displaced texture
  let displacedColor = textureLoad(readTexture, vec2<i32>(displacedX, displacedY), 0);
  
  // ═══════════════════════════════════════════════════════════════════════════
  // COMPOSITING
  // ═══════════════════════════════════════════════════════════════════════════
  
  // Blend between displaced image and spectrogram visualization
  // Amount of displacement vs raw spectrogram based on magnitude
  let blendFactor = magnitude * 0.3;  // 30% spectrogram overlay
  
  // Create final color: displaced image with spectrogram tint
  var finalColor = displacedColor.rgb;
  
  // Add spectrogram color as overlay/emission
  finalColor = finalColor + spectroColor * magnitude * 0.5 * effectiveMag;
  
  // Add frequency-based color grading
  let lowFreqBoost = select(1.0 + magnitude * 0.2, 1.0, uv.y > 0.7);
  let highFreqBoost = select(1.0 + magnitude * 0.1, 1.0, uv.y < 0.3);
  finalColor = finalColor * vec3<f32>(lowFreqBoost, 1.0, highFreqBoost);
  
  // Vignette effect based on displacement
  let vignette = 1.0 - magnitude * 0.3;
  finalColor = finalColor * vignette;
  
  // Clamp final output
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));
  
  // ═══════════════════════════════════════════════════════════════════════════
  // OUTPUT
  // ═══════════════════════════════════════════════════════════════════════════
  
  // Write color output
  textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(finalColor, 1.0));
  
  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(depth, 0.0, 0.0, 0.0));
  
  // Store spectrogram data in dataTextureA for potential multi-pass use
  textureStore(dataTextureA, vec2<i32>(i32(coord.x), i32(coord.y)), vec4<f32>(spectroColor * magnitude, magnitude));
}
