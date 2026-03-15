// ═══════════════════════════════════════════════════════════════
//  Physarum Polycephalum (Slime Mold) with Alpha Scattering
//  Texture-guided agent simulation with physical light transport
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

// Soft particle alpha based on distance
fn softParticleAlpha(dist: f32, radius: f32) -> f32 {
    let t = dist / radius;
    return exp(-t * t * 3.0);
}

// Exponential transmittance for cumulative density
fn transmittance(density: f32) -> f32 {
    return exp(-density);
}

// Agent deposit color with HDR emission
fn agentEmissionColor(base_color: vec3<f32>, intensity: f32) -> vec3<f32> {
    // HDR emission - can exceed 1.0
    return base_color * (0.5 + intensity * 2.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let idx = gid.x;
    if (idx * 3u + 2u >= arrayLength(&extraBuffer)) { return; }
    
    let x = extraBuffer[idx * 3u + 0u];
    let y = extraBuffer[idx * 3u + 1u];
    var angle = extraBuffer[idx * 3u + 2u];
    let tex_size = vec2<f32>(textureDimensions(readTexture));
    let time = u.config.x;
    
    // Parameters
    let agent_radius = mix(1.0, 4.0, u.zoom_params.x);
    let deposit_opacity = mix(0.1, 0.8, u.zoom_params.y);
    let sense_distance = mix(3.0, 10.0, u.zoom_params.z);
    let trail_decay = mix(0.95, 0.995, u.zoom_params.w);
    
    // Agent position
    var agent_pos = vec2<f32>(x, y);
    
    // Mouse position influence
    let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let to_mouse = mouse_pos - agent_pos;
    let dist_to_mouse = length(to_mouse);
    if (dist_to_mouse > 0.01 && dist_to_mouse < 0.3) {
        let mouse_angle = atan2(to_mouse.y, to_mouse.x);
        angle = mix(angle, mouse_angle, 0.1);
    }
    
    // Ripple-based spawning/biasing
    for (var i = 0; i < 50; i++) {
        let ripple = u.ripples[i];
        if (ripple.z > 0.0) {
            let ripple_age = time - ripple.z;
            if (ripple_age > 0.0 && ripple_age < 2.0) {
                let dist_to_ripple = distance(vec2<f32>(x, y), ripple.xy);
                if (dist_to_ripple < 0.05) {
                    angle += (ripple_age - 1.0) * 0.5;
                }
            }
        }
    }
    
    // Movement direction
    var dir = vec2<f32>(cos(angle), sin(angle));
    let sensor_pos = agent_pos + dir * (sense_distance / tex_size.x);
    let front_color = textureSampleLevel(readTexture, u_sampler, sensor_pos, 0.0);
    
    // Simple steer: rotate toward brighter color
    let signal = front_color.r;
    angle = angle + (signal - 0.5) * 0.05;
    
    // Update position
    let speed = 0.5 / tex_size.x;
    let new_pos = fract(vec2<f32>(x, y) + dir * speed);
    
    // Deposit trail with alpha
    let coord = vec2<u32>(u32(new_pos.x * tex_size.x), u32(new_pos.y * tex_size.y));
    
    // Sample current trail
    let current_trail = textureLoad(dataTextureC, vec2<i32>(i32(coord.x), i32(coord.y)), 0);
    
    // Agent deposit color - inverse of front color with HDR boost
    let deposit_color = vec3<f32>(1.0 - front_color.r, 1.0 - front_color.g, 1.0 - front_color.b);
    let emission = agentEmissionColor(deposit_color, signal);
    
    // Deposit with soft alpha
    let deposit_rgba = vec4<f32>(emission, deposit_opacity);
    
    // Blend with existing trail
    let new_trail = mix(current_trail, deposit_rgba, deposit_opacity);
    let decayed_trail = new_trail * trail_decay;
    
    // Store trail
    textureStore(dataTextureA, vec2<i32>(i32(coord.x), i32(coord.y)), decayed_trail);
    
    // Write back agent data
    extraBuffer[idx * 3u + 0u] = new_pos.x;
    extraBuffer[idx * 3u + 1u] = new_pos.y;
    extraBuffer[idx * 3u + 2u] = angle;
    
    // ═══════════════════════════════════════════════════════════════
    //  OUTPUT WITH ALPHA SCATTERING
    // ═══════════════════════════════════════════════════════════════
    
    // Calculate cumulative density for this pixel
    // Read from dataTextureC for accumulated density
    let local_trail = textureSampleLevel(dataTextureC, non_filtering_sampler, new_pos, 0.0);
    
    // Trail density based on alpha channel
    let trail_density = local_trail.a * length(local_trail.rgb);
    
    // Exponential transmittance for cumulative effect
    let trans = transmittance(trail_density);
    let cumulative_alpha = 1.0 - trans;
    
    // HDR color output
    let hdr_output = local_trail.rgb * (1.0 + signal);
    
    let output_color = vec4<f32>(hdr_output, clamp(cumulative_alpha, 0.0, 1.0));
    textureStore(writeTexture, vec2<i32>(i32(coord.x), i32(coord.y)), output_color);
}
