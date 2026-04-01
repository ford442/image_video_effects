// ═══════════════════════════════════════════════════════════════════
//  Worley Noise with FBM Layering and Edge Detection
//  Category: generative
//  Features: upgraded-rgba, depth-aware, procedural, animated, organic-cellular
//  Scientific: Worley Noise - based on distance to random feature points
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

// Hash Functions
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

// Worley Noise Result
struct WorleyResult {
    f1: f32,
    f2: f32,
    cell_id: vec2<f32>,
};

// Worley Noise
fn worley_noise(uv: vec2<f32>, scale: f32, time: f32, drift_speed: f32) -> WorleyResult {
    let st = uv * scale;
    let cell = floor(st);
    let frac = fract(st);
    
    var f1 = 1e10;
    var f2 = 1e10;
    var cell_id = vec2<f32>(0.0);
    
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let current_cell = cell + neighbor;
            let hash_val = hash2(current_cell);
            let drift = vec2<f32>(
                sin(time * drift_speed + hash_val.x * 6.28),
                cos(time * drift_speed + hash_val.y * 6.28)
            ) * 0.3;
            let feature_point = neighbor + hash_val + drift;
            let diff = feature_point - frac;
            let dist = length(diff);
            
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

// FBM Worley
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
        cell_color = cell_color + hash3(worley.cell_id + f32(i)) * amplitude;
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    
    total_f1 = total_f1 / max_value;
    total_f2 = total_f2 / max_value;
    cell_color = cell_color / max_value;
    let edge_value = total_f2 - total_f1;
    return vec3<f32>(total_f1, total_f2, edge_value);
}

// Color Palettes
fn get_inner_color(cell_hash: vec2<f32>) -> vec3<f32> {
    let palette = array<vec3<f32>, 5>(
        vec3<f32>(0.15, 0.08, 0.12),
        vec3<f32>(0.08, 0.15, 0.10),
        vec3<f32>(0.12, 0.10, 0.18),
        vec3<f32>(0.18, 0.12, 0.08),
        vec3<f32>(0.10, 0.12, 0.15)
    );
    let idx = i32(cell_hash.x * 4.99);
    return palette[idx];
}

fn get_edge_color(cell_hash: vec2<f32>, time: f32) -> vec3<f32> {
    let glow = 0.5 + 0.5 * sin(time * 0.5 + cell_hash.y * 6.28);
    let palette = array<vec3<f32>, 4>(
        vec3<f32>(0.9, 0.3, 0.5),
        vec3<f32>(0.3, 0.8, 0.6),
        vec3<f32>(0.6, 0.4, 0.9),
        vec3<f32>(0.9, 0.7, 0.3)
    );
    let idx = i32(cell_hash.x * 3.99);
    return palette[idx] * (0.7 + glow * 0.3);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;
    
    // Parameters
    let cell_density = u.zoom_params.x;
    let edge_intensity = u.zoom_params.y;
    let color_shift = u.zoom_params.z;
    let parallax = u.zoom_params.w;
    
    let density = mix(3.0, 12.0, cell_density);
    let edges = mix(0.3, 1.5, edge_intensity);
    
    // Layer 1: Base organic pattern
    let uv1 = uv + vec2<f32>(sin(time * 0.05), cos(time * 0.03)) * parallax * 0.02;
    let worley1 = fbm_worley(uv1, time * 0.1, density, 3);
    
    // Layer 2: Mid detail
    let uv2 = uv - vec2<f32>(sin(time * 0.07), cos(time * 0.05)) * parallax * 0.03;
    let worley2 = fbm_worley(uv2, time * 0.15 + 100.0, density * 1.5, 2);
    
    // Layer 3: Fine detail
    let uv3 = uv + vec2<f32>(cos(time * 0.1), sin(time * 0.08)) * parallax * 0.01;
    let worley3 = fbm_worley(uv3, time * 0.2 + 200.0, density * 3.0, 2);
    
    // Combine layers
    let combined_f1 = worley1.x * 0.5 + worley2.x * 0.3 + worley3.x * 0.2;
    let combined_f2 = worley1.y * 0.5 + worley2.y * 0.3 + worley3.y * 0.2;
    let combined_edge = worley1.z * 0.5 + worley2.z * 0.3 + worley3.z * 0.2;
    
    let edge_value = combined_edge * edges;
    let cell_hash = hash2(floor(uv * density));
    let inner_color = get_inner_color(cell_hash + color_shift);
    let edge_color = get_edge_color(cell_hash + color_shift, time);
    let depth_shading = 1.0 - combined_f1 * 0.5;
    
    let edge_mask = smoothstep(0.0, 0.15, edge_value);
    var final_color = mix(inner_color * depth_shading, edge_color, edge_mask);
    let glow = pow(edge_value, 2.0) * edge_intensity * 0.5;
    final_color = final_color + edge_color * glow;
    
    // Vignette
    let vignette = 1.0 - length((uv - 0.5) * 1.2);
    final_color = final_color * smoothstep(0.0, 0.7, vignette);
    
    // ═══ SAMPLE INPUT FROM PREVIOUS LAYER ═══
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Opacity control
    let opacity = 0.9;
    
    // Calculate alpha
    let luma = dot(final_color, vec3<f32>(0.299, 0.587, 0.114));
    let edgeAlpha = mix(0.6, 1.0, edge_mask);
    let generatedAlpha = edgeAlpha;
    
    // Blend with input
    let finalColor = mix(inputColor.rgb, final_color, generatedAlpha * opacity);
    let finalAlpha = max(inputColor.a, generatedAlpha * opacity);
    
    // Output RGBA
    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    
    // Output depth
    let depth_out = mix(inputDepth, 1.0 - combined_f1 * 0.8 + edge_value * 0.2, generatedAlpha * opacity);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth_out, 0.0, 0.0, 0.0));
}
