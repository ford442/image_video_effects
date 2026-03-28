// ═══════════════════════════════════════════════════════════════════
//  Chladni Plate Cymatics - Modal Synthesis Visualization
//  Category: generative
//  Features: upgraded-rgba, depth-aware, procedural, animated, organic
//  Scientific basis: Chladni figures from vibrating plate standing waves
//  Upgraded: 2026-03-22
//  By: Agent 1A - Alpha Channel Specialist
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

// Modal numbers for Chladni patterns (m, n, amplitude, phase)
const MODES: array<vec4<f32>, 8> = array<vec4<f32>, 8>(
    vec4<f32>(1.0, 1.0, 1.0, 0.0),   // (1,1) - fundamental
    vec4<f32>(2.0, 1.0, 0.8, 0.5),   // (2,1) - horizontal split
    vec4<f32>(1.0, 2.0, 0.8, 0.3),   // (1,2) - vertical split
    vec4<f32>(2.0, 2.0, 0.6, 0.7),   // (2,2) - quadrant pattern
    vec4<f32>(3.0, 1.0, 0.5, 0.2),   // (3,1) - two horizontal splits
    vec4<f32>(1.0, 3.0, 0.5, 0.9),   // (1,3) - two vertical splits
    vec4<f32>(3.0, 2.0, 0.4, 0.4),   // (3,2) - complex pattern
    vec4<f32>(2.0, 3.0, 0.4, 0.6)    // (2,3) - complex pattern
);

// Hash function for particle noise
fn hash2(p: vec2<f32>) -> f32 {
    let k = vec2<f32>(0.3183099, 0.3678794);
    var x = p * k + k.yx;
    return fract(16.0 * k.x * fract(x.x * x.y * (x.x + x.y)));
}

// Smooth noise for sand texture
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i + vec2<f32>(0.0, 0.0)), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    
    // Parameters
    let sweepSpeed = u.zoom_params.x * 2.0 + 0.1;    // Frequency sweep speed
    let numModes = i32(clamp(u.zoom_params.y * 8.0 + 1.0, 1.0, 8.0)); // Modes to mix
    let sharpness = u.zoom_params.z * 3.0 + 0.5;     // Pattern sharpness
    let particleDensity = u.zoom_params.w;            // Particle density
    
    // Normalized plate coordinates (-1 to 1, centered)
    let plateUV = (uv - 0.5) * 2.0;
    let x = plateUV.x;
    let y = plateUV.y;
    
    // Animated base frequency (sweep through resonances)
    let baseFreq = 3.14159265 * (1.0 + sin(time * sweepSpeed * 0.2) * 0.5);
    
    // Calculate plate displacement using modal synthesis
    // displacement = Σ sin(m*π*x/L) * sin(n*π*y/L) * cos(ωt + phase) * amplitude
    var displacement = 0.0;
    
    for (var i: i32 = 0; i < numModes; i = i + 1) {
        let mode = MODES[i];
        let m = mode.x;
        let n = mode.y;
        let amp = mode.z;
        let phase = mode.w * 6.28318;
        
        // Wave numbers
        let kx = m * baseFreq;
        let ky = n * baseFreq;
        
        // Modal vibration with time evolution
        let modeOscillation = cos(time * sweepSpeed + phase + f32(i) * 0.5);
        
        // Displacement from this mode
        let modeDisplacement = sin(kx * x) * sin(ky * y) * modeOscillation * amp;
        
        displacement = displacement + modeDisplacement;
    }
    
    // Normalize displacement
    displacement = displacement / f32(numModes);
    
    // Mouse interaction - create localized disturbance
    let mouseDist = length(plateUV - (mouse - 0.5) * 2.0);
    let mouseInfluence = exp(-mouseDist * 8.0) * sin(time * 10.0 + mouseDist * 20.0);
    displacement = displacement + mouseInfluence * 0.3;
    
    // Calculate nodal lines (where displacement ≈ 0)
    let nodeMask = 1.0 - smoothstep(0.0, 0.15 / sharpness, abs(displacement));
    
    // Sand/particle accumulation at nodes
    // Particles settle where vibration amplitude is minimal
    let vibrationEnergy = abs(displacement);
    let particleSettling = 1.0 - smoothstep(0.0, 0.3, vibrationEnergy);
    
    // Add noise texture for granular sand appearance
    let sandNoise = noise(uv * 400.0 + time * 0.1);
    let sandDetail = noise(uv * 150.0 - time * 0.05);
    
    // Particle distribution - more particles at nodes
    let particleThreshold = 0.6 - particleDensity * 0.4;
    let particleMask = step(particleThreshold, particleSettling + sandNoise * 0.15);
    
    // Color palette inspired by sand and metal plate
    // Node lines (darker - sand accumulation)
    let sandColor = vec3<f32>(0.85, 0.78, 0.65) * (0.8 + sandDetail * 0.4);
    
    // Antinode areas (lighter - cleared plate)
    let plateColor = vec3<f32>(0.15, 0.12, 0.10) * (1.0 + vibrationEnergy * 0.5);
    
    // Interference pattern coloration
    let patternHue = sin(displacement * 10.0 + time * 0.5) * 0.5 + 0.5;
    let interferenceColor = mix(
        vec3<f32>(0.9, 0.85, 0.7),   // Warm sand
        vec3<f32>(0.6, 0.7, 0.8),   // Cool metal
        patternHue * 0.3
    );
    
    // Combine: particles show sand color, cleared areas show plate
    var color = mix(plateColor, sandColor * interferenceColor, particleMask);
    
    // Emphasize nodal lines with subtle glow
    let nodeGlow = nodeMask * 0.3 * (0.5 + sandNoise * 0.5);
    color = color + vec3<f32>(nodeGlow * 0.9, nodeGlow * 0.85, nodeGlow * 0.7);
    
    // Add subtle specular highlight based on vibration
    let highlight = pow(1.0 - vibrationEnergy, 3.0) * 0.2;
    color = color + vec3<f32>(highlight);
    
    // Vignette for plate edge visualization
    let edgeDist = length(plateUV);
    let vignette = 1.0 - smoothstep(0.7, 1.0, edgeDist);
    color = color * (0.7 + vignette * 0.3);
    
    // Plate boundary visualization
    let boundary = smoothstep(0.98, 1.0, edgeDist);
    color = mix(color, vec3<f32>(0.3, 0.25, 0.2), boundary * 0.5);
    
    // Calculate alpha based on content presence
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.7, 1.0, luma);
    
    // Depth-aware alpha modulation
    let depthAlpha = mix(0.6, 1.0, depth);
    let finalAlpha = (alpha + depthAlpha) * 0.5;
    
    // Output RGBA color
    textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
    
    // Store vibration energy in depth for potential post-processing
    let depthValue = vibrationEnergy * 0.5 + 0.5;
    textureStore(writeDepthTexture, coord, vec4<f32>(depthValue, 0.0, 0.0, 0.0));
}
