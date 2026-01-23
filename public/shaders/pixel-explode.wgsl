// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(gid.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Grid Setup
    let grid_size = 40.0;
    let grid_dims = vec2<f32>(grid_size * aspect, grid_size);
    let cell_size = 1.0 / grid_dims;

    // Mouse
    let mouse = u.zoom_config.yz;
    let explosion_radius = 0.5;

    // Adjusted force and search range to avoid clipping
    let explosion_force = 0.08;
    let range = 6;

    var final_color = vec4<f32>(0.0);
    var closest_z = 1000.0;

    let current_cell = floor(uv * grid_dims);

    for (var x = -range; x <= range; x++) {
        for (var y = -range; y <= range; y++) {
            let neighbor_cell = current_cell + vec2<f32>(f32(x), f32(y));

            // Original position of the particle (center)
            let orig_center = (neighbor_cell + 0.5) * cell_size;

            // Calculate displacement
            let to_mouse = orig_center - mouse;
            // Correct for aspect ratio in distance calc
            let to_mouse_aspect = to_mouse * vec2<f32>(aspect, 1.0);
            let dist = length(to_mouse_aspect);

            // Radial displacement
            let strength = smoothstep(explosion_radius, 0.0, dist);
            let offset = normalize(to_mouse) * strength * explosion_force;

            let new_center = orig_center + offset;

            // Scale logic (Z-depth)
            let scale = 1.0 + strength * 2.0;
            let particle_half_size = (cell_size * 0.5) * scale * 0.9;

            // Check if current pixel 'uv' is inside this transformed particle
            let diff = abs(uv - new_center);

            if (diff.x < particle_half_size.x && diff.y < particle_half_size.y) {
                // Z-buffer check
                let z_depth = dist;

                if (z_depth < closest_z) {
                    closest_z = z_depth;

                    // Sample texture
                    // Map uv back to local particle coordinates 0..1
                    let local_uv = (uv - new_center) / (particle_half_size * 2.0) + 0.5;

                    // Sample relative to orig_center to keep texture coherent on the tile
                    let tex_uv = (neighbor_cell * cell_size) + local_uv * cell_size;

                    final_color = textureSampleLevel(readTexture, u_sampler, tex_uv, 0.0);

                    // Add some shading based on Z/strength
                    final_color = final_color * (1.0 + strength * 0.5);
                }
            }
        }
    }

    // Background color (dark void)
    if (final_color.a == 0.0) {
        final_color = vec4<f32>(0.05, 0.05, 0.1, 1.0);
    }

    textureStore(writeTexture, vec2<i32>(gid.xy), final_color);
}
