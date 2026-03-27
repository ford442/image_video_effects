// ═══════════════════════════════════════════════════════════════
//  Nano Repair with Alpha Scattering
//  Health-based repair simulation with physical light transport
//  
//  Scientific Concepts:
//  - Particles have physical size and opacity
//  - Health affects light transmission
//  - Scattering in damaged areas
//  - Repair creates glowing reconstruction
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

// Hash function for noise
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Soft particle alpha
fn softParticleAlpha(dist: f32, radius: f32) -> f32 {
    let t = dist / radius;
    return exp(-t * t * 2.0);
}

// Exponential transmittance
fn transmittance(density: f32) -> f32 {
    return exp(-density);
}

// Glitch noise function
fn glitchNoise(uv: vec2<f32>, time: f32, strength: f32) -> f32 {
    let blockSize = max(1.0, 20.0 * strength);
    let blockUV = floor(uv * blockSize) / blockSize;
    return hash12(blockUV + time);
}

// Repair emission color
fn repairEmission(health: f32) -> vec3<f32> {
    // Damaged = red/orange glow, Healthy = normal
    let damaged = vec3<f32>(1.0, 0.3, 0.1);
    let healthy = vec3<f32>(0.2, 1.0, 0.4);
    return mix(damaged, healthy, health);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Params
    let radius = u.zoom_params.x;
    let decay = u.zoom_params.y;
    let glitchStr = u.zoom_params.z;
    let scanlines = u.zoom_params.w;

    // Read previous health state
    let oldData = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var health = oldData.r;

    // Mouse Interaction
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    if (dist < radius) {
        // Repair increases health
        health += 0.1;
    } else {
        // Decay decreases health
        health -= decay * 0.01;
    }
    health = clamp(health, 0.0, 1.0);

    // Store health for next frame
    textureStore(dataTextureA, global_id.xy, vec4<f32>(health, 0.0, 0.0, 1.0));

    // ═══════════════════════════════════════════════════════════════
    //  RENDER WITH ALPHA SCATTERING
    // ═══════════════════════════════════════════════════════════════

    // Sample base texture
    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Repair glow alpha
    let repair_radius = radius * (1.0 + sin(time * 3.0) * 0.1);
    let dist_to_repair = max(0.0, dist - radius * 0.5);
    let repair_alpha = softParticleAlpha(dist_to_repair, repair_radius) * (1.0 - health);
    
    // Repair emission
    let repair_emission = repairEmission(health);
    let repair_glow = repair_emission * repair_alpha * 2.0;

    // Glitch Effect for damaged areas
    var glitch_color = color;
    var glitch_alpha: f32 = 0.0;
    
    if (health < 1.0) {
        let noiseVal = glitchNoise(uv, time, glitchStr);
        
        // Random offset blocks
        if (noiseVal > 0.8) {
             let offset = (noiseVal - 0.9) * 0.5 * glitchStr;
             glitch_color = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset, 0.0), 0.0).rgb;
             glitch_color.r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset + 0.01, 0.0), 0.0).r;
             glitch_color.b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset - 0.01, 0.0), 0.0).b;
             glitch_alpha = (noiseVal - 0.8) * 5.0 * (1.0 - health);
        }

        // Noise overlay
        let grain = hash12(uv * resolution + time) * glitchStr;
        glitch_color += vec3<f32>(grain);
        
        // Scanlines
        let sl = sin(uv.y * resolution.y * 0.5) * 0.5 + 0.5;
        let scanline_alpha = sl * scanlines * (1.0 - health);
        glitch_color *= mix(vec3<f32>(1.0), vec3<f32>(sl), scanline_alpha);
    }

    // Mix based on health with alpha blending
    let mask = smoothstep(0.2, 0.8, health);
    let mixed_color = mix(glitch_color, color, mask);
    
    // Add repair glow
    let final_color = mixed_color + repair_glow;
    
    // Cumulative alpha from damage and repair
    let damage_density = (1.0 - health) * (glitch_alpha + scanlines * 0.3);
    let repair_density = repair_alpha * health;
    let total_density = damage_density + repair_density;
    
    // Exponential transmittance
    let trans = transmittance(total_density);
    let cumulative_alpha = 1.0 - trans;
    
    // HDR boost in repair areas
    let hdr_color = final_color * (1.0 + repair_alpha);

    // Output RGBA
    let output = vec4<f32>(hdr_color, clamp(cumulative_alpha, 0.0, 1.0));
    textureStore(writeTexture, vec2<i32>(global_id.xy), output);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
