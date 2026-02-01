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

    let grid_param = u.zoom_params.x;
    let amp_param = u.zoom_params.y;
    let freq_param = u.zoom_params.z;
    let speed_param = u.zoom_params.w;

    let cells = grid_param * 40.0 + 5.0;
    let cell_size = vec2<f32>(1.0 / cells, (1.0 / cells) * aspect);

    // Grid coords
    let grid_uv = uv * vec2<f32>(cells, cells / aspect);
    let cell_id = floor(grid_uv);
    let cell_center_uv = (cell_id + 0.5) / vec2<f32>(cells, cells / aspect);

    // Distance from cell center to mouse
    let d_vec = (cell_center_uv - mouse);
    let d = length(vec2<f32>(d_vec.x * aspect, d_vec.y));

    // Wave
    let time = u.config.x * (speed_param * 5.0);
    let freq = freq_param * 50.0;

    // Scale factor
    // Wave moves outwards: - time
    let wave = sin(d * freq - time);

    // Amp falls off with distance? Or constant?
    // Let's make it ripple out.
    let falloff = 1.0 / (1.0 + d * 5.0);
    let scale_mod = wave * amp_param * falloff;

    let scale = 1.0 - scale_mod * 0.8; // Avoid negative scale

    // Scale UVs relative to cell center
    let uv_centered = uv - cell_center_uv;
    let uv_scaled = uv_centered / max(0.01, scale) + cell_center_uv;

    // Clip if outside cell? Or repeat?
    // Usually with block effects we want clamping or repeating inside the block.
    // If we scale UP (zoom in), we see less. If we scale DOWN (zoom out), we see neighbors or repeat.
    // Let's clamp to cell bounds for "fragmented" look.

    // Calculate bounds of current cell
    let cell_min = cell_id / vec2<f32>(cells, cells / aspect);
    let cell_max = (cell_id + 1.0) / vec2<f32>(cells, cells / aspect);

    var color = vec4<f32>(0.0);

    if (uv_scaled.x >= cell_min.x && uv_scaled.x <= cell_max.x &&
        uv_scaled.y >= cell_min.y && uv_scaled.y <= cell_max.y) {
         color = textureSampleLevel(readTexture, u_sampler, clamp(uv_scaled, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    } else {
         // Gap color
         color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    // Add shading based on scale/wave?
    let light = wave * 0.1;
    color += vec4<f32>(light, light, light, 0.0);

    textureStore(writeTexture, global_id.xy, color);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
