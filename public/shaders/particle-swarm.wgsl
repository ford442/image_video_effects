// ═══════════════════════════════════════════════════════════════
//  Particle Swarm with Alpha Scattering
//  Physical light simulation with cumulative particle density
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

// Particle Swarm with Alpha
// Param1: Spring Stiffness (0.01 - 0.2)
// Param2: Mouse Force (0.1 - 2.0)
// Param3: Damping (0.8 - 0.99)
// Param4: Particle Size/Opacity (0.01 - 0.5)

// Soft particle alpha calculation
fn softParticleAlpha(dist: f32, radius: f32, core_size: f32) -> f32 {
    // Core is more opaque, edges fade smoothly
    let core_alpha = 1.0 - smoothstep(0.0, core_size * radius, dist);
    let edge_fade = 1.0 - smoothstep(core_size * radius, radius, dist);
    return core_alpha * 0.8 + edge_fade * 0.2;
}

// Scattering phase function (Henyey-Greenstein approximation)
fn scatteringPhase(cos_theta: f32, g: f32) -> f32 {
    let g2 = g * g;
    let denom = 1.0 + g2 - 2.0 * g * cos_theta;
    return (1.0 - g2) / (4.0 * 3.14159265 * sqrt(denom * denom * denom));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Parameters
    let stiffness = mix(0.01, 0.2, u.zoom_params.x);
    let forceInput = u.zoom_params.y - 0.5;
    let forceMult = forceInput * 0.1;
    let damping = mix(0.80, 0.98, u.zoom_params.z);
    let particle_radius = mix(0.05, 0.4, u.zoom_params.w);
    let particle_opacity = mix(0.3, 1.0, u.zoom_params.w);

    // Read previous state from dataTextureC
    let state = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var offset = state.xy;
    var vel = state.zw;

    // Current position of the "particle" (pixel source)
    let currentPos = uv + offset;

    // Mouse interaction
    var mousePos = u.zoom_config.yz;
    var interaction = vec2<f32>(0.0);

    // Check distance
    let dVec = mousePos - currentPos;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

    if (dist < particle_radius && dist > 0.001) {
        let t = 1.0 - (dist / particle_radius);
        var dir = normalize(dVec);
        interaction = dir * t * forceMult;
    }

    // Spring force (return to origin 0,0)
    let spring = -offset * stiffness;

    // Physics Update
    vel = (vel + interaction + spring) * damping;
    offset = offset + vel;

    // Calculate speed for motion blur
    let speed = length(vel);
    let motion_blur = min(speed * 10.0, 1.0);

    // Write new state
    textureStore(dataTextureA, global_id.xy, vec4<f32>(offset, vel));

    // Sample Image
    let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
    let base_color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // ═══════════════════════════════════════════════════════════════
    //  ALPHA SCATTERING CALCULATION
    // ═══════════════════════════════════════════════════════════════

    // Calculate soft particle alpha based on distance from particle center
    let particle_center = currentPos;
    let pixel_to_center = uv - particle_center;
    let pixel_dist = length(vec2<f32>(pixel_to_center.x * aspect, pixel_to_center.y));
    
    // Soft particle alpha: core more opaque, edges transparent
    let soft_alpha = softParticleAlpha(pixel_dist, particle_radius, 0.3);
    
    // Final alpha includes particle opacity and speed-based motion blur
    let alpha = soft_alpha * particle_opacity * (1.0 + motion_blur * 0.5);
    
    // HDR emission calculation
    // RGB can exceed 1.0 for glow effects
    let emission_strength = 1.0 + speed * 2.0; // Faster particles glow brighter
    var hdr_color = base_color.rgb * emission_strength;
    
    // Add scattering effect based on motion direction
    let velocity_dir = normalize(vel + vec2<f32>(0.001, 0.001));
    let view_dir = vec2<f32>(0.0, 0.0); // Looking straight at screen
    let cos_theta = dot(velocity_dir, view_dir);
    let scatter = scatteringPhase(cos_theta, 0.3) * speed * 0.5;
    hdr_color += vec3<f32>(scatter * 0.3, scatter * 0.5, scatter * 0.7);

    // Cumulative density for overlapping particles
    // Using the exponential transmittance model: T = exp(-density)
    let density = alpha * (1.0 + length(base_color.rgb));
    let transmittance = exp(-density * 0.5);
    let cumulative_alpha = 1.0 - transmittance;

    // Output RGBA with physical light scattering
    let final_color = vec4<f32>(hdr_color, clamp(cumulative_alpha, 0.0, 1.0));

    textureStore(writeTexture, vec2<i32>(global_id.xy), final_color);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
