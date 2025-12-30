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

    // Parameters
    let scan_width = u.zoom_params.x * 0.2 + 0.01;
    let color_shift = u.zoom_params.y;
    let grid_intensity = u.zoom_params.z;
    let noise_amt = u.zoom_params.w;

    // Mouse Y controls scan position
    let mouse_y = u.zoom_config.z;

    // Distance from scan center (vertical)
    let dist = abs(uv.y - mouse_y);

    var sample_uv = uv;
    var is_scan = false;

    if (dist < scan_width) {
        is_scan = true;

        // 1. Pixelate / Low-Res effect inside scan
        // Higher noise_amt = lower resolution
        let pixels = 50.0 + (1.0 - noise_amt) * 1000.0;
        sample_uv = floor(uv * pixels) / pixels;

        // 2. Horizontal Glitch / Jitter
        let time = u.config.x;
        let jitter = sin(uv.y * 200.0 + time * 20.0) * 0.02 * noise_amt;
        sample_uv.x = clamp(sample_uv.x + jitter, 0.0, 1.0);
    }

    var color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;

    if (is_scan) {
        // 3. Color Shift (Hue Rotate)
        if (color_shift > 0.01) {
            let angle = color_shift * 6.28;
            let c = cos(angle);
            let s = sin(angle);
            // RGB to YIQ-ish rotation matrix
            let mat = mat3x3<f32>(
                vec3<f32>(0.299, 0.587, 0.114) + vec3<f32>(0.701, -0.587, -0.114)*c + vec3<f32>(-0.168, -0.330, 0.497)*s,
                vec3<f32>(0.299, 0.587, 0.114) + vec3<f32>(-0.299, 0.413, -0.114)*c + vec3<f32>(0.328, 0.035, -0.497)*s,
                vec3<f32>(0.299, 0.587, 0.114) + vec3<f32>(-0.300, -0.588, 0.886)*c + vec3<f32>(1.250, -1.050, -0.203)*s
            );

            // Apply matrix
            color = mat * color;
        }

        // 4. Grid Overlay
        if (grid_intensity > 0.0) {
            let grid_size = 50.0;
            let grid_x = step(0.95, fract(uv.x * grid_size));
            let grid_y = step(0.90, fract(uv.y * (grid_size / 2.0))); // wider rows
            let grid = max(grid_x, grid_y) * grid_intensity;
            color = color + vec3<f32>(grid);
        }

        // 5. Brightness / Scanline Glow
        // Brighter at the center of the scan
        let scan_glow = (1.0 - (dist / scan_width)) * 0.5;
        color = color + vec3<f32>(scan_glow);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
