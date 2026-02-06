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
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let scan_speed = u.zoom_params.x;
    let scan_width = u.zoom_params.y;
    let decay = u.zoom_params.z;
    let softness = u.zoom_params.w;

    // Calculate aspect ratio corrected distance from mouse
    let aspect = resolution.x / resolution.y;

    // Handle mouse not present (negative values)
    var center = mouse;
    if (center.x < 0.0) {
        center = vec2<f32>(0.5, 0.5);
    }

    let dist_vec = (uv - center) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Scan radius moves over time
    // We want it to loop every few seconds depending on speed
    // Speed 0 -> Slow, Speed 1 -> Fast
    let loop_speed = mix(0.1, 2.0, scan_speed);
    let radius = fract(time * loop_speed);

    // Scale radius to cover screen (max dist from center to corner is approx 1.4 * aspect)
    let max_dist = 1.5 * aspect;
    let current_scan_dist = radius * max_dist;

    let delta = abs(dist - current_scan_dist);
    let width = scan_width * 0.5; // Base width

    let current_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    // dataTextureC contains the previous frame (feedback)
    var history_color = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Determine if we are updating this pixel
    // Using smoothstep for softness
    let half_width = width * 0.5;
    let soft_edge = softness * half_width;

    var update_factor = 0.0;

    if (delta < half_width) {
        if (softness > 0.001) {
            update_factor = smoothstep(half_width, half_width - soft_edge, delta);
        } else {
            update_factor = 1.0;
        }
    }

    var final_color = mix(history_color, current_color, update_factor);

    // Apply decay (slowly fade to current time everywhere)
    if (decay > 0.0) {
        final_color = mix(final_color, current_color, decay * 0.05);
    }

    textureStore(writeTexture, global_id.xy, final_color);

    // Write to history for next frame
    // We use dataTextureA for the "next" history buffer
    textureStore(dataTextureA, global_id.xy, final_color);

    // Pass depth through
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
