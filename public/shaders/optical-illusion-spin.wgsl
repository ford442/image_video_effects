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
    let center = vec2<f32>(0.5, 0.5);
    let aspect = resolution.x / resolution.y;

    // Parameters
    // x: Ring Count (5 to 50)
    // y: Speed (0 to 5.0)
    // z: Twist Strength (-3.0 to 3.0)
    // w: Alternating (0.0 or 1.0) - mixed smoothly? Threshold it.

    let ring_count = u.zoom_params.x * 45.0 + 5.0;
    let speed = u.zoom_params.y * 5.0; // Rotation speed
    let twist_strength = (u.zoom_params.z - 0.5) * 20.0; // -10 to 10
    let alternating = step(0.5, u.zoom_params.w); // 0 or 1

    // Polar Conversion
    let centered_uv = uv - center;
    let corrected_uv = vec2<f32>(centered_uv.x * aspect, centered_uv.y);
    let radius = length(corrected_uv);
    var angle = atan2(corrected_uv.y, corrected_uv.x);

    // Ring Logic
    let ring_index = floor(radius * ring_count);

    // Direction
    // If alternating is 1, even rings go one way, odd go another.
    // If alternating is 0, all go same way? Or maybe random?
    // Let's make param w control "Variation".
    // w < 0.5: All same direction. w > 0.5: Alternating.
    var direction = 1.0;
    if (alternating > 0.5) {
        if (ring_index % 2.0 != 0.0) {
            direction = -1.0;
        }
    }

    // Time based rotation
    let time_rot = u.config.x * speed * direction * 0.5;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouse_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let mouse_dist = length(mouse_vec);

    // Twist effect near mouse
    // The closer to mouse, the more "offset" or "speed boost" we add.
    // Let's add a rotational offset based on mouse distance.
    // Twist creates a vortex-like drag.
    let twist = smoothstep(0.5, 0.0, mouse_dist) * twist_strength;

    // Apply Rotation
    angle += time_rot + twist;

    // Convert back to UV
    let cos_a = cos(angle);
    let sin_a = sin(angle);

    // Rotate the corrected vector
    // New vector (rx, ry)
    // rx = x cos - y sin ... wait, we have radius and angle.
    let rotated_vec = vec2<f32>(cos_a * radius, sin_a * radius);

    // Map back to UV space
    // x = rx / aspect + 0.5
    // y = ry + 0.5
    let new_uv = vec2<f32>(rotated_vec.x / aspect + 0.5, rotated_vec.y + 0.5);

    var color = vec4<f32>(0.0, 0.0, 0.0, 1.0);

    // Bounds check
    if (new_uv.x >= 0.0 && new_uv.x <= 1.0 && new_uv.y >= 0.0 && new_uv.y <= 1.0) {
         color = textureSampleLevel(readTexture, u_sampler, new_uv, 0.0);
    }

    // Ring Borders (optional aesthetic)
    // Darken edges of rings slightly for separation
    let ring_pos = fract(radius * ring_count);
    let border = smoothstep(0.0, 0.1, ring_pos) * smoothstep(1.0, 0.9, ring_pos);
    // color = color * (0.8 + 0.2 * border); // Subtle ring lines

    textureStore(writeTexture, global_id.xy, color);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, new_uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
