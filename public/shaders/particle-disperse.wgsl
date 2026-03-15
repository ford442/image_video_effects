// ═══════════════════════════════════════════════════════════════
//  Particle Disperse with Alpha Scattering
//  Wind-force particle dispersion with physical light simulation
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

// Soft particle alpha calculation
fn softParticleAlpha(dist: f32, radius: f32) -> f32 {
    return 1.0 - smoothstep(0.0, radius, dist);
}

// Exponential transmittance for cumulative density
fn transmittance(density: f32) -> f32 {
    return exp(-density);
}

// Motion blur kernel based on velocity
fn motionBlurKernel(vel: vec2<f32>, sample_pos: vec2<f32>, pixel_pos: vec2<f32>) -> f32 {
    let vel_len = length(vel);
    if (vel_len < 0.001) {
        return 1.0;
    }
    
    let vel_dir = vel / vel_len;
    let to_pixel = pixel_pos - sample_pos;
    let along_motion = dot(to_pixel, vel_dir);
    let perp_motion = length(to_pixel - vel_dir * along_motion);
    
    // Gaussian along motion direction
    let blur_length = vel_len * 20.0;
    let along_factor = exp(-(along_motion * along_motion) / (blur_length * blur_length + 0.001));
    let perp_factor = exp(-(perp_motion * perp_motion) / 0.001);
    
    return along_factor * perp_factor;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let aspect = resolution.x / resolution.y;
    var uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let windForce = mix(0.01, 0.1, u.zoom_params.x);
    let returnSpeed = mix(0.01, 0.2, u.zoom_params.y);
    let damping = mix(0.8, 0.99, u.zoom_params.z);
    let particle_radius = mix(0.05, 0.3, u.zoom_params.w);
    let particle_opacity = mix(0.4, 1.0, u.zoom_params.w);

    var mouse = u.zoom_config.yz;

    // Read state: RG = Offset, BA = Velocity
    let state = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
    var offset = state.xy;
    var vel = state.zw;

    // Calculate current apparent position
    let currentPos = uv + offset;

    // Mouse interaction - repel from mouse position
    let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
    let pos_aspect = vec2<f32>(currentPos.x * aspect, currentPos.y);

    var dist = distance(pos_aspect, mouse_aspect);
    if (dist < 0.001) { dist = 0.001; }

    var force = vec2<f32>(0.0);
    if (dist < particle_radius * 2.0) {
        var dir = normalize(pos_aspect - mouse_aspect);
        let push = (1.0 - dist / (particle_radius * 2.0)) * windForce;
        force = vec2<f32>(dir.x, dir.y) * push;
        force.x = force.x / aspect;
    }

    // Update Velocity
    vel = vel + force;
    
    // Spring force (return to offset 0)
    let spring = -offset * returnSpeed;
    vel = vel + spring;
    
    // Damping
    vel = vel * damping;

    // Update Offset
    offset = offset + vel;

    // Write state
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(offset, vel));

    // Calculate motion blur and alpha
    let speed = length(vel);
    let motion_blur_amount = min(speed * 15.0, 0.8);

    // Sample Image with inverse semi-lagrangian lookup
    let sampleUV = uv - offset;
    
    // Boundary check
    var base_color = vec4<f32>(0.0, 0.0, 0.0, 0.0);
    if (sampleUV.x >= 0.0 && sampleUV.x <= 1.0 && sampleUV.y >= 0.0 && sampleUV.y <= 1.0) {
        base_color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    }

    // ═══════════════════════════════════════════════════════════════
    //  ALPHA SCATTERING CALCULATION
    // ═══════════════════════════════════════════════════════════════
    
    // Calculate distance from particle center for soft alpha
    let pixel_to_center = uv - currentPos;
    let pixel_dist = length(vec2<f32>(pixel_to_center.x * aspect, pixel_to_center.y));
    
    // Soft particle alpha
    let soft_alpha = softParticleAlpha(pixel_dist, particle_radius);
    
    // Motion blur affects alpha - faster = more spread = lower peak alpha
    let blur_alpha = soft_alpha * (1.0 - motion_blur_amount * 0.5);
    
    // Final alpha with opacity multiplier
    let alpha = blur_alpha * particle_opacity;
    
    // HDR emission based on displacement speed
    // Faster particles emit more light
    let emission = 1.0 + speed * 3.0;
    var hdr_rgb = base_color.rgb * emission;
    
    // Add velocity-colored streaks
    let velocity_color = vec3<f32>(
        0.5 + vel.x * 2.0,
        0.5 + vel.y * 2.0,
        0.5 + speed
    );
    hdr_rgb += velocity_color * motion_blur_amount * 0.3;
    
    // Cumulative density using exponential transmittance
    // Simulates many overlapping small particles
    let particle_density = alpha * length(base_color.rgb + 0.1);
    let trans = transmittance(particle_density * 2.0);
    let cumulative_alpha = 1.0 - trans;
    
    // Apply motion blur to alpha
    let final_alpha = cumulative_alpha * (1.0 - motion_blur_amount * 0.3);

    // Output RGBA
    let output_color = vec4<f32>(hdr_rgb, clamp(final_alpha, 0.0, 1.0));

    textureStore(writeTexture, vec2<i32>(global_id.xy), output_color);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
