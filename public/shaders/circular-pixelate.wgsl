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
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    let density_param = u.zoom_params.x;
    let radius_param = u.zoom_params.y;
    let hardness_param = u.zoom_params.z;
    let bg_mix_param = u.zoom_params.w;

    // Grid config
    // Mouse X can also modulate density locally? No, stick to global param + local radius mod.
    let cells = density_param * 100.0 + 10.0;
    let grid_size = vec2<f32>(1.0 / cells, (1.0 / cells) * aspect); // Correct aspect for square cells?
    // Actually, to get square cells:
    let cell_count_x = cells;
    let cell_count_y = cells / aspect;

    let grid_uv = uv * vec2<f32>(cell_count_x, cell_count_y);
    let cell_id = floor(grid_uv);
    let cell_local = fract(grid_uv) - 0.5; // -0.5 to 0.5

    // Sample color at center of cell
    let sample_uv = (cell_id + 0.5) / vec2<f32>(cell_count_x, cell_count_y);
    let color = textureSampleLevel(readTexture, u_sampler, clamp(sample_uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // Circle shape
    let dist = length(cell_local);

    // Interactive Radius: Modulate based on distance to mouse
    let mouse_dist = distance(uv, mouse);
    let radius_mod = radius_param * (1.0 + 0.5 * sin(mouse_dist * 10.0 - u.config.x * 2.0));
    // Or just simple falloff
    // let radius_mod = radius_param * smoothstep(0.0, 0.5, mouse_dist);
    // Let's use Mouse Y to control Base Radius, Mouse X for Density.
    // The params are explicit though.
    // Let's make radius respond to mouse proximity (larger near mouse).
    let interaction = 1.0 - smoothstep(0.0, 0.3, mouse_dist);
    let final_radius = radius_param * 0.5 + interaction * 0.2; // Max radius 0.5 (touching edges)

    // Hardness
    let edge = 0.01 + (1.0 - hardness_param) * 0.2;
    let mask = 1.0 - smoothstep(final_radius - edge, final_radius, dist);

    var final_color = mix(vec4<f32>(0.0, 0.0, 0.0, 1.0), color, mask);

    // Mix with original image if desired (bg_mix usually 1.0 for full effect)
    let orig = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    final_color = mix(orig, final_color, bg_mix_param);

    textureStore(writeTexture, global_id.xy, final_color);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
