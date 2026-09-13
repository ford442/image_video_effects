// ═══════════════════════════════════════════════════════════════
//  Nano Repair with Alpha Scattering
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, feedback
//  Upgraded: 2026-09-12
//  Ideas: healing front on |∇health|; weld flash where health rose this frame
//  A packing: raw (health, 0, 0, 1)
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadHealth(coord: vec2<i32>, maxCoord: vec2<i32>) -> f32 {
    return textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), maxCoord), 0).r;
}
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
    let coord = vec2<i32>(global_id.xy);
    let maxCoord = vec2<i32>(resolution) - vec2<i32>(1);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let radius = u.zoom_params.x;
    let decay = u.zoom_params.y;
    let glitchStr = u.zoom_params.z;
    let scanlines = u.zoom_params.w;

    let oldHealth = loadHealth(coord, maxCoord);
    var health = oldHealth;

    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    if (dist < radius) {
        health += 0.1 * (1.0 + bass * 0.4);
    } else {
        health -= decay * 0.01;
    }
    health = clamp(health, 0.0, 1.0);

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
    
    // Idea 1 — healing front: emission on |∇health|
    let hL = loadHealth(coord + vec2<i32>(-1, 0), maxCoord);
    let hR = loadHealth(coord + vec2<i32>(1, 0), maxCoord);
    let hD = loadHealth(coord + vec2<i32>(0, -1), maxCoord);
    let hU = loadHealth(coord + vec2<i32>(0, 1), maxCoord);
    let gradH = length(vec2<f32>(hR - hL, hU - hD));
    let front = smoothstep(0.04, 0.22, gradH);

    // Idea 2 — weld flash where health rose this frame
    let healed = clamp(health - oldHealth, 0.0, 1.0);
    let weld = pow(healed * 8.0, 1.6) * (0.55 + mids * 0.45);

    let repair_emission = repairEmission(health);
    let repair_glow = repair_emission * (repair_alpha * 2.0 + front * 1.4);
    let weld_color = vec3<f32>(0.55, 0.95, 1.0) * weld;

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
    let grain = hash12(uv * resolution + time) * glitchStr * (1.0 + treble * 0.3);
        glitch_color += vec3<f32>(grain);
        
        // Scanlines
        let sl = sin(uv.y * resolution.y * 0.5) * 0.5 + 0.5;
        let scanline_alpha = sl * scanlines * (1.0 - health);
        glitch_color *= mix(vec3<f32>(1.0), vec3<f32>(sl), scanline_alpha);
    }

    // Mix based on health with alpha blending
    let mask = smoothstep(0.2, 0.8, health);
    let mixed_color = mix(glitch_color, color, mask);
    
    let final_color = mixed_color + repair_glow + weld_color;
    
    // Cumulative alpha from damage and repair
    let damage_density = (1.0 - health) * (glitch_alpha + scanlines * 0.3);
    let repair_density = repair_alpha * health;
    let total_density = damage_density + repair_density;
    
    // Exponential transmittance
    let trans = transmittance(total_density);
    let cumulative_alpha = clamp(1.0 - trans + front * 0.25 + weld * 0.35, 0.0, 1.0);
    
    let hdr_color = acesToneMap(final_color * (1.0 + repair_alpha + weld * 0.4));

    let output = vec4<f32>(hdr_color, cumulative_alpha);
    textureStore(writeTexture, vec2<i32>(global_id.xy), output);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
