// ═══════════════════════════════════════════════════════════════
//  Infinite Zoom with Möbius Transformations and Alpha Physics
//  Category: distortion
//  Features: mathematical, escher-like, hyperbolic geometry with physical deformation
// 
//  Möbius transformations: f(z) = (az + b) / (cz + d)
//  Creates conformal mappings of the complex plane for
//  infinite tessellations with self-similar patterns.
//  
//  ALPHA PHYSICS:
//  - Iterative transformations create cumulative distortion
//  - Each iteration affects light path = scattered alpha
//  - Modular form coloring affects per-region opacity
//  - Zoom cycle creates depth-based transparency variations
// ═══════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,        // time, unused, resolutionX, resolutionY
  zoom_config: vec4<f32>,  // zoomTime, zoomCenterX, zoomCenterY, depth_threshold
  zoom_params: vec4<f32>,  // zoom_speed, param_a, rotation, iteration_depth
  lighting_params: vec4<f32>, // light_strength, ambient, normal_strength, color_cycling
};

@group(0) @binding(3) var<uniform> u: Uniforms;

// ═══════════════════════════════════════════════════════════════
// Complex Number Operations
// ═══════════════════════════════════════════════════════════════

fn complex_mul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(
        a.x * b.x - a.y * b.y,
        a.x * b.y + a.y * b.x
    );
}

fn complex_div(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let denom = b.x * b.x + b.y * b.y;
    return vec2<f32>(
        (a.x * b.x + a.y * b.y) / denom,
        (a.y * b.x - a.x * b.y) / denom
    );
}

fn complex_conj(z: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(z.x, -z.y);
}

fn complex_abs(z: vec2<f32>) -> f32 {
    return length(z);
}

fn complex_exp(z: vec2<f32>) -> vec2<f32> {
    let exp_x = exp(z.x);
    return vec2<f32>(exp_x * cos(z.y), exp_x * sin(z.y));
}

fn complex_log(z: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(log(length(z)), atan2(z.y, z.x));
}

fn complex_pow(z: vec2<f32>, n: f32) -> vec2<f32> {
    let r = length(z);
    let theta = atan2(z.y, z.x);
    let rn = pow(r, n);
    return vec2<f32>(rn * cos(n * theta), rn * sin(n * theta));
}

// ═══════════════════════════════════════════════════════════════
// Möbius Transformation
// ═══════════════════════════════════════════════════════════════

fn mobius_transform(z: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, d: vec2<f32>) -> vec2<f32> {
    let numerator = complex_mul(a, z) + b;
    let denominator = complex_mul(c, z) + d;
    return complex_div(numerator, denominator);
}

fn hyperbolic_mobius(z: vec2<f32>, t: f32) -> vec2<f32> {
    let ch = cosh(t);
    let sh = sinh(t);
    let a = vec2<f32>(ch, 0.0);
    let b = vec2<f32>(sh, 0.0);
    let c = vec2<f32>(sh, 0.0);
    let d = vec2<f32>(ch, 0.0);
    return mobius_transform(z, a, b, c, d);
}

// ═══════════════════════════════════════════════════════════════
// Modular Form Coloring
// ═══════════════════════════════════════════════════════════════

fn lattice_modular_value(z: vec2<f32>, omega1: vec2<f32>, omega2: vec2<f32>) -> vec2<f32> {
    let det = omega1.x * omega2.y - omega1.y * omega2.x;
    let m = (z.x * omega2.y - z.y * omega2.x) / det;
    let n = (omega1.x * z.y - omega1.y * z.x) / det;
    return vec2<f32>(fract(m), fract(n));
}

fn modular_j_invariant_approx(z: vec2<f32>) -> f32 {
    let x = z.x;
    let y = z.y;
    let r2 = x * x + y * y;
    return 1728.0 * (4.0 * x * x * x - 3.0 * x * r2) / (r2 * r2 * r2 + 0.001);
}

// ═══════════════════════════════════════════════════════════════
// Utility Functions
// ═══════════════════════════════════════════════════════════════

fn ping_pong(a: f32) -> f32 {
    return 1.0 - abs(fract(a * 0.5) * 2.0 - 1.0);
}

fn hue_to_rgb(h: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(h + k) * 6.0 - 3.0);
    return clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hsb_to_rgb(h: f32, s: f32, b: f32) -> vec3<f32> {
    let rgb = hue_to_rgb(h);
    return b * mix(vec3<f32>(1.0), rgb, s);
}

// ═══════════════════════════════════════════════════════════════
// Alpha Physics for Möbius Transformations
// ═══════════════════════════════════════════════════════════════

fn calculateIterationAlpha(
    baseAlpha: f32,
    iterationCount: i32,
    maxIterations: i32,
    accumulatedScale: f32
) -> f32 {
    // More iterations = more distortion = scattered light
    let iterationFactor = 1.0 - (f32(iterationCount) / f32(maxIterations)) * 0.3;
    
    // Scale affects perceived opacity (zoomed = less detailed = more transparent)
    let scaleFactor = 1.0 / (1.0 + accumulatedScale * 0.1);
    
    return clamp(baseAlpha * iterationFactor * scaleFactor, 0.4, 1.0);
}

fn calculateModularAlpha(
    baseAlpha: f32,
    latticeCoord: vec2<f32>,
    jInvariant: f32
) -> f32 {
    // Lattice position affects opacity (near lattice points = more opaque)
    let distFromLattice = length(latticeCoord - 0.5);
    let latticeAlpha = 0.7 + 0.3 * (1.0 - distFromLattice);
    
    // j-invariant special values create opacity variations
    let jModulation = 1.0 - abs(fract(jInvariant * 0.001) - 0.5) * 0.2;
    
    return clamp(baseAlpha * latticeAlpha * jModulation, 0.5, 1.0);
}

// ═══════════════════════════════════════════════════════════════
// Infinite Zoom with Möbius Iteration and Alpha
// ═══════════════════════════════════════════════════════════════

fn apply_mobius_zoom_alpha(uv: vec2<f32>, zoom_time: f32) -> vec4<f32> {
    let zoom_speed = u.zoom_params.x;
    let param_a = u.zoom_params.y;
    let rotation = u.zoom_params.z;
    let max_iterations = i32(clamp(u.zoom_params.w * 10.0, 1.0, 20.0));
    
    let z0 = (uv - 0.5) * 4.0;
    
    let t = zoom_time * zoom_speed;
    let cycle = fract(t);
    let iteration = floor(t);
    
    let theta = rotation + t * 0.5;
    let a_param = mix(0.1, 0.9, ping_pong(param_a + cycle));
    
    let a = vec2<f32>(cos(theta), sin(theta));
    let b = vec2<f32>(a_param * cos(t * 0.7), a_param * sin(t * 0.7));
    let c = complex_conj(b);
    let d = complex_conj(a);
    
    var z = z0;
    var accumulated_scale = 1.0;
    var totalDistortion = 0.0;
    
    for (var i: i32 = 0; i < max_iterations; i = i + 1) {
        z = mobius_transform(z, a, b, c, d);
        
        let hyper_t = 0.3 * sin(t + f32(i));
        z = hyperbolic_mobius(z, hyper_t);
        
        accumulated_scale = accumulated_scale * (1.0 + 0.1 * sin(t * 2.0 + f32(i)));
        totalDistortion = totalDistortion + 0.05;
        
        if (complex_abs(z) > 10.0) {
            z = z * 0.1;
            break;
        }
    }
    
    let zoom_scale = 1.0 + cycle * 3.0;
    z = z / zoom_scale;
    
    var result = z / 4.0 + 0.5;
    result = fract(result);
    
    // Sample texture
    let tex_color = textureSampleLevel(readTexture, non_filtering_sampler, result, 0.0);
    
    // Calculate modular coloring
    let omega1 = vec2<f32>(1.0, 0.0);
    let omega2 = vec2<f32>(0.5, 0.866025);
    let lattice_coord = lattice_modular_value(z, omega1, omega2);
    let j_val = modular_j_invariant_approx(z * 0.5);
    
    // Calculate alpha with physics
    let iterationAlpha = calculateIterationAlpha(tex_color.a, max_iterations, max_iterations, accumulated_scale);
    let finalAlpha = calculateModularAlpha(iterationAlpha, lattice_coord, j_val);
    
    return vec4<f32>(tex_color.rgb, finalAlpha);
}

// ═══════════════════════════════════════════════════════════════
// Color with Alpha Calculation
// ═══════════════════════════════════════════════════════════════

fn calculate_mobius_color_alpha(uv: vec2<f32>, zoom_time: f32) -> vec4<f32> {
    let zoom_speed = u.zoom_params.x;
    let param_a = u.zoom_params.y;
    let color_cycling = u.lighting_params.w;
    
    let t = zoom_time * zoom_speed;
    
    // Transform UV through Möbius iteration
    let zoomedResult = apply_mobius_zoom_alpha(uv, zoom_time);
    let transformed_uv = fract((uv - 0.5) * 4.0 / (1.0 + cycle * 3.0) / 4.0 + 0.5);
    
    // Sample for color calculation
    let tex_color = textureSampleLevel(readTexture, non_filtering_sampler, transformed_uv, 0.0);
    
    // Modular form coloring
    let z = (transformed_uv - 0.5) * 4.0;
    
    let omega1 = vec2<f32>(1.0, 0.0);
    let omega2 = vec2<f32>(0.5, 0.866025);
    let lattice_coord = lattice_modular_value(z, omega1, omega2);
    
    let j_val = modular_j_invariant_approx(z * 0.5);
    let hue = fract(abs(j_val) * 0.001 + t * color_cycling + length(lattice_coord));
    
    let dist_from_lattice = length(lattice_coord - 0.5);
    let sat = 0.5 + 0.5 * (1.0 - dist_from_lattice);
    
    let luminance = dot(tex_color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let brightness = mix(0.3, 1.0, luminance);
    
    let hsb_color = hsb_to_rgb(hue, sat * 0.8, brightness);
    
    let blend_factor = ping_pong(param_a + 0.3);
    let final_rgb = mix(tex_color.rgb, hsb_color, blend_factor);
    
    // Preserve alpha from zoom calculation
    return vec4<f32>(final_rgb, zoomedResult.a);
}

var<private> cycle: f32;

// ═══════════════════════════════════════════════════════════════
// Main Shader Entry
// ═══════════════════════════════════════════════════════════════

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let zoom_time = u.zoom_config.x;
    
    cycle = fract(zoom_time * u.zoom_params.x);
    
    // Apply Möbius infinite zoom with alpha
    let color = apply_mobius_zoom_alpha(uv, zoom_time);
    
    // Add depth variation
    let t = zoom_time * u.zoom_params.x;
    let depth_variation = 0.5 + 0.5 * sin(cycle * 6.28318);
    
    // Sample depth
    let transformed_uv = fract((uv - 0.5) * 4.0 / (1.0 + cycle * 3.0) / 4.0 + 0.5);
    let base_depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, transformed_uv, 0.0).r;
    let final_depth = mix(base_depth, depth_variation, 0.2);
    
    // Store results with RGBA
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color.rgb, color.a));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(final_depth, 0.0, 0.0, 0.0));
}
