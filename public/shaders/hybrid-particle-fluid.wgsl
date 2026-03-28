// ═══════════════════════════════════════════════════════════════════
//  Hybrid Particle Fluid
//  Category: simulation
//  Features: hybrid, particle-system, fluid-advection, glow
//  Chunks From: particle-swarm.wgsl (particle logic), navier-stokes pattern,
//               neon-pulse glow concept
//  Created: 2026-03-22
//  By: Agent 2A - Shader Surgeon
// ═══════════════════════════════════════════════════════════════════
//  Concept: Particles that move like fluid with glowing trails,
//           combining particle advection with velocity field flow
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

// ═══ HYBRID LOGIC: Particle Fluid System ═══
// Curl noise for divergence-free velocity field
fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.01;
    let n1 = fbm2(p + vec2<f32>(eps, 0.0) + time * 0.1, 4);
    let n2 = fbm2(p - vec2<f32>(eps, 0.0) + time * 0.1, 4);
    let n3 = fbm2(p + vec2<f32>(0.0, eps) + time * 0.1, 4);
    let n4 = fbm2(p - vec2<f32>(0.0, eps) + time * 0.1, 4);
    
    let dx = (n1 - n2) / (2.0 * eps);
    let dy = (n3 - n4) / (2.0 * eps);
    
    return vec2<f32>(dy, -dx); // Perpendicular gradient = curl
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let id = vec2<i32>(global_id.xy);
    
    // Parameters
    let particleCount = mix(20.0, 100.0, u.zoom_params.x);   // x: Particle density
    let fluidSpeed = mix(0.5, 3.0, u.zoom_params.y);         // y: Flow speed
    let trailDecay = mix(0.9, 0.99, u.zoom_params.z);        // z: Trail persistence
    let glowRadius = mix(0.01, 0.05, u.zoom_params.w);       // w: Glow size
    
    // Get velocity from curl noise (fluid simulation)
    let velocity = curlNoise(uv * 2.0, time * 0.2) * fluidSpeed * 0.01;
    
    // Sample previous frame for trails
    let backUV = uv - velocity;
    let prevColor = textureSampleLevel(dataTextureC, u_sampler, backUV, 0.0).rgb;
    
    // Particle positions (grid-based with jitter)
    let gridSize = 1.0 / sqrt(particleCount);
    var particleIntensity = 0.0;
    var particleColor = vec3<f32>(0.0);
    
    for (var i: i32 = 0; i < i32(particleCount); i++) {
        let fi = f32(i);
        let particleBase = vec2<f32>(
            fract(fi * 0.618034), // Golden ratio distribution
            fract(fi * 0.414213)  // Another irrational
        );
        
        // Animate particle along flow
        let age = fract(time * 0.1 + fi * 0.01);
        var particlePos = particleBase;
        
        // Advect particle through velocity field
        for (var step: i32 = 0; step < 5; step++) {
            let vel = curlNoise(particlePos * 2.0, time * 0.2) * fluidSpeed * 0.02;
            particlePos += vel;
        }
        
        // Particle trail
        let trailLength = 10;
        for (var t: i32 = 0; t < trailLength; t++) {
            let ft = f32(t) / f32(trailLength);
            let trailPos = particlePos - velocity * f32(t) * 5.0;
            let dist = length(uv - fract(trailPos));
            
            if (dist < glowRadius * (1.0 + ft)) {
                let intensity = (1.0 - ft) * (1.0 - dist / glowRadius);
                particleIntensity += intensity;
                
                let hue = fi / particleCount + age * 0.2;
                let pColor = palette(hue,
                    vec3<f32>(0.5),
                    vec3<f32>(0.5),
                    vec3<f32>(1.0),
                    vec3<f32>(0.0, 0.33, 0.67)
                );
                particleColor += pColor * intensity;
            }
        }
    }
    
    // Combine fluid trails with particles
    var color = prevColor * trailDecay;
    
    if (particleIntensity > 0.0) {
        particleColor /= particleIntensity;
        color += particleColor * particleIntensity * 0.5;
    }
    
    // Add velocity visualization
    let velMag = length(velocity);
    color += vec3<f32>(0.2, 0.4, 0.8) * velMag * 10.0;
    
    // Vorticity visualization
    let vorticity = fbm2(uv * 4.0 + time * 0.15, 3);
    color += vec3<f32>(0.8, 0.3, 0.2) * vorticity * 0.1;
    
    // Alpha based on activity
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(0.5, 1.0, luma + particleIntensity * 0.3);
    
    // Store for feedback
    textureStore(dataTextureA, id, vec4<f32>(color, alpha));
    
    textureStore(writeTexture, id, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(velMag * 10.0, 0.0, 0.0, 0.0));
}
