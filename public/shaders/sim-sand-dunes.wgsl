// ═══════════════════════════════════════════════════════════════════
//  Sim: Sand Dunes
//  Category: simulation
//  Features: simulation, cellular-automata, falling-sand, wind-erosion
//  Complexity: High
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Falling sand physics with wind erosion
//  Grid-based: sand falls, piles at angle of repose, wind moves loose sand
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let gravity = mix(0.5, 2.0, u.zoom_params.x);     // x: Gravity strength
    let wind = mix(-0.1, 0.1, u.zoom_params.y);       // y: Wind direction/speed
    let viscosity = mix(0.9, 0.99, u.zoom_params.z);  // z: Sand viscosity
    let erosion = mix(0.0, 0.1, u.zoom_params.w);     // w: Erosion rate
    
    // Read current cell
    let self = textureLoad(dataTextureC, gid.xy, 0).r;
    let selfType = textureLoad(dataTextureC, gid.xy, 0).g; // Sand type/color variation
    
    // Read neighbors
    let below = textureLoad(dataTextureC, gid.xy - vec2<u32>(0u, 1u), 0).r;
    let belowLeft = textureLoad(dataTextureC, gid.xy - vec2<u32>(1u, 1u), 0).r;
    let belowRight = textureLoad(dataTextureC, gid.xy + vec2<u32>(1u, 1u), 0).r;
    let left = textureLoad(dataTextureC, gid.xy - vec2<u32>(1u, 0u), 0).r;
    let right = textureLoad(dataTextureC, gid.xy + vec2<u32>(1u, 0u), 0).r;
    
    var newState = self;
    var newType = selfType;
    
    // Sand physics
    if (self > 0.5) {
        // This cell has sand - try to fall
        if (below < 0.5) {
            // Fall straight down
            newState = 0.0;
        } else if (belowLeft < 0.5 && belowRight < 0.5) {
            // Slide down randomly
            newState = select(0.0, 1.0, hash12(uv + time) > 0.5);
        } else if (belowLeft < 0.5) {
            // Slide left
            newState = 0.0;
        } else if (belowRight < 0.5) {
            // Slide right
            newState = 0.0;
        }
        
        // Wind erosion - move sand horizontally
        if (newState > 0.5 && hash12(uv + time * 0.1) < abs(wind) * 5.0) {
            if (wind > 0.0 && right < 0.5) {
                newState = 0.0;
            } else if (wind < 0.0 && left < 0.5) {
                newState = 0.0;
            }
        }
    } else {
        // Empty - check if sand falls into here
        let above = textureLoad(dataTextureC, gid.xy + vec2<u32>(0u, 1u), 0).r;
        let aboveLeft = textureLoad(dataTextureC, gid.xy + vec2<u32>(1u, 1u), 0).r;
        let aboveRight = textureLoad(dataTextureC, gid.xy - vec2<u32>(1u, 1u), 0).r;
        let aboveType = textureLoad(dataTextureC, gid.xy + vec2<u32>(0u, 1u), 0).g;
        
        if (above > 0.5) {
            newState = above;
            newType = aboveType;
        } else if (aboveLeft > 0.5 && wind > 0.0 && hash12(uv + time) < abs(wind) * 10.0) {
            newState = aboveLeft;
            newType = textureLoad(dataTextureC, gid.xy + vec2<u32>(1u, 1u), 0).g;
        } else if (aboveRight > 0.5 && wind < 0.0 && hash12(uv + time) < abs(wind) * 10.0) {
            newState = aboveRight;
            newType = textureLoad(dataTextureC, gid.xy - vec2<u32>(1u, 1u), 0).g;
        }
    }
    
    // Add new sand at mouse position
    let mousePos = u.zoom_config.yz;
    let mouseDist = length(uv - mousePos);
    if (mouseDist < 0.03) {
        newState = 1.0;
        newType = fract(time * 0.1);
    }
    
    // Initialize with some sand at bottom
    if (time < 1.0 && uv.y < 0.1 && hash12(uv * 10.0) > 0.3) {
        newState = 1.0;
        newType = hash12(uv);
    }
    
    // Store state
    textureStore(dataTextureA, gid.xy, vec4<f32>(newState, newType, 0.0, 1.0));
    
    // Color based on sand type
    let sandColors = array<vec3<f32>, 4>(
        vec3<f32>(0.94, 0.78, 0.53), // Gold
        vec3<f32>(0.91, 0.67, 0.41), // Orange
        vec3<f32>(0.85, 0.55, 0.32), // Rust
        vec3<f32>(0.76, 0.60, 0.42)  // Brown
    );
    
    let colorIdx = i32(newType * 4.0) % 4;
    var sandColor = sandColors[colorIdx];
    
    // Add shading based on neighbors
    if (newState > 0.5) {
        let heightDiff = above - below;
        sandColor *= (0.8 + heightDiff * 0.2);
    }
    
    // Blend with background
    let bgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let finalColor = mix(bgColor * 0.5, sandColor, newState);
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.85, 1.0, newState);
    
    textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth * (1.0 - newState * 0.2), 0.0, 0.0, 0.0));
}
