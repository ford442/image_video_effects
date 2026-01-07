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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=BlockSize, y=Radius, z=GridOpacity, w=ColorTint
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let block_size = max(2.0, u.zoom_params.x * 50.0 + 2.0); // 2 to 52 pixels
    let radius = u.zoom_params.y * 0.4 + 0.05;
    let grid_opacity = u.zoom_params.z;
    let tint_strength = u.zoom_params.w;

    // Mouse
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Smooth circle mask
    let mask = 1.0 - smoothstep(radius, radius + 0.05, dist);

    var color: vec4<f32>;

    if (mask > 0.001) {
        // Inside digital lens: Pixelate
        let blocks = resolution / block_size;
        let uv_quantized = floor(uv * blocks) / blocks + (0.5 / blocks);

        let pixelated = textureSampleLevel(readTexture, non_filtering_sampler, uv_quantized, 0.0);
        let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

        // Grid lines
        let uv_pixel = uv * resolution;
        let grid_x = step(block_size - 1.0, uv_pixel.x % block_size);
        let grid_y = step(block_size - 1.0, uv_pixel.y % block_size);
        let grid_line = max(grid_x, grid_y);

        var lens_color = pixelated;

        // Green matrix tint
        let tint = vec4<f32>(0.0, 1.0, 0.2, 1.0);
        lens_color = mix(lens_color, lens_color * tint * 1.5, tint_strength);

        // Add grid
        lens_color = mix(lens_color, vec4<f32>(0.0, 0.0, 0.0, 1.0), grid_line * grid_opacity);

        // Mix based on mask edge (soft transition)
        color = mix(original, lens_color, mask);

    } else {
        color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    }

    textureStore(writeTexture, global_id.xy, color);
}
