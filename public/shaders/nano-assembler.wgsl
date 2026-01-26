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

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(coord) / vec2<f32>(dims);

    let assembly_progress = u.zoom_params.x; // Assembly
    let particle_density = u.zoom_params.y; // Density
    let scatter_force = u.zoom_params.z; // Disruption
    let rebuild_speed = u.zoom_params.w; // Rebuild Speed

    let mouse = u.zoom_config.yz;
    let aspect = u.config.z / u.config.w;
    let time = u.config.y;

    // Gridify coordinates (simulating nanobots/pixels)
    let grid_size = mix(50.0, 5.0, particle_density); // Inverse size
    let grid_coord = floor(uv * grid_size) / grid_size;

    // Each grid cell is a "nanobot"
    let cell_center = grid_coord + vec2<f32>(0.5 / grid_size);
    let cell_uv = fract(uv * grid_size); // 0-1 within cell

    // Mouse Interaction: Disassemble
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Nanobot "target" position (where it wants to be)
    // vs "current" position (scattered)

    // Scatter logic:
    // If scattered, offset the UV lookup based on noise
    let noise_offset = (hash2(grid_coord + time * 0.1) - 0.5) * scatter_force;

    // Assembly factor (global + local mouse disruption)
    // Mouse creates a hole in the assembly (repulsion)
    let mouse_repel = smoothstep(0.2, 0.0, dist);
    let current_state = clamp(assembly_progress - mouse_repel * scatter_force, 0.0, 1.0);

    // Rebuild logic (animated)
    // Use time to cycle the assembly if rebuild_speed > 0
    let pulse = 0.5 + 0.5 * sin(time * rebuild_speed * 2.0);
    let anim_state = mix(current_state, current_state * pulse, rebuild_speed * 0.5);

    // Apply offset if not fully assembled
    let final_uv_offset = noise_offset * (1.0 - anim_state);

    // Sample Texture (where the nanobot is carrying color from)
    let source_uv = grid_coord + final_uv_offset;

    // Boundary check
    var color = vec4<f32>(0.0);
    if (source_uv.x >= 0.0 && source_uv.x <= 1.0 && source_uv.y >= 0.0 && source_uv.y <= 1.0) {
        color = textureSampleLevel(readTexture, u_sampler, source_uv, 0.0);
    }

    // Render the Nanobot shape (circle or square)
    // Square with gap
    let border = 0.1;
    let shape = step(border, cell_uv.x) * step(border, cell_uv.y) * step(cell_uv.x, 1.0 - border) * step(cell_uv.y, 1.0 - border);

    // If fully assembled, merge shapes (remove gaps)
    let merge = smoothstep(0.8, 1.0, anim_state);
    let final_alpha = mix(shape, 1.0, merge);

    // Highlight edges of bots when disassembling
    let highlight = (1.0 - final_alpha) * vec3<f32>(0.0, 1.0, 1.0) * (1.0 - anim_state);

    var final_color = color.rgb * final_alpha + highlight;

    // If empty space (no bot), black
    if (final_alpha < 0.1) {
        final_color = vec3<f32>(0.05, 0.05, 0.1) * (1.0 - anim_state); // faint background grid
    }

    textureStore(writeTexture, coord, vec4<f32>(final_color, 1.0));
}
