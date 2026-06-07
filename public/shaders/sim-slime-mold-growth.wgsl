// ═══════════════════════════════════════════════════════════════════
//  Sim: Slime Mold Growth (Physarum)
//  Category: simulation
//  Features: simulation, agent-based, chemoattractant, sensor-steering
//  Complexity: Very High
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Agent-based Physarum-style simulation
//  1000s of agents deposit trails, sensor-based steering (left/center/right)
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Sensor sampling
fn sense(trailMap: texture_2d<f32>, pos: vec2<f32>, angle: f32, sensorOffset: f32, sensorDist: f32) -> f32 {
    let sensorDir = vec2<f32>(cos(angle), sin(angle));
    let sensorPos = pos + sensorDir * sensorDist;
    let sensorUV = clamp(sensorPos, vec2<f32>(0.0), vec2<f32>(1.0));
    return textureSampleLevel(trailMap, u_sampler, sensorUV, 0.0).r;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let sensorAngle = mix(0.2, 1.0, u.zoom_params.x);     // x: Sensor angle
    let decayRate = mix(0.9, 0.995, u.zoom_params.y);     // y: Trail decay rate
    let particleCount = mix(100.0, 2000.0, u.zoom_params.z); // z: Particle count (simulated)
    let randomness = mix(0.0, 0.3, u.zoom_params.w);      // w: Randomness/jitter
    
    // Read trail map
    let trail = textureLoad(dataTextureC, gid.xy, 0).r;
    
    // Diffuse and decay trails
    var sum = 0.0;
    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            sum += textureLoad(dataTextureC, vec2<i32>(gid.xy) + vec2<i32>(x, y), 0).r;
        }
    }
    let diffused = sum / 9.0;
    var newTrail = diffused * decayRate;
    
    // Simulate agent deposits at this pixel
    // We simulate agents by hashing position and checking if agents visit this cell
    var deposit = 0.0;
    let numSimulatedAgents = min(i32(particleCount / 10.0), 50);
    
    for (var i: i32 = 0; i < numSimulatedAgents; i++) {
        let fi = f32(i);
        // Agent initial position
        let agentSeed = vec2<f32>(fi * 1.234, fi * 3.456);
        var agentPos = vec2<f32>(
            0.1 + hash12(agentSeed) * 0.8,
            0.1 + hash12(agentSeed + 1.0) * 0.8
        );
        
        // Agent direction (wanders over time)
        var agentAngle = hash12(agentSeed + 2.0) * 6.28 + time * 0.5;
        
        // Simulate agent steps
        for (var step: i32 = 0; step < 20; step++) {
            // Sensor positions
            let leftAngle = agentAngle - sensorAngle;
            let rightAngle = agentAngle + sensorAngle;
            
            // Sample trail at sensors (use current trail map)
            let leftSense = textureSampleLevel(dataTextureC, u_sampler, 
                clamp(agentPos + vec2<f32>(cos(leftAngle), sin(leftAngle)) * 0.02, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
            let centerSense = textureSampleLevel(dataTextureC, u_sampler,
                clamp(agentPos + vec2<f32>(cos(agentAngle), sin(agentAngle)) * 0.02, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
            let rightSense = textureSampleLevel(dataTextureC, u_sampler,
                clamp(agentPos + vec2<f32>(cos(rightAngle), sin(rightAngle)) * 0.02, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
            
            // Steer based on sensor readings
            if (centerSense < leftSense && centerSense < rightSense) {
                // Continue forward with slight randomness
                agentAngle += (hash12(agentPos + time) - 0.5) * randomness;
            } else if (leftSense > rightSense) {
                agentAngle -= sensorAngle * 0.3;
            } else if (rightSense > leftSense) {
                agentAngle += sensorAngle * 0.3;
            }
            
            // Move agent
            agentPos += vec2<f32>(cos(agentAngle), sin(agentAngle)) * 0.003;
            agentPos = fract(agentPos); // Wrap around
            
            // Check if agent is near this pixel
            let distToCell = length(agentPos - uv);
            if (distToCell < 0.005) {
                deposit += 0.05;
            }
        }
    }
    
    // Add deposit from mouse
    let mousePos = u.zoom_config.yz;
    let mouseDist = length(uv - mousePos);
    if (mouseDist < 0.03) {
        deposit += 0.1 * (1.0 - mouseDist / 0.03);
    }
    
    newTrail = min(newTrail + deposit, 1.0);
    
    // Store trail
    textureStore(dataTextureA, gid.xy, vec4<f32>(newTrail, 0.0, 0.0, 1.0));
    
    // Render
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    // Trail color (cyan/gold gradient based on density)
    let trailColor = vec3<f32>(
        newTrail * 0.2 + pow(newTrail, 3.0) * 0.8,
        newTrail * 0.8,
        newTrail * 0.9 + pow(newTrail, 2.0) * 0.1
    );
    
    // Blend with background
    var color = mix(baseColor * 0.2, trailColor, newTrail * 0.9);
    
    // Add glow
    color += vec3<f32>(0.0, newTrail * 0.3, newTrail * 0.4) * newTrail;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    textureStore(writeTexture, gid.xy, vec4<f32>(color, mix(0.7, 1.0, newTrail)));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth * (1.0 - newTrail * 0.2), 0.0, 0.0, 0.0));
}
