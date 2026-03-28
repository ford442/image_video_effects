// ═══════════════════════════════════════════════════════════════════
//  Voronoi Crystal - Animated crystal growth using Voronoi diagrams
//  Category: generative
//  Features: procedural, animated, crystal growth simulation
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

// Hash function for pseudo-random values
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// 2D rotation
fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Smooth Voronoi with animated seeds
fn voronoiCrystal(uv: vec2<f32>, t: f32, crystalCount: f32, irregularity: f32) -> vec4<f32> {
    let n = floor(uv * crystalCount);
    let f = fract(uv * crystalCount);
    
    var f1 = 10.0;  // Distance to closest seed
    var f2 = 10.0;  // Distance to second closest
    var cellId = vec2<f32>(0.0);
    var seedPos = vec2<f32>(0.0);
    
    // Search neighborhood
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            let g = vec2<f32>(f32(i), f32(j));
            let cell = n + g;
            
            // Animated seed position with irregularity
            let baseSeed = hash22(cell);
            let anim = vec2<f32>(
                sin(t * 0.3 + baseSeed.x * 6.28) * irregularity,
                cos(t * 0.2 + baseSeed.y * 6.28) * irregularity
            );
            let o = baseSeed + anim;
            
            // Add some rotation based on cell
            let angle = t * 0.1 + baseSeed.x * 3.14;
            let r = g + o - f;
            let rotated = rot2(angle) * r;
            
            // Distance with optional stretching
            let stretch = mix(1.0, 0.5 + baseSeed.y, irregularity);
            let d = length(vec2<f32>(rotated.x, rotated.y / stretch));
            
            if (d < f1) {
                f2 = f1;
                f1 = d;
                cellId = cell;
                seedPos = o;
            } else if (d < f2) {
                f2 = d;
            }
        }
    }
    
    return vec4<f32>(f1, f2, cellId.x + cellId.y * 0.1, hash21(cellId));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.config.x;
    
    // Parameters - safe randomization
    let growthSpeed = mix(0.2, 1.5, u.zoom_params.x);
    let crystalCount = mix(2.0, 20.0, u.zoom_params.y);
    let irregularity = mix(0.0, 0.4, u.zoom_params.z);
    let glowIntensity = mix(0.5, 2.0, u.zoom_params.w);
    
    // Aspect correction
    let aspect = resolution.x / resolution.y;
    var p = uv * vec2<f32>(aspect, 1.0);
    
    // Slow pan
    p = p + vec2<f32>(sin(t * 0.05) * 0.1, cos(t * 0.03) * 0.1);
    
    // Get Voronoi data
    let voro = voronoiCrystal(p, t * growthSpeed, crystalCount, irregularity);
    let f1 = voro.x;
    let f2 = voro.y;
    let cellHash = voro.w;
    
    // Edge detection (facet boundaries)
    let edge = f2 - f1;
    let edgeMask = smoothstep(0.15, 0.0, edge);
    
    // Crystal depth simulation (cell age/size)
    let cellAge = fract(cellHash + t * 0.05);
    let depth = cellAge * 0.5 + 0.5;
    
    // Color palette - icy blues and whites with rainbow iridescence
    let baseHue = cellHash * 0.1 + 0.55; // Blue range
    let iridescence = sin(cellHash * 20.0 + t * 0.5) * 0.1;
    
    var col = vec3<f32>(0.0);
    
    // Base crystal color
    let h = baseHue + iridescence;
    let crystalCol = vec3<f32>(
        0.5 + 0.5 * cos(6.28 * (h + 0.0)),
        0.5 + 0.5 * cos(6.28 * (h + 0.33)),
        0.5 + 0.5 * cos(6.28 * (h + 0.67))
    );
    
    // Darker interior, brighter edges
    let interior = smoothstep(0.0, 0.3, f1);
    col = crystalCol * (0.3 + 0.7 * interior);
    
    // Add edge glow (facets)
    let edgeGlow = vec3<f32>(0.9, 0.95, 1.0) * edgeMask * glowIntensity;
    col = col + edgeGlow;
    
    // Add depth shading
    col = col * (0.7 + 0.3 * depth);
    
    // Internal structure (growth rings)
    let rings = sin(f1 * 20.0 + cellAge * 6.28);
    let ringMask = smoothstep(0.0, 0.1, rings) * smoothstep(0.3, 0.0, f1);
    col = col + crystalCol * ringMask * 0.3;
    
    // Specular highlight at seed center
    let specular = exp(-f1 * 10.0) * (0.5 + 0.5 * sin(t + cellHash * 10.0));
    col = col + vec3<f32>(1.0) * specular * 0.5;
    
    // Frost effect at cell boundaries
    let frost = smoothstep(0.1, 0.0, edge) * smoothstep(0.0, 0.05, f1);
    col = mix(col, vec3<f32>(0.95, 0.98, 1.0), frost * 0.4);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth * 0.5, 0.0, 0.0, 0.0));
}
