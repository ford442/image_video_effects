// ═══════════════════════════════════════════════════════════════════
//  Hyperbolic Crystal Symbiosis
//  Category: generative
//  Features: hyperbolic-geometry, competing-growth, audio-competition, mouse-curvature, crystalline
//  Complexity: High
//  Chunks From: hyperbolic tiling techniques + competing growth models
//  Created: 2026-05-31
//  By: Grok (creative technical artist)
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
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.35;
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    // Mouse controls curvature center
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Hyperbolic projection (Poincaré disk approximation)
    let distFromCenter = length(uv - 0.5);
    let curvature = 1.8 + u.zoom_params.x * 3.5;
    
    // Two competing crystal species
    let seed1 = vec2<f32>(0.3, 0.4);
    let seed2 = vec2<f32>(0.7, 0.6);
    
    // Distance in hyperbolic space
    let d1 = length(uv - seed1) * curvature;
    let d2 = length(uv - seed2) * curvature;
    
    // Growth with audio seasons
    let seasonCoop = mids * 0.7;      // Mids encourage cooperation
    let seasonCompete = bass * 0.65;  // Bass increases competition
    
    let growth1 = sin(d1 * 7.0 - time * (1.2 + seasonCoop)) * 0.5 + 0.5;
    let growth2 = sin(d2 * 6.5 + time * (1.4 + seasonCompete)) * 0.5 + 0.5;
    
    // Competition / Symbiosis
    let competition = abs(growth1 - growth2) * seasonCompete;
    let symbiosis = (1.0 - abs(growth1 - growth2)) * seasonCoop;
    
    let crystal1 = growth1 * (1.0 - competition * 0.4) + symbiosis * 0.3;
    let crystal2 = growth2 * (1.0 - competition * 0.4) + symbiosis * 0.3;
    
    // Mouse influence
    let mouseEffect = smoothstep(0.3, 0.05, length(uv - mouse)) * mouseDown * 1.8;
    let final1 = clamp(crystal1 + mouseEffect * 0.4, 0.0, 1.6);
    let final2 = clamp(crystal2 - mouseEffect * 0.3, 0.0, 1.6);
    
    // Store state
    textureStore(dataTextureA, gid.xy, vec4<f32>(final1, final2, 0.0, 0.0));
    
    // Visualization
    let c1 = vec3<f32>(0.2, 0.7, 0.9) * final1;
    let c2 = vec3<f32>(0.9, 0.5, 0.2) * final2;
    
    let col = c1 + c2;
    
    // Edge highlighting between species
    let edge = abs(final1 - final2);
    let finalCol = col + vec3<f32>(1.0, 0.95, 0.8) * edge * 0.6;
    
    // Alpha based on combined crystal density
    let density = final1 * 0.6 + final2 * 0.6;
    let alpha = clamp(density * 0.9 + edge * 0.4, 0.1, 1.2);
    
    let a = clamp(alpha, 0.0, 1.0);
    textureStore(writeTexture, gid.xy, vec4<f32>(finalCol * a, a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(density * 0.7, 0.0, 0.0, 0.0));
}