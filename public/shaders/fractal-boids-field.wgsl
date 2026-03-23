// ═══════════════════════════════════════════════════════════════════
//  Fractal Boids Field
//  Category: simulation
//  Features: advanced-hybrid, boids, fractal-flow-field, gpu-particles
//  Complexity: High
//  Chunks From: boids.wgsl, gen_grid
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Flocking behavior on a fractal vector field
//  Swarms of particles flowing through organic fractal currents
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

// ═══ CHUNK: fbm2 ═══
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

// ═══ DOMAIN WARP FBM ═══
fn domainWarpFBM(p: vec2<f32>, time: f32) -> vec2<f32> {
    let q = vec2<f32>(
        fbm2(p + vec2<f32>(0.0, time * 0.1 * audioReactivity), 4),
        fbm2(p + vec2<f32>(5.2, 1.3 + time * 0.1 * audioReactivity), 4)
    );
    let r = vec2<f32>(
        fbm2(p + 4.0 * q + vec2<f32>(1.7 - time * 0.15 * audioReactivity, 9.2), 4),
        fbm2(p + 4.0 * q + vec2<f32>(8.3 - time * 0.15 * audioReactivity, 2.8), 4)
    );
    return r;
}

// ═══ FLOW FIELD SAMPLE ═══
fn sampleFlowField(uv: vec2<f32>, time: f32, flowStrength: f32) -> vec2<f32> {
    let warped = domainWarpFBM(uv * 5.0, time * 0.1 * audioReactivity);
    let angle = warped.x * 6.28 * flowStrength;
    return vec2<f32>(cos(angle), sin(angle));
}

// ═══ BOID SIMULATION ═══
fn simulateBoids(uv: vec2<f32>, time: f32, boidCount: f32, flowStrength: f32, separationDist: f32) -> vec3<f32> {
    var boidColor = vec3<f32>(0.0);
    let hashUV = floor(uv * boidCount) / boidCount;
    let boidId = hash12(hashUV);
    
    // Simulated boid position (in grid cell)
    var boidPos = hashUV + vec2<f32>(
        sin(time * (1.0 + boidId * 2.0) + boidId * 10.0),
        cos(time * (1.0 + boidId * 1.5) + boidId * 10.0)
    ) * 0.5 / boidCount;
    
    // Get flow field at boid position
    let flow = sampleFlowField(boidPos, time, flowStrength);
    
    // Boid rules (simplified for performance)
    var separation = vec2<f32>(0.0);
    var alignment = flow;
    var cohesion = vec2<f32>(0.0);
    
    // Sample neighbors (simplified grid-based)
    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            if (x == 0 && y == 0) { continue; }
            let neighborUV = hashUV + vec2<f32>(f32(x), f32(y)) / boidCount;
            let neighborId = hash12(neighborUV);
            let neighborPos = neighborUV + vec2<f32>(
                sin(time * (1.0 + neighborId * 2.0) + neighborId * 10.0),
                cos(time * (1.0 + neighborId * 1.5) + neighborId * 10.0)
            ) * 0.5 / boidCount;
            
            let diff = boidPos - neighborPos;
            let dist = length(diff);
            
            if (dist < separationDist / boidCount && dist > 0.001) {
                separation += normalize(diff) / dist;
            }
            
            cohesion += neighborPos;
        }
    }
    
    cohesion = cohesion / 8.0 - boidPos;
    
    // Combine forces
    let velocity = normalize(separation * 1.5 + alignment * 1.0 + cohesion * 0.5 + flow * 2.0);
    
    // Trail rendering
    let toBoid = uv - boidPos;
    let distToBoid = length(toBoid);
    let trailWidth = 0.003;
    
    if (distToBoid < trailWidth * (1.0 + boidId)) {
        // Boid color based on velocity direction
        let hue = atan2(velocity.y, velocity.x) / 6.28 + 0.5;
        boidColor = vec3<f32>(
            0.5 + 0.5 * cos(hue * 6.28),
            0.5 + 0.5 * cos(hue * 6.28 + 2.09),
            0.5 + 0.5 * cos(hue * 6.28 + 4.18)
        );
    }
    
    // Trail behind boid
    let trailDir = -velocity;
    for (var i = 1; i < 10; i++) {
        let trailPos = boidPos + trailDir * f32(i) * 0.01;
        let distToTrail = length(uv - trailPos);
        let trailIntensity = 1.0 - f32(i) / 10.0;
        if (distToTrail < trailWidth * trailIntensity) {
            let trailColor = vec3<f32>(0.8, 0.9, 1.0) * trailIntensity * 0.5;
            boidColor = max(boidColor, trailColor);
        }
    }
    
    return boidColor;
}

// ═══ MAIN ═══
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    let id = vec2<i32>(global_id.xy);
    
    // Parameters
    let boidCount = mix(10.0, 50.0, u.zoom_params.x);      // x: Boid count (simulated)
    let flowStrength = mix(0.5, 3.0, u.zoom_params.y);      // y: Flow field strength
    let trailPersist = u.zoom_params.z;                      // z: Trail persistence
    let separation = mix(0.02, 0.1, u.zoom_params.w);       // w: Separation distance
    
    // Base image
    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    // Calculate boid field
    let boidColor = simulateBoids(uv, time, boidCount, flowStrength, separation);
    
    // Blend with background
    color = mix(color, boidColor, length(boidColor) * (0.5 + trailPersist * 0.5));
    
    // Add flow field visualization
    let flow = sampleFlowField(uv, time, flowStrength * 0.5);
    let flowMag = length(flow);
    color += vec3<f32>(flowMag * 0.1, flowMag * 0.05, flowMag * 0.15) * flowStrength;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.75, 1.0, length(boidColor));
    
    textureStore(writeTexture, id, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
