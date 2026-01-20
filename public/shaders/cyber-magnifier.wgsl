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

    // Parameters
    let magnification = mix(1.0, 4.0, u.zoom_params.x);
    let radius = mix(0.1, 0.45, u.zoom_params.y);
    let aberration_strength = u.zoom_params.z * 0.05;
    let grid_opacity = u.zoom_params.w;

    // Distance to mouse (corrected for aspect)
    let dist_vec = uv - mouse;
    let dist_vec_aspect = dist_vec * vec2(aspect, 1.0);
    let dist = length(dist_vec_aspect);

    // Lens mask (soft edge)
    let edge_width = 0.005;
    let in_lens = 1.0 - smoothstep(radius, radius + edge_width, dist);

    // Calculate zoomed UV
    // We want the point under the mouse to remain fixed, and points around it to push out.
    // uv_new = (uv - center) / mag + center
    let uv_zoomed = (uv - mouse) / magnification + mouse;

    // Chromatic Aberration Vector
    // Displacement increases towards the edge of the lens
    // Direction is radial from mouse
    let aberration_dir = normalize(dist_vec);
    // Handle center case (0 vector)
    let valid_aberration = select(vec2<f32>(0.0), aberration_dir, length(dist_vec) > 0.0001);

    let aberration_offset = valid_aberration * aberration_strength * (dist / radius);

    // Mix UVs
    // If we are outside lens, uv is normal. Inside, it's zoomed + aberration.
    // We'll interpolate for smoothness at edge, though physical lenses are usually sharp cuts.
    // Let's keep it sharp but use the smooth mask for alpha blending if we want a "ghost" lens.
    // Here we hard switch effectively via mix, but the transition is tiny (edge_width).

    // Inside the lens, we sample using zoomed coordinates.
    // R channel pushes out, B channel pushes in (or vice versa)
    let r_uv_lens = uv_zoomed - aberration_offset;
    let g_uv_lens = uv_zoomed;
    let b_uv_lens = uv_zoomed + aberration_offset;

    // Sample
    let r_lens = textureSampleLevel(readTexture, u_sampler, r_uv_lens, 0.0).r;
    let g_lens = textureSampleLevel(readTexture, u_sampler, g_uv_lens, 0.0).g;
    let b_lens = textureSampleLevel(readTexture, u_sampler, b_uv_lens, 0.0).b;
    let col_lens = vec4<f32>(r_lens, g_lens, b_lens, 1.0);

    let col_bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Composite
    var final_color = mix(col_bg, col_lens, in_lens);

    // Grid Overlay
    if (in_lens > 0.01 && grid_opacity > 0.0) {
        let grid_uv = (uv_zoomed - mouse) * 20.0 * magnification; // Scale grid with zoom so it looks attached to world?
        // No, let's make the grid attached to the lens UI.
        let grid_ui_uv = dist_vec_aspect * 20.0; // Grid fixed to lens

        let grid_lines = abs(fract(grid_ui_uv - 0.5) - 0.5);
        let line_mask = smoothstep(0.45, 0.48, max(grid_lines.x, grid_lines.y));

        // Circular Rings in grid
        let ring_dist = length(grid_ui_uv); // 0..radius*20
        let ring_lines = abs(fract(ring_dist) - 0.5);
        let ring_mask = smoothstep(0.45, 0.48, ring_lines);

        let grid_combined = max(line_mask, ring_mask);

        final_color = mix(final_color, vec4<f32>(0.0, 1.0, 1.0, 1.0), grid_combined * grid_opacity * in_lens * 0.3);
    }

    // Lens Border Ring
    let border = smoothstep(edge_width, 0.0, abs(dist - radius));
    final_color = mix(final_color, vec4<f32>(0.2, 0.9, 1.0, 1.0), border);

    // Vignette / Dimming outside lens to focus attention (Optional, maybe subtle)
    let vignette = smoothstep(radius, radius + 0.2, dist);
    final_color = mix(final_color, final_color * 0.6, vignette * 0.5);

    textureStore(writeTexture, global_id.xy, final_color);

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
