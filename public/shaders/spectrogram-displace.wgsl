// ═══════════════════════════════════════════════════════════════════
//  Spectrogram Displace
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Created: 2026-04-15
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
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
    let baseFreq1 = 110.0;
    let baseFreq2 = 220.0;
    let baseFreq3 = 440.0;
    
    let mod1 = sin(time * 0.5) * 0.5 + 0.5;
    let mod2 = sin(time * 0.7 + 1.0) * 0.5 + 0.5;
    let mod3 = sin(time * 0.3 + 2.0) * 0.5 + 0.5;
    
    let beat = sin(time * 8.0) * 0.5 + 0.5;
    
    var amplitude: f32 = 0.0;
    
    for (var h: i32 = 1; h <= MAX_HARMONICS; h = h + 1) {
        let harmonic = f32(h);
        let harmonicDecay = 1.0 / harmonic;
        
        let isBass = step(frequency, 300.0);
        let ratio1 = frequency / (baseFreq1 * harmonic);
        let proximity1 = exp(-ratio1 * ratio1 * 100.0);
        let amp1 = proximity1 * harmonicDecay * mod1 * (0.3 + 0.7 * beat) * isBass;
        
        let isMid = step(200.0, frequency) * step(frequency, 2000.0);
        let ratio2 = frequency / (baseFreq2 * harmonic);
        let proximity2 = exp(-ratio2 * ratio2 * 200.0);
        let amp2 = proximity2 * harmonicDecay * mod2 * 0.6 * isMid;
        
        let isHigh = step(1000.0, frequency);
        let ratio3 = frequency / (baseFreq3 * harmonic);
        let proximity3 = exp(-ratio3 * ratio3 * 400.0);
        let amp3 = proximity3 * harmonicDecay * mod3 * 0.4 * isHigh;
        
        amplitude = amplitude + amp1 + amp2 + amp3;
    }
    
    let noiseFloor = 0.02 * noise(time * 100.0 + frequency * 0.01);
    let transient = 0.3 * hash(frequency + time) * step(0.95, hash(time * 10.0));
    
    return clamp(amplitude + noiseFloor + transient, 0.0, 1.0);
}

fn calculateFrequencyBin(binIndex: u32, numBins: u32, time: f32) -> f32 {
    let binF = f32(binIndex);
    let numBinsF = f32(numBins);
    let normalizedBin = binF / numBinsF;
    let frequency = getFrequency(normalizedBin, 1.0);
    var magnitude = generateAudioSignal(time, frequency);
    let aWeight = 1.0 + 0.5 * exp(-pow((frequency - 4000.0) / 2000.0, 2.0));
    magnitude = magnitude * aWeight;
    let timeMod = sin(time * 2.0 + normalizedBin * 10.0) * 0.1;
    magnitude = magnitude + timeMod * magnitude;
    return clamp(magnitude, 0.0, 1.0);
}

fn heatmapColor(t: f32) -> vec3<f32> {
    let c1 = vec3<f32>(0.0, 0.0, 0.0);
    let c2 = vec3<f32>(0.0, 0.0, 0.5);
    let c3 = vec3<f32>(0.0, 1.0, 0.0);
    let c4 = vec3<f32>(1.0, 1.0, 0.0);
    let c5 = vec3<f32>(1.0, 0.0, 0.0);
    let c6 = vec3<f32>(1.0, 1.0, 1.0);
    let t1 = clamp(t / 0.16, 0.0, 1.0);
    let t2 = clamp((t - 0.16) / 0.17, 0.0, 1.0);
    let t3 = clamp((t - 0.33) / 0.17, 0.0, 1.0);
    let t4 = clamp((t - 0.5) / 0.16, 0.0, 1.0);
    let t5 = clamp((t - 0.66) / 0.17, 0.0, 1.0);
    var col = mix(c1, c2, t1);
    col = mix(col, c3, t2);
    col = mix(col, c4, t3);
    col = mix(col, c5, t4);
    col = mix(col, c6, t5);
    return col;
}

fn neonColor(t: f32) -> vec3<f32> {
    let c1 = vec3<f32>(0.0, 1.0, 1.0);
    let c2 = vec3<f32>(1.0, 0.0, 1.0);
    let c3 = vec3<f32>(0.6, 0.0, 1.0);
    let t1 = clamp(t * 2.0, 0.0, 1.0);
    let t2 = clamp((t - 0.5) * 2.0, 0.0, 1.0);
    var col = mix(c1, c2, t1);
    col = mix(col, c3, t2);
    return col;
}

fn oceanColor(t: f32) -> vec3<f32> {
    let c1 = vec3<f32>(0.0, 0.1, 0.3);
    let c2 = vec3<f32>(0.0, 0.4, 0.6);
    let c3 = vec3<f32>(0.0, 0.8, 0.8);
    let c4 = vec3<f32>(0.2, 1.0, 0.8);
    let t1 = clamp(t / 0.33, 0.0, 1.0);
    let t2 = clamp((t - 0.33) / 0.33, 0.0, 1.0);
    let t3 = clamp((t - 0.66) / 0.34, 0.0, 1.0);
    var col = mix(c1, c2, t1);
    col = mix(col, c3, t2);
    col = mix(col, c4, t3);
    return col;
}

fn fireColor(t: f32) -> vec3<f32> {
    let c1 = vec3<f32>(0.0, 0.0, 0.0);
    let c2 = vec3<f32>(0.5, 0.0, 0.0);
    let c3 = vec3<f32>(1.0, 0.0, 0.0);
    let c4 = vec3<f32>(1.0, 0.5, 0.0);
    let c5 = vec3<f32>(1.0, 1.0, 0.0);
    let c6 = vec3<f32>(1.0, 1.0, 1.0);
    let t1 = clamp(t / 0.16, 0.0, 1.0);
    let t2 = clamp((t - 0.16) / 0.17, 0.0, 1.0);
    let t3 = clamp((t - 0.33) / 0.17, 0.0, 1.0);
    let t4 = clamp((t - 0.5) / 0.16, 0.0, 1.0);
    let t5 = clamp((t - 0.66) / 0.17, 0.0, 1.0);
    var col = mix(c1, c2, t1);
    col = mix(col, c3, t2);
    col = mix(col, c4, t3);
    col = mix(col, c5, t4);
    col = mix(col, c6, t5);
    return col;
}

fn getColor(magnitude: f32, scheme: f32) -> vec3<f32> {
    let t = clamp(magnitude, 0.0, 1.0);
    let schemeIndex = u32(scheme * 3.0) % 4u;
    let c0 = heatmapColor(t);
    let c1 = neonColor(t);
    let c2 = oceanColor(t);
    let c3 = fireColor(t);
    var col = mix(c0, c1, f32(schemeIndex == 1u));
    col = mix(col, c2, f32(schemeIndex == 2u));
    col = mix(col, c3, f32(schemeIndex == 3u));
    return col;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    
    let dimX = u.config.z;
    let dimY = u.config.w;
    let uv = vec2<f32>(global_id.xy) / vec2<f32>(dimX, dimY);
    let time = u.config.x;
    
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    let freqRange = u.zoom_params.x * (1.0 + bass * 0.3);
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
    magnitude = clamp(magnitude, 0.0, 1.0);
    
    let mousePos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let mouseInBounds = step(0.0, mousePos.y) * step(mousePos.y, 1.0);
    let mouseFreq = getFrequency(mousePos.y, effectiveFreqRange);
    let freqDist = abs(frequency - mouseFreq) / max(mouseFreq, 0.0001);
    let nearMouse = step(freqDist, 0.3) * mouseInBounds;
    let highlight = 1.0 + (0.3 - freqDist) / 0.3 * 1.5;
    magnitude = magnitude * mix(1.0, highlight, nearMouse);
    
    for (var i: i32 = 0; i < 50; i = i + 1) {
        let ripple = u.ripples[i];
        let rippleAge = time - ripple.z;
        let rippleActive = step(0.0, ripple.z) * step(0.0, rippleAge) * step(rippleAge, 3.0);
        let distToRipple = distance(uv, ripple.xy);
        let inRange = step(distToRipple, 0.15);
        let rippleInfluence = (1.0 - rippleAge / 3.0) * (1.0 - distToRipple / 0.15);
        magnitude = magnitude * mix(1.0, 1.0 + rippleInfluence * 2.0, rippleActive * inRange);
    }
    
    magnitude = clamp(magnitude, 0.0, 1.0);
    
    let spectroColor = getColor(magnitude, colorScheme);
    
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    let freqFactor = 1.0 - uv.y;
    let displacementX = magnitude * (src.r - src.b) * 50.0 * effectiveMag;
    let displacementY = magnitude * (src.g - 0.5) * 30.0 * effectiveMag * freqFactor;
    let waveDisp = sin(uv.y * 20.0 + time * 3.0) * magnitude * 10.0;
    
    let uvOffsetX = (displacementX + waveDisp) / dimX;
    let uvOffsetY = displacementY / dimY;
    let displacedUV = clamp(uv + vec2<f32>(uvOffsetX, uvOffsetY), vec2<f32>(0.0), vec2<f32>(1.0));
    let displacedColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
    
    let blendFactor = magnitude * 0.3;
    var finalColor = displacedColor.rgb;
    finalColor = finalColor + spectroColor * magnitude * 0.5 * effectiveMag;
    
    let lowFreqBoost = mix(1.0 + magnitude * 0.2, 1.0, step(0.7, uv.y));
    let highFreqBoost = mix(1.0 + magnitude * 0.1, 1.0, step(uv.y, 0.3));
    finalColor = finalColor * vec3<f32>(lowFreqBoost, 1.0, highFreqBoost);
    
    let vignette = 1.0 - magnitude * 0.3;
    finalColor = finalColor * vignette;
    
    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));
    
    let lumaOut = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.4 + lumaOut * 0.4 + bass * 0.2 + 0.1, 0.0, 1.0);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    
    textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, alpha));
}
