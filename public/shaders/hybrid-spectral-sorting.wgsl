// ═══════════════════════════════════════════════════════════════════
//  Hybrid Spectral Sorting
//  Category: distortion
//  Features: hybrid, pixel-sorting, spectral-analysis, audio-reactive
//  Chunks From: bitonic-sort pattern, spectrogram-displace (spectral analysis),
//               audio-reactive pattern
//  Created: 2026-03-22
//  By: Agent 2A - Shader Surgeon
// ═══════════════════════════════════════════════════════════════════
//  Concept: Audio-reactive pixel sorting with frequency-based color
//           shifts and displacement based on spectral analysis
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
  config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=AudioFFT, y=MouseX, z=MouseY, w=Generic
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK 1: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK 2: fbm2 (from gen_grid.wgsl) ═══
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

// ═══ CHUNK 3: palette (from gen-xeno-botanical-synth-flora.wgsl) ═══
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// ═══ CHUNK 4: hueShift (from stellar-plasma.wgsl) ═══
fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(hue);
    return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

// ═══ HYBRID LOGIC: Spectral Pixel Sorting ═══
fn rgb2luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let id = vec2<i32>(global_id.xy);
    
    // Audio input (from zoom_config.x)
    let audio = u.zoom_config.x;
    let bassPulse = 1.0 + audio * 0.5;
    
    // Parameters
    let sortThreshold = mix(0.1, 0.5, u.zoom_params.x);    // x: Sorting sensitivity
    let spectralBands = mix(4.0, 32.0, u.zoom_params.y);   // y: Frequency bands
    let displacement = mix(0.0, 0.2, u.zoom_params.z);     // z: Spectral displacement
    let hueShiftAmount = u.zoom_params.w * 3.14159;        // w: Color shift
    
    // Spectral analysis bands
    let band = floor(uv.y * spectralBands);
    let bandPhase = band / spectralBands;
    
    // Generate pseudo-spectral data from FBM + audio
    let spectralNoise = fbm2(vec2<f32>(bandPhase * 10.0, time * 0.5), 3);
    let bandEnergy = spectralNoise * (0.5 + audio * 0.5);
    
    // Pixel sorting logic
    var sortUV = uv;
    let sortDir = vec2<f32>(0.0, 1.0); // Vertical sort
    
    // Compare current pixel with neighbor in sort direction
    let neighborDist = 2.0 + bandEnergy * 10.0;
    let neighborUV = uv + sortDir * neighborDist / resolution.y;
    
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let neighbor = textureSampleLevel(readTexture, u_sampler, neighborUV, 0.0).rgb;
    
    let currentLuma = rgb2luma(current);
    let neighborLuma = rgb2luma(neighbor);
    
    // Sort based on luminance difference and threshold
    let lumaDiff = abs(currentLuma - neighborLuma);
    let shouldSort = lumaDiff > sortThreshold;
    
    // Spectral displacement
    let displacementVec = vec2<f32>(
        sin(bandPhase * 6.28318 + time) * bandEnergy,
        cos(bandPhase * 6.28318 + time * 0.7) * bandEnergy
    ) * displacement;
    
    // Sample with displacement
    let displacedUV = uv + displacementVec * bassPulse;
    let displaced = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;
    
    // Color based on spectral band
    let spectralColor = palette(bandPhase + time * 0.1,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 1.0, 0.5),
        vec3<f32>(0.0, 0.33, 0.67)
    );
    
    // Mix original with sorted version
    var color: vec3<f32>;
    if (shouldSort) {
        // Swap colors based on luminance
        if (currentLuma > neighborLuma) {
            color = mix(current, neighbor, 0.7);
        } else {
            color = mix(neighbor, current, 0.7);
        }
    } else {
        color = displaced;
    }
    
    // Apply spectral color tint
    color = mix(color, color * spectralColor, bandEnergy * 0.5);
    
    // Hue shift based on band and audio
    color = hueShift(color, hueShiftAmount * bandPhase + audio * 0.5);
    
    // Audio-reactive glow
    let glow = bandEnergy * audio * 0.5;
    color += spectralColor * glow;
    
    // Glitch effect on beat
    let beat = step(0.7, audio);
    if (beat > 0.0) {
        let glitchOffset = vec2<f32>(hash12(uv + time) - 0.5, 0.0) * 0.02 * beat;
        let glitchColor = textureSampleLevel(readTexture, u_sampler, uv + glitchOffset, 0.0).rgb;
        color = mix(color, glitchColor, 0.3);
    }
    
    // Alpha based on activity
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(0.7, 1.0, luma + bandEnergy * 0.3);
    
    // Depth pass-through with audio modulation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    textureStore(writeTexture, id, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - bandEnergy * 0.2), 0.0, 0.0, 0.0));
}
