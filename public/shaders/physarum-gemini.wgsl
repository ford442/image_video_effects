// ═══════════════════════════════════════════════════════════════
//  Physarum Polycephalum (Slime Mold) Gemini - Advanced Simulation
//  With Alpha Scattering and Physical Light Transport
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

// Agent struct with personality
struct Agent {
    pos: vec2<f32>,
    angle: f32,
    p_type: f32,
};

// Soft particle alpha based on distance
fn softParticleAlpha(dist: f32, radius: f32) -> f32 {
    let t = dist / radius;
    return exp(-t * t * 2.5);
}

// Exponential transmittance for cumulative density
fn transmittance(density: f32) -> f32 {
    return exp(-density);
}

// HDR emission calculation
fn hdrEmission(base: vec3<f32>, intensity: f32, pulse: f32) -> vec3<f32> {
    return base * (0.3 + intensity * 3.0 + pulse * 2.0);
}

// Personality-based color
fn personalityColor(p_type: f32, nutrient: vec3<f32>) -> vec3<f32> {
    let hue = p_type * 0.8 + 0.1;
    let base = vec3<f32>(
        0.5 + 0.5 * cos(hue * 6.28318530718),
        0.5 + 0.5 * cos(hue * 6.28318530718 + 2.094),
        0.5 + 0.5 * cos(hue * 6.28318530718 + 4.189)
    );
    return mix(base, nutrient, 0.4);
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let idx = gid.x;
    if (idx * 4u + 3u >= arrayLength(&extraBuffer)) { return; }

    var agent: Agent;
    agent.pos = vec2<f32>(extraBuffer[idx * 4u + 0u], extraBuffer[idx * 4u + 1u]);
    agent.angle = extraBuffer[idx * 4u + 2u];
    agent.p_type = extraBuffer[idx * 4u + 3u];

    let tex_size = vec2<f32>(textureDimensions(readTexture));
    let time = u.config.x;
    
    // Parameters
    let agent_radius = mix(1.5, 5.0, u.zoom_params.x);
    let deposit_opacity = mix(0.1, 0.9, u.zoom_params.y);
    let sensor_dist = mix(5.0, 15.0, u.zoom_params.z) / tex_size.x;
    let decay_rate = mix(0.002, 0.02, 1.0 - u.zoom_params.w);
    
    // Sense-and-turn logic
    let sensor_angle = 0.5;
    var dir = vec2<f32>(cos(agent.angle), sin(agent.angle));
    
    let f_pos = agent.pos + dir * sensor_dist;
    let l_pos = agent.pos + vec2<f32>(cos(agent.angle - sensor_angle), sin(agent.angle - sensor_angle)) * sensor_dist;
    let r_pos = agent.pos + vec2<f32>(cos(agent.angle + sensor_angle), sin(agent.angle + sensor_angle)) * sensor_dist;
    
    // Sense trail density from alpha channel
    let f_sense = textureSampleLevel(dataTextureC, non_filtering_sampler, f_pos, 0.0).a;
    let l_sense = textureSampleLevel(dataTextureC, non_filtering_sampler, l_pos, 0.0).a;
    let r_sense = textureSampleLevel(dataTextureC, non_filtering_sampler, r_pos, 0.0).a;
    
    // Steer toward less dense areas (exploration)
    if (f_sense > l_sense && f_sense > r_sense) {
        // Continue straight
    } else if (l_sense < r_sense) {
        agent.angle -= 0.2;
    } else if (r_sense < l_sense) {
        agent.angle += 0.2;
    }
    
    // Random turn
    if (hash(agent.pos + time) > 0.95) {
        agent.angle += (hash(agent.pos - time) - 0.5) * 2.0;
    }

    // Nutrient interaction
    let nutrient_color = textureSampleLevel(readTexture, u_sampler, agent.pos, 0.0).rgb;
    let nutrient_value = length(nutrient_color);

    // Move faster in nutrient-rich areas
    let speed = (0.001 + nutrient_value * 0.002) * (1.0 + agent.p_type * 0.5);
    agent.pos += vec2<f32>(cos(agent.angle), sin(agent.angle)) * speed;
    
    // Wrap around screen edges
    agent.pos = fract(agent.pos);

    // Deposit trail
    let coord = vec2<u32>(agent.pos * tex_size);
    
    // Pulsing effect based on personality
    let pulse = sin(time * 5.0 + agent.p_type * 6.28) * 0.5 + 0.5;
    let pulse_boost = select(0.0, 1.0, pulse > 0.9);
    
    // Trail color based on personality and nutrients
    let trail_color = personalityColor(agent.p_type, nutrient_color);
    
    // Current trail at this position
    let current_trail = textureLoad(dataTextureC, vec2<i32>(coord), 0);
    
    // HDR emission with pulse
    let emission = hdrEmission(trail_color, nutrient_value, pulse_boost);
    
    // Deposit with alpha
    let deposit_alpha = deposit_opacity * (0.5 + pulse_boost * 0.5);
    
    // Blend and decay
    let new_trail = mix(current_trail.rgb, emission, deposit_alpha);
    let decayed_trail = max(current_trail.rgb - decay_rate, vec3<f32>(0.0));
    let final_trail = mix(decayed_trail, new_trail, 0.5);
    
    // Store trail with alpha (density in alpha channel)
    let trail_density = current_trail.a * (1.0 - decay_rate) + deposit_alpha;
    textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(final_trail, min(trail_density, 1.0)));
    
    // Write back agent data
    extraBuffer[idx * 4u + 0u] = agent.pos.x;
    extraBuffer[idx * 4u + 1u] = agent.pos.y;
    extraBuffer[idx * 4u + 2u] = agent.angle;
    extraBuffer[idx * 4u + 3u] = agent.p_type;

    // ═══════════════════════════════════════════════════════════════
    //  OUTPUT WITH ALPHA SCATTERING
    // ═══════════════════════════════════════════════════════════════
    
    // Calculate cumulative density
    let local_density = textureSampleLevel(dataTextureC, non_filtering_sampler, agent.pos, 0.0);
    let density_value = local_density.a * length(local_density.rgb);
    
    // Exponential transmittance
    let trans = transmittance(density_value * 2.0);
    let cumulative_alpha = 1.0 - trans;
    
    // HDR output with glow
    let hdr_output = local_density.rgb * (1.0 + pulse_boost + nutrient_value);
    
    // Pulsing agents are brighter
    let final_output = vec4<f32>(
        hdr_output + vec3<f32>(pulse_boost * 0.5),
        clamp(cumulative_alpha + pulse_boost * 0.3, 0.0, 1.0)
    );
    
    // Only write if above threshold or pulsing
    if (cumulative_alpha > 0.01 || pulse_boost > 0.0) {
        textureStore(writeTexture, vec2<i32>(coord), final_output);
    }
}
