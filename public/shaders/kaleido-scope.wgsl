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

    // Params
    // x: Segments (3 to 20?)
    // y: Rotation Speed
    // z: Zoom
    // w: Offset

    let segments_param = u.zoom_params.x; // 0.0-1.0
    let rot_speed = u.zoom_params.y;
    let zoom = u.zoom_params.z;
    let offset_param = u.zoom_params.w;

    let num_segments = 3.0 + floor(segments_param * 12.0); // 3 to 15

    // Mouse Interaction: Center of Kaleidoscope
    let mouse = u.zoom_config.yz;

    // Coords relative to mouse, aspect corrected
    let rel_uv = uv - mouse;
    let aspect_uv = vec2<f32>(rel_uv.x * aspect, rel_uv.y);

    // Polar coordinates
    let dist = length(aspect_uv);
    var angle = atan2(aspect_uv.y, aspect_uv.x);

    // Kaleidoscope Logic
    let segment_angle = 6.28318 / num_segments;

    // Rotate over time
    let time = u.config.x * (rot_speed - 0.5) * 2.0; // -1 to 1 speed
    angle = angle + time;

    // Mirroring
    // Map angle to 0..segment_angle
    // Modulo logic in WGSL: a - b * floor(a/b)
    angle = angle - segment_angle * floor(angle / segment_angle);
    // Mirror if > half segment
    if (angle > segment_angle * 0.5) {
        angle = segment_angle - angle;
    }

    // Reconstruct vector
    // Zoom/Scale
    let scale = 0.5 + (1.0 - zoom) * 2.0; // Zoom in means smaller scale value? No, small scale means we see less.
    // If zoom is 1.0 -> scale should be small (zoom in).
    // Let's say param z=1.0 is "Zoom In" -> scale=0.2
    // z=0.0 is "Zoom Out" -> scale=2.0
    let final_scale = 2.0 - zoom * 1.8;

    let radius = dist * final_scale;

    // Offset (Ring effect)
    let ring_offset = offset_param * 0.5;
    let final_radius = radius + ring_offset;

    let new_vec = vec2<f32>(cos(angle), sin(angle)) * final_radius;

    // Rotate back? Or just use as is relative to something?
    // We need to map back to UV space.
    // Let's add the mouse pos back to center it there?
    // Or center it at 0.5, 0.5?
    // Usually Kaleidoscope looks into the image.
    // Let's center sample at 0.5, 0.5.

    let sample_uv = vec2<f32>(0.5, 0.5) + vec2<f32>(new_vec.x / aspect, new_vec.y);

    var color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;

    // Bounds check or mirror repeat?
    // Sampler defaults to repeat usually.

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
