// ═══════════════════════════════════════════════════════════════
//  Kimi Flock Symphony with Alpha Scattering
//  Advanced particle flocking with musical visualization
//  With Physical Light Transport and Cumulative Alpha
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

const BOID_COUNT: u32 = 16384u;
const MAX_SPEED: f32 = 3.0;
const PERCEPTION_RADIUS: f32 = 0.05;

// Soft particle alpha
fn softParticleAlpha(dist: f32, radius: f32) -> f32 {
    let t = dist / radius;
    return exp(-t * t * 1.5);
}

// Exponential transmittance
fn transmittance(density: f32) -> f32 {
    return exp(-density);
}

// HDR emission
fn hdrEmission(base: vec3<f32>, intensity: f32) -> vec3<f32> {
    return base * (0.5 + intensity * 2.0);
}

fn hash(p: f32) -> f32 {
    return fract(sin(p * 12.9898) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i.x + i.y * 57.0), hash(i.x + 1.0 + i.y * 57.0), u.x),
               mix(hash(i.x + (i.y + 1.0) * 57.0), hash(i.x + 1.0 + (i.y + 1.0) * 57.0), u.x), u.y);
}

// HSL to RGB conversion
fn hsl_to_rgb(h: f32, s: f32, l: f32) -> vec3<f32> {
    let c = (1.0 - abs(2.0 * l - 1.0)) * s;
    let x = c * (1.0 - abs(fract(h * 6.0) * 2.0 - 1.0));
    let m = l - c * 0.5;
    
    var rgb: vec3<f32>;
    if (h < 1.0 / 6.0) {
        rgb = vec3<f32>(c, x, 0.0);
    } else if (h < 2.0 / 6.0) {
        rgb = vec3<f32>(x, c, 0.0);
    } else if (h < 3.0 / 6.0) {
        rgb = vec3<f32>(0.0, c, x);
    } else if (h < 4.0 / 6.0) {
        rgb = vec3<f32>(0.0, x, c);
    } else if (h < 5.0 / 6.0) {
        rgb = vec3<f32>(x, 0.0, c);
    } else {
        rgb = vec3<f32>(c, 0.0, x);
    }
    return rgb + vec3<f32>(m);
}

@compute @workgroup_size(64, 1, 1)
fn update_boids(@builtin(global_invocation_id) gid: vec3<u32>) {
    let idx = gid.x;
    if (idx >= BOID_COUNT) { return; }
    
    var base = idx * 6u;
    var px = extraBuffer[base + 0u];
    var py = extraBuffer[base + 1u];
    var vx = extraBuffer[base + 2u];
    var vy = extraBuffer[base + 3u];
    var hue = extraBuffer[base + 4u];
    var energy = extraBuffer[base + 5u];
    
    var pos = vec2<f32>(px, py);
    let vel = vec2<f32>(vx, vy);
    var time = u.config.x;
    
    // Separation, Alignment, Cohesion
    var sep = vec2<f32>(0.0);
    var ali = vec2<f32>(0.0);
    var coh = vec2<f32>(0.0);
    var count: f32 = 0.0;
    
    for (var j: u32 = 0u; j < 256u; j = j + 1u) {
        let j_idx = (idx + j * 64u) % BOID_COUNT;
        if (j_idx == idx) { continue; }
        
        let j_base = j_idx * 6u;
        let j_pos = vec2<f32>(extraBuffer[j_base + 0u], extraBuffer[j_base + 1u]);
        let j_vel = vec2<f32>(extraBuffer[j_base + 2u], extraBuffer[j_base + 3u]);
        
        let diff = pos - j_pos;
        var d = length(diff);
        
        if (d < PERCEPTION_RADIUS && d > 0.0) {
            sep += normalize(diff) / d;
            ali += j_vel;
            coh += j_pos;
            count += 1.0;
        }
    }
    
    if (count > 0.0) {
        sep = normalize(sep) * 1.5;
        ali = normalize(ali / count - vel) * 1.0;
        coh = normalize(coh / count - pos) * 1.0;
    }
    
    // Mouse attraction with spiral
    let mouse_pos = u.zoom_config.yz;
    let to_mouse = mouse_pos - pos;
    let dist_to_mouse = length(to_mouse);
    let mouse_force = normalize(to_mouse) * 0.03;
    
    let perp = vec2<f32>(-mouse_force.y, mouse_force.x);
    let spiral_strength = u.zoom_config.w * 2.0 + 0.5;
    let spiral_force = perp * spiral_strength * smoothstep(0.5, 0.0, dist_to_mouse);
    
    var new_vel = vel + sep * 0.5 + ali * 0.3 + coh * 0.3 + mouse_force + spiral_force;
    
    // Noise wandering
    let noise_force = vec2<f32>(
        noise(pos * 10.0 + time),
        noise(pos * 10.0 + time + 100.0)
    ) * 0.02;
    new_vel += noise_force;
    
    // Limit speed
    let speed = length(new_vel);
    if (speed > MAX_SPEED) {
        new_vel = normalize(new_vel) * MAX_SPEED;
    }
    
    // Update position
    var new_pos = pos + new_vel * 0.003;
    new_pos = fract(new_pos);
    
    // Update color based on velocity
    let speed_norm = speed / MAX_SPEED;
    hue = fract(hue + speed_norm * 0.01 + time * 0.02);
    energy = mix(energy, speed_norm, 0.1);
    
    extraBuffer[base + 0u] = new_pos.x;
    extraBuffer[base + 1u] = new_pos.y;
    extraBuffer[base + 2u] = new_vel.x;
    extraBuffer[base + 3u] = new_vel.y;
    extraBuffer[base + 4u] = hue;
    extraBuffer[base + 5u] = energy;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(textureDimensions(readTexture));
    var uv = vec2<f32>(global_id.xy) / resolution;
    var time = u.config.x;
    
    // Parameters
    let glow_radius = u.zoom_params.y * 8.0 + 2.0;
    let color_shift = u.zoom_params.z;
    let density = u.zoom_params.w;
    let particle_opacity = 0.6;
    
    var accumulated_color = vec3<f32>(0.0);
    var accumulated_density: f32 = 0.0;
    var total_energy: f32 = 0.0;
    
    // Sample boids
    let sample_count = 2048u;
    for (var i: u32 = 0u; i < sample_count; i = i + 1u) {
        var base = i * 6u;
        let bx = extraBuffer[base + 0u] * resolution.x;
        let by = extraBuffer[base + 1u] * resolution.y;
        let bvx = extraBuffer[base + 2u];
        let bvy = extraBuffer[base + 3u];
        let b_hue = extraBuffer[base + 4u];
        let b_energy = extraBuffer[base + 5u];
        
        let boid_pos = vec2<f32>(bx, by);
        let vel = vec2<f32>(bvx, bvy);
        let pixel_pos = vec2<f32>(f32(coord.x), f32(coord.y));
        
        var d = distance(pixel_pos, boid_pos);
        
        if (d < glow_radius) {
            // Speed for motion blur
            let speed = length(vel);
            
            // Soft particle alpha
            let alpha = softParticleAlpha(d, glow_radius) * particle_opacity * b_energy;
            
            // HSL color with shift
            var rgb = hsl_to_rgb(fract(b_hue + color_shift), 0.8, 0.5);
            
            // HDR emission based on energy and speed
            let emission = 1.0 + b_energy * 2.0 + speed * 0.5;
            let hdr_rgb = hdrEmission(rgb, emission);
            
            // Accumulate
            accumulated_color += hdr_rgb * alpha * density;
            accumulated_density += alpha;
            total_energy += alpha * emission;
        }
    }
    
    // Center glow at mouse
    var mouse = u.zoom_config.yz * resolution;
    let mouse_dist = distance(vec2<f32>(f32(coord.x), f32(coord.y)), mouse);
    let mouse_alpha = softParticleAlpha(mouse_dist, 100.0) * 0.5;
    accumulated_color += vec3<f32>(1.0, 0.9, 0.7) * mouse_alpha;
    accumulated_density += mouse_alpha;
    
    // Tone mapping
    accumulated_color = accumulated_color / (1.0 + accumulated_color);
    accumulated_color = pow(accumulated_color, vec3<f32>(0.8));
    
    // Cumulative alpha using exponential transmittance
    let trans = transmittance(accumulated_density * 0.5);
    let final_alpha = 1.0 - trans;
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    accumulated_color *= vignette;
    
    // Output RGBA
    let output = vec4<f32>(accumulated_color, clamp(final_alpha, 0.0, 1.0));
    textureStore(writeTexture, coord, output);
}
