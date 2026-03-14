// ═══════════════════════════════════════════════════════════════
//  Worley Noise with FBM Layering and Edge Detection
//  Category: generative
//  Features: procedural, animated, organic cellular patterns
//  
//  SCIENTIFIC CONCEPT:
//  - Worley Noise: Based on distance to random feature points
//  - FBM (Fractal Brownian Motion): Sum multiple octaves for detail
//  - Edge Detection: Highlight cell boundaries using F2 - F1
//
//  ARTISTIC VISION:
//  - Organic cellular patterns resembling microscopic tissue or foam
//  - Glowing edges between cells
//  - Depth through parallax-like layering
//  - Animated feature points that slowly drift
// ═══════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

// ═══════════════════════════════════════════════════════════════
//  Hash Functions - Generate pseudo-random values
// ═══════════════════════════════════════════════════════════════

fn hash2(p: vec2<f32>) -> vec2<f32> {
    var h = vec2<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3))
    );
    return fract(sin(h) * 43758.5453);
}

fn hash3(p: vec2<f32>) -> vec3<f32> {
    var h = vec3<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3)),
        dot(p, vec2<f32>(419.2, 371.9))
    );
    return fract(sin(h) * 43758.5453);
}

fn hash1(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// ═══════════════════════════════════════════════════════════════
//  Worley Noise - Calculate F1 (closest) and F2 (2nd closest) distances
// ═══════════════════════════════════════════════════════════════

struct WorleyResult {
    f1: f32,      // Distance to closest feature point
    f2: f32,      // Distance to second closest
    cell_id: vec2<f32>,  // Cell identifier for color variation
};

fn worley_noise(uv: vec2<f32>, scale: f32, time: f32, drift_speed: f32) -> WorleyResult {
    // Scale coordinates into grid space
    let st = uv * scale;
    let cell = floor(st);
    let frac = fract(st);
    
    var f1 = 1e10;
    var f2 = 1e10;
    var cell_id = vec2<f32>(0.0);
    
    // Search neighboring cells (3x3 grid)
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let current_cell = cell + neighbor;
            
            // Generate feature point within this cell with time-based drift
            let hash_val = hash2(current_cell);
            let drift = vec2<f32>(
                sin(time * drift_speed + hash_val.x * 6.28),
                cos(time * drift_speed + hash_val.y * 6.28)
            ) * 0.3; // Drift amplitude
            
            let feature_point = neighbor + hash_val + drift;
            let diff = feature_point - frac;
            let dist = length(diff);
            
            // Update F1 and F2
            if dist < f1 {
                f2 = f1;
                f1 = dist;
                cell_id = hash_val;
            } else if dist < f2 {
                f2 = dist;
            }
        }
    }
    
    return WorleyResult(f1, f2, cell_id);
}

// ═══════════════════════════════════════════════════════════════
//  FBM (Fractal Brownian Motion) - Layer multiple octaves
// ═══════════════════════════════════════════════════════════════

fn fbm_worley(uv: vec2<f32>, time: f32, base_scale: f32, octaves: i32) -> vec3<f32> {
    var total_f1: f32 = 0.0;
    var total_f2: f32 = 0.0;
    var amplitude: f32 = 1.0;
    var frequency: f32 = 1.0;
    var max_value: f32 = 0.0;
    var cell_color = vec3<f32>(0.0);
    
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        let worley = worley_noise(uv, base_scale * frequency, time, 0.5 + f32(i) * 0.2);
        
        total_f1 = total_f1 + worley.f1 * amplitude;
        total_f2 = total_f2 + worley.f2 * amplitude;
        max_value = max_value + amplitude;
        
        // Accumulate cell colors weighted by amplitude
        cell_color = cell_color + hash3(worley.cell_id + f32(i)) * amplitude;
        
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    
    // Normalize
    total_f1 = total_f1 / max_value;
    total_f2 = total_f2 / max_value;
    cell_color = cell_color / max_value;
    
    // Edge value: F2 - F1 (0 at cell center, higher at edges)
    let edge_value = total_f2 - total_f1;
    
    return vec3<f32>(total_f1, total_f2, edge_value);
}

// ═══════════════════════════════════════════════════════════════
//  Color Palette - Organic tissue/foam colors
// ═══════════════════════════════════════════════════════════════

fn get_inner_color(cell_hash: vec2<f32>) -> vec3<f32> {
    // Organic tissue colors
    let palette = array<vec3<f32>, 5>(
        vec3<f32>(0.15, 0.08, 0.12),  // Deep burgundy
        vec3<f32>(0.08, 0.15, 0.10),  // Forest shadow
        vec3<f32>(0.12, 0.10, 0.18),  // Deep purple
        vec3<f32>(0.18, 0.12, 0.08),  // Rust brown
        vec3<f32>(0.10, 0.12, 0.15)   // Deep teal
    );
    
    let idx = i32(cell_hash.x * 4.99);
    return palette[idx];
}

fn get_edge_color(cell_hash: vec2<f32>, time: f32) -> vec3<f32> {
    // Glowing edge colors
    let glow = 0.5 + 0.5 * sin(time * 0.5 + cell_hash.y * 6.28);
    
    let palette = array<vec3<f32>, 4>(
        vec3<f32>(0.9, 0.3, 0.5),   // Neon pink
        vec3<f32>(0.3, 0.8, 0.6),   // Electric mint
        vec3<f32>(0.6, 0.4, 0.9),   // Lavender glow
        vec3<f32>(0.9, 0.7, 0.3)    // Golden amber
    );
    
    let idx = i32(cell_hash.x * 3.99);
    return palette[idx] * (0.7 + glow * 0.3);
}

// ═══════════════════════════════════════════════════════════════
//  Main
// ═══════════════════════════════════════════════════════════════

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters from zoom_params
    let cell_density = u.zoom_params.x;      // Controls scale (0.1 to 2.0)
    let edge_intensity = u.zoom_params.y;    // Controls edge glow (0.0 to 1.0)
    let color_shift = u.zoom_params.z;       // Color variation (0.0 to 1.0)
    let parallax = u.zoom_params.w;          // Layer movement (0.0 to 1.0)
    
    // Default values if parameters not set
    let density = mix(3.0, 12.0, cell_density);
    let edges = mix(0.3, 1.5, edge_intensity);
    
    // Layer 1: Base organic pattern (slow drift)
    let uv1 = uv + vec2<f32>(sin(time * 0.05), cos(time * 0.03)) * parallax * 0.02;
    let worley1 = fbm_worley(uv1, time * 0.1, density, 3);
    
    // Layer 2: Mid detail (opposite drift)
    let uv2 = uv - vec2<f32>(sin(time * 0.07), cos(time * 0.05)) * parallax * 0.03;
    let worley2 = fbm_worley(uv2, time * 0.15 + 100.0, density * 1.5, 2);
    
    // Layer 3: Fine detail (faster drift)
    let uv3 = uv + vec2<f32>(cos(time * 0.1), sin(time * 0.08)) * parallax * 0.01;
    let worley3 = fbm_worley(uv3, time * 0.2 + 200.0, density * 3.0, 2);
    
    // Combine layers with FBM weighting
    let combined_f1 = worley1.x * 0.5 + worley2.x * 0.3 + worley3.x * 0.2;
    let combined_f2 = worley1.y * 0.5 + worley2.y * 0.3 + worley3.y * 0.2;
    let combined_edge = worley1.z * 0.5 + worley2.z * 0.3 + worley3.z * 0.2;
    
    // Edge detection: F2 - F1
    let edge_value = combined_edge * edges;
    
    // Generate cell-based colors
    let cell_hash = hash2(floor(uv * density));
    let inner_color = get_inner_color(cell_hash + color_shift);
    let edge_color = get_edge_color(cell_hash + color_shift, time);
    
    // Depth-based shading (darker in cell centers, brighter at edges)
    let depth_shading = 1.0 - combined_f1 * 0.5;
    
    // Final color mixing: inner color with glowing edges
    let edge_mask = smoothstep(0.0, 0.15, edge_value);
    var final_color = mix(inner_color * depth_shading, edge_color, edge_mask);
    
    // Add subtle volumetric glow at edges
    let glow = pow(edge_value, 2.0) * edge_intensity * 0.5;
    final_color = final_color + edge_color * glow;
    
    // Subtle vignette
    let vignette = 1.0 - length((uv - 0.5) * 1.2);
    final_color = final_color * smoothstep(0.0, 0.7, vignette);
    
    // Output color
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_color, 1.0));
    
    // Output depth based on cell structure for parallax feel
    let depth = 1.0 - combined_f1 * 0.8 + edge_value * 0.2;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
