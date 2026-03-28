// ═══════════════════════════════════════════════════════════════════
//  Quasicrystal - Penrose tiling-inspired patterns with 5-fold symmetry
//  Category: generative
//  Features: procedural, aperiodic tiling, projection method
//  Created: 2026-03-22
//  By: Agent 4A
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

// Quasicrystal pattern using the projection method
// A 5D lattice is projected onto 2D to create the pattern
fn quasicrystal(uv: vec2<f32>, n: i32, t: f32, angle: f32) -> f32 {
    var value = 0.0;
    let pi = 3.14159265359;
    
    // Sum of waves at angles determined by symmetry
    for (var i: i32 = 0; i < n; i++) {
        let theta = angle + pi * 2.0 * f32(i) / f32(n);
        let k = vec2<f32>(cos(theta), sin(theta));
        value += cos(dot(uv, k) * 10.0 + t);
    }
    
    return value / f32(n);
}

// Rhombus tiling based on quasicrystal
fn rhombusPattern(uv: vec2<f32>, n: i32, t: f32, angle: f32) -> vec2<f32> {
    let qc = quasicrystal(uv, n, t, angle);
    let qc2 = quasicrystal(uv + vec2<f32>(0.1), n, t, angle + 0.1);
    
    // Create tiling pattern
    let phase1 = fract(qc * 2.0);
    let phase2 = fract(qc2 * 2.0);
    
    return vec2<f32>(phase1, phase2);
}

// Metallic gradient
fn metallicColor(uv: vec2<f32>, pattern: f32, t: f32) -> vec3<f32> {
    // Gold and silver base
    let gold = vec3<f32>(1.0, 0.84, 0.0);
    let silver = vec3<f32>(0.75, 0.75, 0.75);
    let bronze = vec3<f32>(0.8, 0.5, 0.2);
    
    // Gradient based on pattern
    let m = fract(pattern + t * 0.05);
    
    var col = vec3<f32>(0.0);
    if (m < 0.33) {
        col = mix(gold, silver, m * 3.0);
    } else if (m < 0.66) {
        col = mix(silver, bronze, (m - 0.33) * 3.0);
    } else {
        col = mix(bronze, gold, (m - 0.66) * 3.0);
    }
    
    return col;
}

// Gem accent color
fn gemColor(idx: i32, t: f32) -> vec3<f32> {
    let gems = array<vec3<f32>, 5>(
        vec3<f32>(0.9, 0.1, 0.2), // Ruby
        vec3<f32>(0.1, 0.6, 0.9), // Sapphire
        vec3<f32>(0.1, 0.8, 0.3), // Emerald
        vec3<f32>(0.9, 0.5, 0.1), // Amber
        vec3<f32>(0.7, 0.2, 0.8)  // Amethyst
    );
    return gems[idx % 5];
}

// 2D rotation
fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.config.x;
    
    // Parameters - safe randomization
    let symmetry = i32(mix(5.0, 13.0, u.zoom_params.x)); // 5, 7, 9, 11, 13
    let patternDensity = mix(3.0, 15.0, u.zoom_params.y);
    let colorCycle = u.zoom_params.z;
    let projAngle = mix(0.0, 6.28318, u.zoom_params.w);
    
    // Aspect correction
    let aspect = resolution.x / resolution.y;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * patternDensity;
    
    // Slow rotation to reveal symmetries
    let rotSpeed = 0.05;
    p = rot2(t * rotSpeed + projAngle) * p;
    
    // Generate quasicrystal pattern
    let qc = quasicrystal(p, symmetry, t * 0.2, projAngle);
    
    // Create rhombus tiling pattern
    let threshold = 0.2;
    let pattern = smoothstep(-threshold, threshold, qc);
    
    // Second layer for detail
    let qc2 = quasicrystal(p * 1.5 + 0.5, symmetry, t * 0.15, projAngle + 0.1);
    let pattern2 = smoothstep(-threshold * 0.5, threshold * 0.5, qc2);
    
    // Metallic base color
    var col = metallicColor(p, qc + qc2, t * colorCycle);
    
    // Add gem accents at specific pattern locations
    let gemLocations = fract(qc * 5.0 + qc2 * 3.0);
    let gemMask = smoothstep(0.48, 0.5, gemLocations) * smoothstep(0.52, 0.5, gemLocations);
    
    let gemIdx = i32(fract(qc * 10.0) * 5.0);
    let gemAccent = gemColor(gemIdx, t) * gemMask;
    col = mix(col, gemAccent, gemMask * 0.6);
    
    // Highlight rhombus edges
    let edge = abs(qc);
    let edgeMask = smoothstep(0.05, 0.0, edge);
    col = col + vec3<f32>(1.0, 0.95, 0.8) * edgeMask * 0.4;
    
    // Add subtle shimmer
    let shimmer = sin(p.x * 20.0 + t) * sin(p.y * 20.0 + t * 1.3);
    col = col + vec3<f32>(0.1) * shimmer * 0.05;
    
    // Depth variation based on pattern
    let depth = pattern * 0.5 + pattern2 * 0.3;
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    col *= vignette;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
