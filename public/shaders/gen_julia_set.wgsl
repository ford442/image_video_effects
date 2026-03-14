// ═══════════════════════════════════════════════════════════════
//  Newton Fractal - Basins of Attraction for Polynomial Roots
//  Category: generative
//  Features: procedural, animated, interactive
//
//  Scientific Concept:
//  Newton's method for finding roots: z_{n+1} = z_n - f(z_n)/f'(z_n)
//  For f(z) = z³ - 1, roots are cube roots of unity
//  Each point converges to one of 3 roots forming fractal basins
// ═══════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(7) var dataTextureA : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC : texture_2d<f32>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,         // x=PanX, y=PanY, z=Zoom, w=Power
  ripples: array<vec4<f32>, 50>,
};

// Complex number operations
fn c_mul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn c_div(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let denom = dot(b, b);
    return vec2<f32>(
        (a.x * b.x + a.y * b.y) / denom,
        (a.y * b.x - a.x * b.y) / denom
    );
}

fn c_pow(z: vec2<f32>, n: f32) -> vec2<f32> {
    let r = length(z);
    let theta = atan2(z.y, z.x);
    let new_r = pow(r, n);
    let new_theta = n * theta;
    return vec2<f32>(new_r * cos(new_theta), new_r * sin(new_theta));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x;
    let uv = vec2<f32>(global_id.xy) / resolution;
    
    // Get parameters
    let pan = u.zoom_params.xy;
    let zoom = u.zoom_params.z;
    let power = u.zoom_params.w;
    
    // Default power to 3.0 (z³ - 1) if not set
    let p = select(3.0, power, power > 1.0);
    
    // Map pixel to complex plane with pan and zoom
    let aspect = resolution.x / resolution.y;
    let scale = 2.5 / max(zoom, 0.1);
    var z = (uv - 0.5) * vec2<f32>(scale * aspect, scale) + pan;
    
    // Three roots of unity for z³ - 1 = 0
    let root1 = vec2<f32>(1.0, 0.0);
    let root2 = vec2<f32>(-0.5, 0.86602540378);  // cos(2π/3), sin(2π/3)
    let root3 = vec2<f32>(-0.5, -0.86602540378); // cos(4π/3), sin(4π/3)
    
    // Newton iteration parameters
    let max_iterations = 80;
    let epsilon = 0.0001;
    var iteration = 0;
    var converged_root = 0;
    
    // Newton's method: z_{n+1} = z_n - f(z_n)/f'(z_n)
    // For f(z) = z^p - 1, f'(z) = p * z^(p-1)
    for (iteration = 0; iteration < max_iterations; iteration++) {
        let z_sq = c_mul(z, z);
        let z_cubed = c_mul(z_sq, z);
        
        // f(z) = z³ - 1 (or z^p - 1 for generalized Newton fractal)
        let fz = z_cubed - vec2<f32>(1.0, 0.0);
        
        // f'(z) = 3z² (or p * z^(p-1) for generalized)
        let fpz = 3.0 * z_sq;
        
        // Newton step
        let new_z = z - c_div(fz, fpz);
        
        // Check for convergence
        let diff = length(new_z - z);
        
        // Check which root we converged to
        if (diff < epsilon) {
            let d1 = length(new_z - root1);
            let d2 = length(new_z - root2);
            let d3 = length(new_z - root3);
            
            if (d1 < epsilon) {
                converged_root = 1;
            } else if (d2 < epsilon) {
                converged_root = 2;
            } else if (d3 < epsilon) {
                converged_root = 3;
            }
            break;
        }
        
        z = new_z;
    }
    
    // Color by root and iteration count
    // Root 1: Red/Magenta, Root 2: Green/Yellow, Root 3: Blue/Cyan
    var color: vec3<f32>;
    let t = f32(iteration) / f32(max_iterations);
    let smooth_factor = 1.0 - t;
    
    switch (converged_root) {
        case 1: {
            // Root 1: Red/Magenta with iteration shading
            color = mix(
                vec3<f32>(0.8, 0.0, 0.2),
                vec3<f32>(1.0, 0.3, 0.6),
                smooth_factor
            );
        }
        case 2: {
            // Root 2: Green/Yellow with iteration shading
            color = mix(
                vec3<f32>(0.0, 0.7, 0.2),
                vec3<f32>(0.8, 1.0, 0.2),
                smooth_factor
            );
        }
        case 3: {
            // Root 3: Blue/Cyan with iteration shading
            color = mix(
                vec3<f32>(0.0, 0.3, 0.8),
                vec3<f32>(0.3, 0.9, 1.0),
                smooth_factor
            );
        }
        default: {
            // Did not converge (boundary region) - White/Gold glow
            color = mix(
                vec3<f32>(1.0, 1.0, 0.95),
                vec3<f32>(1.0, 0.8, 0.3),
                sin(time * 2.0) * 0.3 + 0.5
            );
        }
    }
    
    // Add subtle animation glow near boundaries
    let boundary_glow = exp(-f32(iteration) * 0.1);
    color += vec3<f32>(0.3, 0.25, 0.2) * boundary_glow * 0.5;
    
    // Store final color
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    
    // Store iteration data and convergence info
    textureStore(dataTextureA, global_id.xy, vec4<f32>(
        f32(converged_root) / 3.0,
        f32(iteration) / f32(max_iterations),
        boundary_glow,
        1.0
    ));
}
