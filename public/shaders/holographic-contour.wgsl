
struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

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
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dim = textureDimensions(readTexture);
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));

    if (coord.x >= i32(dim.x) || coord.y >= i32(dim.y)) {
        return;
    }

    let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(dim.x), f32(dim.y));

    // Parameters
    let threshold = u.zoom_params.x;     // Edge Threshold
    let glow_strength = u.zoom_params.y; // Glow Strength
    let shift_amount = u.zoom_params.z;  // Hologram Shift
    let dim_bg = u.zoom_params.w;        // Darken Background

    // Mouse Position (u.zoom_config.y = x, u.zoom_config.z = y)
    let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    // Sobel Edge Detection
    let dx = vec2<i32>(1, 0);
    let dy = vec2<i32>(0, 1);

    let c = textureLoad(readTexture, coord, 0).rgb;
    let l = textureLoad(readTexture, coord - dx, 0).rgb;
    let r = textureLoad(readTexture, coord + dx, 0).rgb;
    let t = textureLoad(readTexture, coord - dy, 0).rgb;
    let b = textureLoad(readTexture, coord + dy, 0).rgb;

    let edge_x = length(r - l);
    let edge_y = length(b - t);
    let edge = sqrt(edge_x * edge_x + edge_y * edge_y);

    var final_color = c * (1.0 - dim_bg); // Dimmed original background

    if (edge > threshold) {
        // Holographic Effect: Color shifts based on angle to mouse
        let to_mouse = uv - mouse_pos;
        let angle = atan2(to_mouse.y, to_mouse.x);
        let dist = length(to_mouse);

        // Create RGB split based on angle and shift
        let shift_vec = vec2<f32>(cos(angle), sin(angle)) * shift_amount * (1.0 - dist); // More shift closer to mouse? Or consistent?
        // Let's make shift depend on mouse distance inverted (stronger near mouse) or just constant.
        // Let's try constant direction based on mouse relative to pixel.

        // Sampling for chromatic aberration on edges
        // We can't easily resample the 'edge' value without recomputing, but we can fake it by coloring the edge value we have.

        let hue = fract(angle / 6.28 + u.config.x * 0.1); // Rotate hue over time

        // Simple spectral colors
        let r_val = 0.5 + 0.5 * cos(6.28 * (hue + 0.0));
        let g_val = 0.5 + 0.5 * cos(6.28 * (hue + 0.33));
        let b_val = 0.5 + 0.5 * cos(6.28 * (hue + 0.67));

        let edge_color = vec3<f32>(r_val, g_val, b_val) * glow_strength * (edge - threshold) * 5.0;

        final_color += edge_color;
    }

    textureStore(writeTexture, coord, vec4<f32>(final_color, 1.0));
}
