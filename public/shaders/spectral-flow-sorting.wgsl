// ═══════════════════════════════════════════════════════════════════
//  Spectral Flow Sorting
//  Category: distortion
//  Features: advanced-hybrid, pixel-sorting, optical-flow, fft
//  Complexity: High
//  Chunks From: flow-sort.wgsl, luma-flow-field
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Flow-aware pixel sorting with frequency analysis
//  Pixels flow and sort along motion vectors
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

// ═══ OPTICAL FLOW CALCULATION ═══
fn calculateOpticalFlow(uv: vec2<f32>, pixel: vec2<f32>) -> vec2<f32> {
    // Current frame
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let currLuma = dot(current, vec3<f32>(0.299, 0.587, 0.114));
    
    // Previous frame (from dataTextureC)
    let previous = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let prevLuma = dot(previous, vec3<f32>(0.299, 0.587, 0.114));
    
    // Spatial gradients
    let right = dot(textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(pixel.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let left = dot(textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(pixel.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let up = dot(textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, pixel.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let down = dot(textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0, pixel.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    
    let dx = (right - left) * 0.5;
    let dy = (up - down) * 0.5;
    let dt = currLuma - prevLuma;
    
    // Optical flow (simplified Lucas-Kanade)
    let flow = vec2<f32>(dx, dy) * dt * 10.0;
    
    return flow;
}

// ═══ SIMULATED FFT (frequency analysis) ═══
fn analyzeFrequency(uv: vec2<f32>, pixel: vec2<f32>) -> f32 {
    // Simplified local frequency analysis using edge detection
    var gradientSum = 0.0;
    var sampleCount = 0.0;
    
    for (var i: i32 = -2; i <= 2; i++) {
        for (var j: i32 = -2; j <= 2; j++) {
            let offset = vec2<f32>(f32(i), f32(j)) * pixel * 3.0;
            let sample = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
            let luma = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
            
            let nextOffset = vec2<f32>(f32(i + 1), f32(j)) * pixel * 3.0;
            let nextSample = textureSampleLevel(readTexture, u_sampler, uv + nextOffset, 0.0).rgb;
            let nextLuma = dot(nextSample, vec3<f32>(0.299, 0.587, 0.114));
            
            gradientSum += abs(luma - nextLuma);
            sampleCount += 1.0;
        }
    }
    
    // High gradient = high frequency
    return gradientSum / sampleCount;
}

// ═══ PIXEL SORTING ALONG FLOW LINE ═══
fn sortAlongFlow(uv: vec2<f32>, flowDir: vec2<f32>, threshold: f32) -> vec3<f32> {
    var sorted = vec3<f32>(0.0);
    var weights = 0.0;
    
    // Sample along flow line
    for (var i: i32 = -5; i <= 5; i++) {
        let t = f32(i) / 5.0;
        let sampleUV = uv + flowDir * t * 0.1;
        
        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) {
            continue;
        }
        
        let sample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let luma = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
        
        // Weight by luminance (sorting effect)
        let weight = select(0.0, luma, luma > threshold);
        sorted += sample * weight;
        weights += weight;
    }
    
    return select(vec3<f32>(0.0), sorted / weights, weights > 0.001);
}

// ═══ MAIN ═══
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixel = 1.0 / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    let id = vec2<i32>(global_id.xy);
    
    // Parameters
    let flowSensitivity = mix(0.0, 5.0, u.zoom_params.x);    // x: Flow sensitivity
    let sortThreshold = u.zoom_params.y;                      // y: Sort threshold
    let freqInfluence = u.zoom_params.z;                      // z: Frequency influence
    let smoothing = mix(0.0, 0.9, u.zoom_params.w);          // w: Temporal smoothing
    
    // Mouse interaction
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;
    let distToMouse = length(uv - mousePos);
    let mouseGravity = 1.0 - smoothstep(0.0, 0.35, distToMouse);
    let clickPulse = select(0.0, 1.0, isMouseDown) * sin(distToMouse * 25.0 - time * 5.0) * exp(-distToMouse * 3.0);
    
    // Calculate optical flow
    let mouseDir = normalize(uv - mousePos + 0.001);
    let cursorFlow = mouseDir * mouseGravity * 3.0 * (1.0 + select(0.0, 3.0, isMouseDown));
    let flow = calculateOpticalFlow(uv, pixel) * flowSensitivity + cursorFlow + clickPulse;
    let flowMag = length(flow);
    let flowDir = select(vec2<f32>(0.0), normalize(flow), flowMag > 0.001);
    
    // Analyze frequency content
    let dominantFreq = analyzeFrequency(uv, pixel);
    
    // Pixel sort along flow direction
    let sortedColor = sortAlongFlow(uv, flowDir, sortThreshold);
    
    // Frequency-based color shift
    let freqColor = vec3<f32>(
        dominantFreq * 2.0,
        dominantFreq * 1.5,
        dominantFreq * 3.0
    );
    
    // Base color
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    // Blend based on flow and frequency
    var color = mix(baseColor, sortedColor, flowMag * smoothing);
    color = mix(color, freqColor, dominantFreq * freqInfluence);
    
    // Flow visualization
    let flowAngle = atan2(flow.y, flow.x) / 6.28 + 0.5;
    let flowColor = vec3<f32>(
        0.5 + 0.5 * cos(flowAngle * 6.28),
        0.5 + 0.5 * cos(flowAngle * 6.28 + 2.09),
        0.5 + 0.5 * cos(flowAngle * 6.28 + 4.18)
    );
    color = mix(color, flowColor, flowMag * 0.3);
    
    // Store current frame for next optical flow calculation
    textureStore(dataTextureA, id, vec4<f32>(baseColor, 1.0));
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.8, 1.0, flowMag * 0.5) + mouseGravity * 0.2;
    
    textureStore(writeTexture, id, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
