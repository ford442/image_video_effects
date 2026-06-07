// ═══════════════════════════════════════════════════════════════════
//  Sim: Decay System
//  Category: artistic
//  Features: simulation, cellular-automata, corrosion, layered-materials
//  Complexity: Medium
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Multi-layer decay and corrosion simulation
//  Decay progresses from edges inward, different materials decay differently
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

// Edge detection
fn detectEdges(uv: vec2<f32>, pixel: vec2<f32>) -> f32 {
    let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let right = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let left = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let up = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixel.y), 0.0).rgb;
    let down = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixel.y), 0.0).rgb;
    
    let edgeX = length(right - left);
    let edgeY = length(up - down);
    
    return (edgeX + edgeY) * 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    
    let uv = vec2<f32>(gid.xy) / resolution;
    let pixel = 1.0 / resolution;
    let time = u.config.x;
    
    // Parameters
    let decayRate = mix(0.001, 0.01, u.zoom_params.x);     // x: Decay rate
    let edgeVulnerability = mix(1.0, 5.0, u.zoom_params.y); // y: Edge vulnerability
    let colorShift = u.zoom_params.z;                       // z: Color shift amount
    let recovery = mix(0.0, 0.001, u.zoom_params.w);       // w: Recovery rate
    
    // Read current decay state
    let decayState = textureLoad(dataTextureC, gid.xy, 0).r;
    let materialType = textureLoad(dataTextureC, gid.xy, 0).g; // Different materials
    
    // Detect edges in source image
    let edges = detectEdges(uv, pixel);
    let isEdge = step(0.1, edges);
    
    // Count decayed neighbors (for cellular automata spread)
    var decayedNeighbors = 0.0;
    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            if (x == 0 && y == 0) { continue; }
            let neighborDecay = textureLoad(dataTextureC, vec2<i32>(gid.xy) + vec2<i32>(x, y), 0).r;
            decayedNeighbors += step(0.5, neighborDecay);
        }
    }
    
    // Decay calculation
    var newDecay = decayState;
    
    // Edges decay faster
    let edgeFactor = isEdge * edgeVulnerability;
    
    // Material affects decay rate (different materials in different channels)
    let materialDecayRate = decayRate * (0.5 + materialType * 0.5);
    
    // Apply decay
    newDecay += materialDecayRate * (1.0 + edgeFactor) * (1.0 + decayedNeighbors * 0.1);
    
    // Recovery (can "paint" protection)
    let mousePos = u.zoom_config.yz;
    let mouseDist = length(uv - mousePos);
    let mouseProtection = smoothstep(0.1, 0.0, mouseDist);
    newDecay -= recovery * (1.0 + mouseProtection * 10.0);
    
    // Clamp
    newDecay = clamp(newDecay, 0.0, 1.0);
    
    // Initialize material type from source on first frame
    var newMaterial = materialType;
    if (time < 1.0) {
        let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
        newMaterial = (source.r * 0.3 + source.g * 0.6 + source.b * 0.1);
    }
    
    // Store decay state
    textureStore(dataTextureA, gid.xy, vec4<f32>(newDecay, newMaterial, 0.0, 1.0));
    
    // Render decayed image
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    // Decay stages with color shifts
    let stage1 = baseColor * vec3<f32>(0.9, 0.95, 1.0); // Slightly faded
    let stage2 = baseColor * vec3<f32>(0.7, 0.8, 0.9);  // More faded, cooler
    let stage3 = baseColor * vec3<f32>(0.5, 0.6, 0.7);  // Quite degraded
    let stage4 = baseColor * vec3<f32>(0.3, 0.35, 0.4); // Heavily corroded
    let stage5 = vec3<f32>(0.1, 0.12, 0.15);           // Almost gone
    
    var decayedColor = baseColor;
    if (newDecay < 0.2) {
        decayedColor = mix(baseColor, stage1, newDecay * 5.0);
    } else if (newDecay < 0.4) {
        decayedColor = mix(stage1, stage2, (newDecay - 0.2) * 5.0);
    } else if (newDecay < 0.6) {
        decayedColor = mix(stage2, stage3, (newDecay - 0.4) * 5.0);
    } else if (newDecay < 0.8) {
        decayedColor = mix(stage3, stage4, (newDecay - 0.6) * 5.0);
    } else {
        decayedColor = mix(stage4, stage5, (newDecay - 0.8) * 5.0);
    }
    
    // Add rust/corrosion texture in decayed areas
    let rustNoise = hash12(uv * 100.0 + time * 0.01);
    let rust = vec3<f32>(0.6, 0.3, 0.1) * rustNoise * newDecay * (1.0 - newDecay) * 4.0;
    decayedColor += rust * colorShift;
    
    // Add edge corrosion
    let edgeCorrosion = isEdge * newDecay * vec3<f32>(0.2, 0.25, 0.3);
    decayedColor += edgeCorrosion;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.85, 1.0, 1.0 - newDecay * 0.3);
    
    textureStore(writeTexture, gid.xy, vec4<f32>(decayedColor, alpha));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth * (1.0 - newDecay * 0.1), 0.0, 0.0, 0.0));
}
