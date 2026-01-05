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
  config: vec4<f32>,       // x=Time, y=Ripples, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // Params
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

    // Parameters
    let grid_speed = u.zoom_params.x; // Grid movement speed
    let glow_intensity = u.zoom_params.y; // Brightness of grid
    let grid_scale = u.zoom_params.z; // Size of grid squares
    let warp_amt = u.zoom_params.w;   // Curvature of grid/sky

    // Mouse Interaction
    // Mouse Y sets horizon (inverted, so mouse up = higher horizon / more floor)
    // Let's map mouse Y (0 top, 1 bottom) directly.
    let mouse_y = u.zoom_config.z;
    let horizon = mouse_y;

    // Mouse X creates a curve/bend in the road
    let mouse_x = u.zoom_config.y;
    let curve = (mouse_x - 0.5) * 4.0 * warp_amt;

    var final_color = vec3<f32>(0.0, 0.0, 0.0);

    if (uv.y < horizon) {
        // Sky (The Image)
        // Map UV y from [0, horizon] to [0, 1]?
        // Or just show the top part of image? Let's squash the image to fit the sky area.
        let sky_uv_y = uv.y / max(horizon, 0.01);
        var sky_uv = vec2<f32>(uv.x, sky_uv_y);

        // Add subtle sunset gradient
        let gradient = smoothstep(0.0, 1.0, sky_uv_y);
        let sunset_color = vec3<f32>(0.8, 0.2, 0.5); // Pinkish

        let img_color = textureSampleLevel(readTexture, u_sampler, sky_uv, 0.0).rgb;
        final_color = mix(img_color, sunset_color, gradient * 0.3 * glow_intensity);

    } else {
        // Floor (The Grid)
        // Perspective projection
        let dy = uv.y - horizon;

        // Avoid division by zero close to horizon
        let z_depth = 1.0 / max(dy, 0.001);

        // Apply curve
        let x_offset = curve * dy * dy; // Curve increases with distance (actually curve should affect far away more?)
        // Standard "road" curve logic: x += curve * z

        let grid_u = (uv.x - 0.5 - x_offset) * z_depth * (0.5 + grid_scale) + 0.5;
        let grid_v = z_depth * (0.5 + grid_scale) + u.config.x * grid_speed;

        // Draw Grid Lines
        let line_width = 0.05 * z_depth; // Lines get thicker closer to camera? No, perspective makes them thinner in screen space usually?
        // Actually, constant width in UV space means thinner in screen space at horizon.

        let grid_x = abs(fract(grid_u) - 0.5);
        let grid_y = abs(fract(grid_v) - 0.5);

        let line_mask = step(0.45, grid_x) + step(0.45, grid_y);
        let grid_val = clamp(line_mask, 0.0, 1.0);

        // Reflection of Sky/Image
        // Sample image at mirrored Y
        let refl_y = horizon - dy; // Simple mirror
        let refl_uv = vec2<f32>(uv.x, clamp(refl_y, 0.0, 1.0)); // Clamp
        let refl_color = textureSampleLevel(readTexture, u_sampler, refl_uv, 0.0).rgb;

        // Grid Color (Cyan/Magenta)
        let grid_col = vec3<f32>(0.0, 1.0, 1.0) * grid_val * glow_intensity * 2.0; // Cyan grid

        // Fade grid into horizon
        let fade = smoothstep(0.0, 0.2, dy);

        final_color = mix(refl_color * 0.5, grid_col, grid_val * fade);
        // Add distance fog (black or purple)
        let fog = smoothstep(0.0, 0.4, dy); // 0 at horizon, 1 near camera
        final_color = mix(vec3<f32>(0.1, 0.0, 0.2), final_color, fog);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
