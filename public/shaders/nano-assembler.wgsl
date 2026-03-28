// ═══════════════════════════════════════════════════════════════
//  Nano Assembler with Alpha Scattering
//  Grid-based nanobot simulation with physical light transport
//  
//  Scientific Concepts:
//  - Particles have physical size and opacity
//  - Many small particles = cumulative alpha
//  - Scattering affects perceived transparency
//  - Assembly state affects light transmission
// ═══════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p2 = fract(p * vec2<f32>(0.1031, 0.1030));
    p2 += dot(p2, p2.yx + 33.33);
    return fract((p2.xx + p2.yx) * p2.xy);
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

// Nanobot emission color
fn nanobotEmission(base: vec3<f32>, assembled: f32) -> vec3<f32> {
    // Disassembled = cyan glow, assembled = natural color
    let disassembled_glow = vec3<f32>(0.2, 0.8, 1.0);
    return mix(base * (0.5 + assembled), disassembled_glow, 1.0 - assembled);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(coord) / vec2<f32>(dims);

    let assembly_progress = u.zoom_params.x;
    let particle_density = u.zoom_params.y;
    let scatter_force = u.zoom_params.z;
    let rebuild_speed = u.zoom_params.w;

    var mouse = u.zoom_config.yz;
    let aspect = u.config.z / u.config.w;
    let time = u.config.y;

    // Grid parameters
    let grid_size = mix(50.0, 5.0, particle_density);
    let grid_coord = floor(uv * grid_size) / grid_size;
    let cell_center = grid_coord + vec2<f32>(0.5 / grid_size);
    let cell_uv = fract(uv * grid_size);

    // Mouse interaction
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Scatter logic
    let noise_offset = (hash2(grid_coord + time * 0.1) - 0.5) * scatter_force;
    let mouse_repel = smoothstep(0.2, 0.0, dist);
    let current_state = clamp(assembly_progress - mouse_repel * scatter_force, 0.0, 1.0);

    // Rebuild animation
    let pulse = 0.5 + 0.5 * sin(time * rebuild_speed * 2.0);
    let anim_state = mix(current_state, current_state * pulse, rebuild_speed * 0.5);

    // Apply offset if not fully assembled
    let final_uv_offset = noise_offset * (1.0 - anim_state);
    let source_uv = grid_coord + final_uv_offset;

    // Sample texture
    var base_color = vec4<f32>(0.0);
    if (source_uv.x >= 0.0 && source_uv.x <= 1.0 && source_uv.y >= 0.0 && source_uv.y <= 1.0) {
        base_color = textureSampleLevel(readTexture, u_sampler, source_uv, 0.0);
    }

    // ═══════════════════════════════════════════════════════════════
    //  NANOBOT ALPHA SCATTERING
    // ═══════════════════════════════════════════════════════════════

    // Nanobot shape (square with soft edges)
    let border = 0.1;
    let cell_dist = max(abs(cell_uv.x - 0.5), abs(cell_uv.y - 0.5)) * 2.0;
    
    // Soft particle alpha for nanobot shape
    let core_radius = 0.5 - border;
    let bot_alpha = softParticleAlpha(max(0.0, cell_dist - core_radius), border * 0.5);
    
    // Assembly affects opacity
    let assembled_alpha = bot_alpha * (0.3 + anim_state * 0.7);
    
    // Merge shapes when fully assembled
    let merge = smoothstep(0.8, 1.0, anim_state);
    let final_alpha = mix(assembled_alpha, 1.0, merge);

    // Highlight edges when disassembling
    let edge_dist = abs(cell_dist - core_radius);
    let edge_highlight = (1.0 - smoothstep(0.0, 0.05, edge_dist)) * (1.0 - anim_state);
    let highlight_color = vec3<f32>(0.0, 1.0, 1.0) * edge_highlight;

    // HDR emission based on assembly state
    let emission = nanobotEmission(base_color.rgb, anim_state);
    let hdr_color = emission * (1.0 + edge_highlight * 2.0);
    
    // Grid density for cumulative alpha
    let grid_density = final_alpha * (1.0 + scatter_force * 0.5);
    
    // Exponential transmittance
    let trans = transmittance(grid_density);
    let cumulative_alpha = 1.0 - trans;

    // Background grid when disassembled
    let bg_grid = vec3<f32>(0.05, 0.05, 0.1) * (1.0 - anim_state);
    
    // Final color composition
    var final_color = hdr_color * final_alpha + highlight_color;
    if (final_alpha < 0.1) {
        final_color = bg_grid;
    }

    // Output RGBA
    let output = vec4<f32>(final_color, clamp(cumulative_alpha, 0.0, 1.0));
    textureStore(writeTexture, coord, output);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, filteringSampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
