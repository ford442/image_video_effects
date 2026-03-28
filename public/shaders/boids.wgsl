// ═══════════════════════════════════════════════════════════════
//  Boids Swarm with Alpha Scattering
//  GPU-based flocking with physical light simulation
//  
//  Scientific Concepts:
//  - Particles have physical size and opacity
//  - Many small particles = cumulative alpha
//  - Scattering affects perceived transparency
//  - Motion blur affects alpha accumulation
// ═══════════════════════════════════════════════════════════════

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

const BOID_COUNT: u32 = 8192u;
const BOID_SPEED: f32 = 2.0;

// Soft particle alpha based on distance
fn softParticleAlpha(dist: f32, radius: f32) -> f32 {
    // Gaussian-like falloff for soft particles
    let normalized_dist = dist / radius;
    return exp(-normalized_dist * normalized_dist * 2.0);
}

// Exponential transmittance for cumulative density
fn transmittance(density: f32) -> f32 {
    return exp(-density);
}

// HDR tone mapping helper
fn toneMap(hdr: vec3<f32>) -> vec3<f32> {
    // Reinhard tone mapping
    return hdr / (1.0 + hdr);
}

@compute @workgroup_size(64, 1, 1)
fn update_boids(@builtin(global_invocation_id) gid: vec3<u32>) {
    let idx = gid.x;
    if (idx >= BOID_COUNT) { return; }
    var base = idx * 4u;
    let px = extraBuffer[base + 0u];
    let py = extraBuffer[base + 1u];
    var vx = extraBuffer[base + 2u];
    var vy = extraBuffer[base + 3u];
    var pos = vec2<f32>(px, py);
    let tex_size = vec2<f32>(textureDimensions(readTexture));
    let brightness = textureSampleLevel(readTexture, u_sampler, pos / tex_size, 0.0).r;
    let time = u.config.x;
    
    // Mouse position as attractor
    let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let to_mouse = mouse_pos - pos;
    let dist_to_mouse = length(to_mouse);
    if (dist_to_mouse > 0.01) {
        let mouse_force = normalize(to_mouse) * 0.05;
        vx += mouse_force.x;
        vy += mouse_force.y;
    }
    
    // Ripples as attractor seeds
    for (var i = 0; i < 50; i++) {
        let ripple = u.ripples[i];
        if (ripple.z > 0.0) {
            let ripple_age = time - ripple.z;
            if (ripple_age > 0.0 && ripple_age < 4.0) {
                let to_ripple = ripple.xy - pos;
                let dist_to_ripple = length(to_ripple);
                if (dist_to_ripple > 0.01 && dist_to_ripple < 0.3) {
                    let ripple_force = normalize(to_ripple) * 0.02 * (1.0 - ripple_age / 4.0);
                    vx += ripple_force.x;
                    vy += ripple_force.y;
                }
            }
        }
    }
    
    // Simple move towards brighter areas
    if (brightness > 0.5) { vx += 0.01; vy += 0.01; }
    var vel = normalize(vec2<f32>(vx, vy)) * BOID_SPEED;
    var new_pos = pos + vel;
    new_pos = fract(new_pos);
    extraBuffer[base + 0u] = new_pos.x;
    extraBuffer[base + 1u] = new_pos.y;
    extraBuffer[base + 2u] = vel.x;
    extraBuffer[base + 3u] = vel.y;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let coord = vec2<u32>(gid.xy);
    let dim = textureDimensions(readTexture);
    let tex_size = vec2<f32>(dim);
    let time = u.config.x;
    
    // Accumulate particle density and color
    var accumulated_color = vec3<f32>(0.0);
    var accumulated_density: f32 = 0.0;
    var total_energy: f32 = 0.0;
    
    // Particle parameters
    let particle_radius = 3.0 + u.zoom_params.x * 5.0;
    let particle_opacity = 0.6 + u.zoom_params.y * 0.4;
    let glow_intensity = 0.5 + u.zoom_params.z * 1.5;
    
    // Sample boids for rendering
    for (var i: u32 = 0u; i < 2048u; i = i + 1u) {
        var base = i * 4u;
        let bx = extraBuffer[base + 0u] * f32(dim.x);
        let by = extraBuffer[base + 1u] * f32(dim.y);
        let bvx = extraBuffer[base + 2u];
        let bvy = extraBuffer[base + 3u];
        
        let boid_pos = vec2<f32>(bx, by);
        let vel = vec2<f32>(bvx, bvy);
        let pixel_pos = vec2<f32>(f32(coord.x), f32(coord.y));
        
        // Distance to boid
        let dist = distance(pixel_pos, boid_pos);
        
        if (dist < particle_radius * 3.0) {
            // Speed for motion blur and emission
            let speed = length(vel);
            
            // Soft particle alpha
            let soft_alpha = softParticleAlpha(dist, particle_radius);
            
            // Motion blur stretches particle along velocity
            let vel_dir = normalize(vel + vec2<f32>(0.001, 0.001));
            let to_pixel = pixel_pos - boid_pos;
            let along_vel = dot(to_pixel, vel_dir);
            let perp_vel = length(to_pixel - vel_dir * along_vel);
            
            // Elongated particle shape for motion blur
            let blur_length = 1.0 + speed * 5.0;
            let blur_alpha = soft_alpha * exp(-(perp_vel * perp_vel) / (particle_radius * 0.5));
            
            // Boid color based on velocity direction
            let velocity_hue = atan2(vel.y, vel.x) / 6.28318530718 + 0.5;
            let boid_color = vec3<f32>(
                0.5 + 0.5 * cos(velocity_hue * 6.28318530718),
                0.5 + 0.5 * cos(velocity_hue * 6.28318530718 + 2.094),
                0.5 + 0.5 * cos(velocity_hue * 6.28318530718 + 4.189)
            );
            
            // HDR emission based on speed
            let emission = 1.0 + speed * glow_intensity;
            let hdr_color = boid_color * emission;
            
            // Accumulate with alpha
            let alpha = blur_alpha * particle_opacity;
            accumulated_color += hdr_color * alpha;
            accumulated_density += alpha;
            total_energy += alpha * emission;
        }
    }
    
    // Tone mapping
    accumulated_color = toneMap(accumulated_color * 0.5);
    
    // Cumulative alpha using exponential transmittance
    // More particles = higher density = lower transmittance
    let trans = transmittance(accumulated_density * 0.1);
    let final_alpha = 1.0 - trans;
    
    // Boost alpha with energy for glowing effect
    let energy_boost = min(total_energy * 0.01, 0.5);
    let final_alpha_boosted = min(final_alpha + energy_boost, 1.0);
    
    // Sample background with inverse alpha
    let bg_color = textureLoad(readTexture, vec2<i32>(i32(coord.x), i32(coord.y)), 0).rgb;
    let final_color = mix(bg_color * 0.1, accumulated_color, final_alpha_boosted);
    
    let output = vec4<f32>(final_color, final_alpha_boosted);
    textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), output);
}
