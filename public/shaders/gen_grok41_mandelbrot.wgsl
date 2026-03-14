// ═══════════════════════════════════════════════════════════════
//  Buddhabrot Nebula - Orbit accumulation rendering
//  Based on Melinda Green's Buddhabrot technique (1993)
//  Category: generative
//  Features: procedural, animated accumulation, nebula aesthetic
// ═══════════════════════════════════════════════════════════════
//
// Scientific Concept:
// Buddhabrot renders the density of orbit paths for escaping points,
// creating ghostly Buddha-like figures and nebula patterns.
// Instead of coloring pixels based on iteration count (Mandelbrot),
// we accumulate how often orbit paths pass through each pixel.
//
// Implementation:
// - Monte Carlo sampling of random c values per pixel
// - Orbit path tracking with density accumulation
// - Temporal animation showing pattern emergence
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

// Pseudo-random number generator
fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(p2) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(p3) * 43758.5453);
}

// Complex number operations
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn cadd(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return a + b;
}

// Iterate and return whether point escapes
fn escapes(c: vec2<f32>, max_iter: u32) -> bool {
    var z = vec2<f32>(0.0);
    for (var i: u32 = 0u; i < max_iter; i = i + 1u) {
        z = cmul(z, z) + c;
        if (dot(z, z) > 4.0) {
            return true;
        }
    }
    return false;
}

// Sample random c in view region
fn random_c(uv: vec2<f32>, seed: vec3<f32>, view_center: vec2<f32>, view_scale: f32) -> vec2<f32> {
    let rnd = hash3(seed);
    // Sample in view rectangle
    let c = view_center + (rnd.xy - 0.5) * view_scale * 3.0;
    return c;
}

// Nebula color mapping based on density
fn nebula_color(density: f32, time: f32) -> vec3<f32> {
    // Normalize density for coloring
    let d = clamp(density * 0.5, 0.0, 1.0);
    
    // Create ethereal nebula colors
    // Deep purples, blues, cyan, with hints of gold/pink
    let t = time * 0.1;
    
    // Base nebula palette (deep space)
    let deep_purple = vec3<f32>(0.1, 0.05, 0.2);
    let cosmic_blue = vec3<f32>(0.05, 0.15, 0.35);
    let nebula_cyan = vec3<f32>(0.1, 0.4, 0.5);
    let ethereal_pink = vec3<f32>(0.6, 0.3, 0.5);
    let stellar_gold = vec3<f32>(0.9, 0.7, 0.3);
    let white_core = vec3<f32>(1.0, 0.95, 0.9);
    
    // Multi-octave color mixing for rich nebula effect
    var color = deep_purple;
    
    // Layer colors based on density thresholds
    color = mix(color, cosmic_blue, smoothstep(0.05, 0.15, d));
    color = mix(color, nebula_cyan, smoothstep(0.1, 0.25, d) * (0.8 + 0.2 * sin(t + d * 5.0)));
    color = mix(color, ethereal_pink, smoothstep(0.15, 0.35, d) * (0.6 + 0.4 * cos(t * 0.7 + d * 3.0)));
    color = mix(color, stellar_gold, smoothstep(0.3, 0.6, d) * (0.5 + 0.5 * sin(t * 0.5)));
    color = mix(color, white_core, smoothstep(0.5, 1.0, d));
    
    // Add subtle color variation based on position
    color = color * (0.9 + 0.1 * sin(d * 10.0 + t));
    
    // Glow enhancement for high density
    let glow = pow(d, 2.0) * 0.5;
    color = color + vec3<f32>(glow * 0.5, glow * 0.6, glow * 0.8);
    
    return color;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x;
    let uv = (vec2<f32>(global_id.xy) / resolution - 0.5) * 2.0;
    let aspect = resolution.x / resolution.y;
    
    // View parameters from uniforms
    let zoom_center = vec2<f32>(u.zoom_params.x, u.zoom_params.y);
    let zoom_scale = u.zoom_params.z;
    let evolution_speed = u.zoom_params.w;
    
    // Default view parameters if not provided
    let view_center = select(vec2<f32>(-0.5, 0.0), zoom_center, zoom_center.x != 0.0 || zoom_center.y != 0.0);
    let view_scale = select(1.0, zoom_scale, zoom_scale > 0.0);
    let speed = select(0.5, evolution_speed, evolution_speed > 0.0);
    
    // Animated time for evolution
    let t = time * speed * 0.1;
    
    // Map pixel to complex plane
    let c_pixel = view_center + vec2<f32>(uv.x * aspect, uv.y) * view_scale;
    
    // Buddhabrot accumulation via Monte Carlo sampling
    // For each pixel, sample random c values and accumulate
    // contributions from orbits that pass near this pixel
    var density: f32 = 0.0;
    var sample_count: u32 = 32u; // Number of samples per pixel
    
    // Seed based on pixel position and time for temporal variation
    let pixel_seed = vec2<f32>(f32(global_id.x), f32(global_id.y));
    
    for (var s: u32 = 0u; s < sample_count; s = s + 1u) {
        // Generate random c with time-based variation
        let seed = vec3<f32>(pixel_seed, f32(s) + t * 100.0);
        let c_rand = random_c(uv, seed, view_center, view_scale);
        
        // Check if this c escapes (Buddhabrot only considers escaping orbits)
        if (escapes(c_rand, 64u)) {
            // Now trace the orbit and accumulate density
            var z = vec2<f32>(0.0);
            var orbit_points: array<vec2<f32>, 64>;
            var orbit_len: u32 = 0u;
            
            // Store orbit path
            for (var i: u32 = 0u; i < 64u && orbit_len < 64u; i = i + 1u) {
                z = cmul(z, z) + c_rand;
                if (dot(z, z) > 4.0) {
                    break;
                }
                orbit_points[orbit_len] = z;
                orbit_len = orbit_len + 1u;
            }
            
            // Accumulate density based on proximity to current pixel
            // This is the key Buddhabrot insight: count orbit visits
            for (var i: u32 = 0u; i < orbit_len; i = i + 1u) {
                let orbit_p = orbit_points[i];
                // Distance from orbit point to current pixel
                let dist = length(orbit_p - c_pixel);
                
                // Contribution falls off with distance (soft accumulation)
                let contribution = 1.0 / (1.0 + dist * dist * 1000.0 * view_scale);
                density = density + contribution;
            }
        }
    }
    
    // Temporal evolution: add animated variation to density
    let evolution = sin(t + length(c_pixel) * 3.0) * 0.1 + 1.0;
    density = density * evolution / f32(sample_count);
    
    // Apply tone mapping for better visual range
    density = density * 50.0; // Scale factor
    density = density / (1.0 + density); // Soft clip
    
    // Get nebula color from density
    var color = nebula_color(density, t);
    
    // Add subtle starfield background
    let star_noise = hash3(vec3<f32>(pixel_seed * 0.01, t * 0.01));
    if (star_noise.x > 0.998) {
        let star_brightness = hash2(pixel_seed + vec2<f32>(t)).x;
        color = mix(color, vec3<f32>(1.0), star_brightness * 0.8);
    }
    
    // Subtle vignette
    let vignette = 1.0 - length(uv) * 0.3;
    color = color * vignette;
    
    // Gamma correction
    color = pow(color, vec3<f32>(0.8));
    
    // Output final color
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    
    // Depth output (store density for potential use)
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(density, 0.0, 0.0, 0.0));
}
