// ═══════════════════════════════════════════════════════════════════
//  Holographic Interferometry
//  Category: generative
//  Features: advanced-hybrid, interference-patterns, holography, phase-coloring
//  Complexity: High
//  Chunks From: holographic_interference.wgsl, anamorphic-flare
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Simulated hologram with interference fringes
//  Rainbow interference patterns, speckled laser light, depth-parallax
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

// ═══ CHUNK: hash12 ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ SPECKLE NOISE (laser coherence) ═══
fn speckleNoise(uv: vec2<f32>, coherence: f32) -> f32 {
    let scale = mix(50.0, 500.0, coherence);
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
        let fi = f32(i);
        s += hash12(uv * scale + vec2<f32>(fi * 13.7, fi * 42.3));
    }
    return s / 4.0;
}

// ═══ INTERFERENCE PATTERN ═══
fn interferencePattern(uv: vec2<f32>, depth: f32, fringeDensity: f32, angle: f32) -> f32 {
    // Object beam with depth parallax
    let objectPhase = depth * fringeDensity * 10.0;
    
    // Reference beam at angle
    let refPhase = (uv.x * cos(angle) + uv.y * sin(angle)) * fringeDensity * 50.0;
    
    // Phase difference creates interference fringes
    let phaseDiff = objectPhase + refPhase;
    
    // Interference intensity (constructive/destructive)
    let interference = 0.5 + 0.5 * cos(phaseDiff);
    
    return interference;
}

// ═══ HOLOGRAPHIC RECONSTRUCTION ═══
fn reconstructHologram(uv: vec2<f32>, depth: f32, intensity: f32, phase: f32, angle: f32) -> vec3<f32> {
    // Reconstruction beam
    let reconPhase = (uv.x * cos(angle + 0.5) + uv.y * sin(angle + 0.5)) * 20.0;
    
    // Combined phase
    let totalPhase = phase + reconPhase;
    
    // Phase to color mapping (rainbow hologram)
    let hue = fract(totalPhase / 6.28);
    let sat = 0.7 + intensity * 0.3;
    let val = 0.5 + intensity * 0.5;
    
    // HSV to RGB
    let c = val * sat;
    let h = hue * 6.0;
    let x = c * (1.0 - abs(h % 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    
    if (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else { rgb = vec3<f32>(c, 0.0, x); }
    
    return rgb + vec3<f32>(val - c);
}

// ═══ MAIN ═══
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.config.y;
    let audioBass = u.config.y * 1.2;
    let audioMid = u.config.z;
    let audioHigh = u.config.w;
    let audioReactivity = 1.0 + audioOverall * 0.5;
    let id = vec2<i32>(global_id.xy);
    
    // Parameters
    let fringeDensity = mix(10.0, 100.0, u.zoom_params.x); // x: Fringe density
    let coherence = u.zoom_params.y;                        // y: Coherence (speckle size)
    let reconAngle = u.zoom_params.z * 3.14;               // z: Reconstruction angle
    let saturation = mix(0.5, 1.5, u.zoom_params.w);       // w: Saturation
    
    // Sample source and depth
    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let luma = dot(sourceColor, vec3<f32>(0.299, 0.587, 0.114));
    
    // Calculate interference pattern
    let interference = interferencePattern(uv, depth, fringeDensity, reconAngle);
    
    // Phase from interference
    let phase = acos(interference * 2.0 - 1.0);
    
    // Holographic reconstruction
    var holoColor = reconstructHologram(uv, depth, luma, phase, reconAngle);
    
    // Add speckle noise
    let speckle = speckleNoise(uv + time * 0.01 * audioReactivity, coherence);
    let specklePattern = mix(0.8, 1.2, speckle * coherence);
    
    // Combine with source image
    let hologram = holoColor * luma * specklePattern * saturation;
    
    // Add fringe visualization
    let fringes = sin(phase * fringeDensity) * 0.5 + 0.5;
    let fringeColor = vec3<f32>(fringes * 0.5, fringes * 0.3, fringes * 0.7);
    
    var color = mix(sourceColor * 0.3, hologram + fringeColor * 0.2, 0.8);
    
    // Depth-based parallax effect
    let parallax = depth * 0.02;
    let parallaxUV = uv + vec2<f32>(cos(reconAngle), sin(reconAngle)) * parallax;
    let parallaxColor = textureSampleLevel(readTexture, u_sampler, clamp(parallaxUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    
    color = mix(color, parallaxColor * holoColor, depth * 0.3);
    
    let alpha = mix(0.75, 0.95, luma);
    
    textureStore(writeTexture, id, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
