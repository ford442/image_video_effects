// Kimi Flock Symphony - Advanced particle flocking with musical visualization
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

fn hash(p: f32) -> f32 {
    return fract(sin(p * 12.9898) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
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
    
    let base = idx * 6u;
    var px = extraBuffer[base + 0u];
    var py = extraBuffer[base + 1u];
    var vx = extraBuffer[base + 2u];
    var vy = extraBuffer[base + 3u];
    var hue = extraBuffer[base + 4u];
    var energy = extraBuffer[base + 5u];
    
    let pos = vec2<f32>(px, py);
    let vel = vec2<f32>(vx, vy);
    let time = u.config.x;
    
    // Separation, Alignment, Cohesion (simplified)
    var sep = vec2<f32>(0.0);
    var ali = vec2<f32>(0.0);
    var coh = vec2<f32>(0.0);
    var count: f32 = 0.0;
    
    // Sample neighbors (spatial hashing would be better but brute force for simplicity)
    for (var j: u32 = 0u; j < 256u; j = j + 1u) {
        let j_idx = (idx + j * 64u) % BOID_COUNT;
        if (j_idx == idx) { continue; }
        
        let j_base = j_idx * 6u;
        let j_pos = vec2<f32>(extraBuffer[j_base + 0u], extraBuffer[j_base + 1u]);
        let j_vel = vec2<f32>(extraBuffer[j_base + 2u], extraBuffer[j_base + 3u]);
        
        let diff = pos - j_pos;
        let d = length(diff);
        
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
    
    // Mouse attraction with spiral motion
    let mouse_pos = u.zoom_config.yz;
    let to_mouse = mouse_pos - pos;
    let dist_to_mouse = length(to_mouse);
    let mouse_force = normalize(to_mouse) * 0.03;
    
    // Add perpendicular component for spiral
    let perp = vec2<f32>(-mouse_force.y, mouse_force.x);
    let spiral_strength = u.zoom_config.w * 2.0 + 0.5;
    let spiral_force = perp * spiral_strength * smoothstep(0.5, 0.0, dist_to_mouse);
    
    // Apply forces
    var new_vel = vel + sep * 0.5 + ali * 0.3 + coh * 0.3 + mouse_force + spiral_force;
    
    // Add noise-based wandering
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
    
    // Update color based on velocity and position
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
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let trail_length = u.zoom_params.x * 0.1;
    let glow_radius = u.zoom_params.y * 5.0 + 1.0;
    let color_shift = u.zoom_params.z;
    let density = u.zoom_params.w;
    
    var color = vec3<f32>(0.0);
    var total_energy: f32 = 0.0;
    
    // Sample boids with trail accumulation
    let sample_count = 2048u;
    for (var i: u32 = 0u; i < sample_count; i = i + 1u) {
        let base = i * 6u;
        let bx = extraBuffer[base + 0u] * resolution.x;
        let by = extraBuffer[base + 1u] * resolution.y;
        let b_hue = extraBuffer[base + 4u];
        let b_energy = extraBuffer[base + 5u];
        
        let boid_pos = vec2<f32>(bx, by);
        let pixel_pos = vec2<f32>(f32(coord.x), f32(coord.y));
        let d = distance(pixel_pos, boid_pos);
        
        if (d < glow_radius) {
            let intensity = (1.0 - d / glow_radius) * b_energy;
            let rgb = hsl_to_rgb(fract(b_hue + color_shift), 0.8, 0.5);
            color += rgb * intensity * density;
            total_energy += intensity;
        }
    }
    
    // Add center glow at mouse
    let mouse = u.zoom_config.yz * resolution;
    let mouse_dist = distance(vec2<f32>(f32(coord.x), f32(coord.y)), mouse);
    let mouse_glow = smoothstep(100.0, 0.0, mouse_dist) * 0.5;
    color += vec3<f32>(1.0, 0.9, 0.7) * mouse_glow;
    
    // Tone mapping and glow
    color = color / (1.0 + color);
    color = pow(color, vec3<f32>(0.8));
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    color *= vignette;
    
    textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
}
