// ----------------------------------------------------------------
// Psychedelic Layered Time-Stamps
// Category: generative
// ----------------------------------------------------------------

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

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=DiffusionA, y=DiffusionB, z=Feed, w=Kill
    ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(u.config.zw);

    // Boundary check
    if (coords.x >= res.x || coords.y >= res.y) {
        return;
    }

    let uv = vec2<f32>(coords) / vec2<f32>(res);
    let time = u.config.x;
    let audio = u.config.y;
    let mouse = u.zoom_config.yz;

    let layer_count = i32(u.zoom_params.x * 10.0 + 3.0);
    let delay_scale = u.zoom_params.y;
    let distortion_amp = u.zoom_params.z;

    var final_color = vec3<f32>(0.0);

    // Create rippling distortion based on audio and time
    let dist_offset = vec2<f32>(
        sin(uv.y * 10.0 + time) * distortion_amp * (1.0 + audio * 2.0),
        cos(uv.x * 10.0 + time) * distortion_amp * (1.0 + audio * 2.0)
    );

    let distorted_uv = uv + dist_offset;
    let sample_coords = vec2<i32>(distorted_uv * vec2<f32>(res));

    // Fetch delay info
    let delay_info = textureLoad(dataTextureC, coords, 0);
    let current_delay = delay_info.x + (audio * 0.1);

    // Sample base image with distortion
    let base_color = textureLoad(readTexture, clamp(sample_coords, vec2<i32>(0), res - vec2<i32>(1)), 0).rgb;

    // Calculate layer contribution
    for(var i = 0; i < 10; i++) {
        if (i >= layer_count) { break; }
        let layer_factor = f32(i) / f32(layer_count);

        let color_shift_raw = time * 0.1 + layer_factor;
        let color_shift = color_shift_raw - floor(color_shift_raw);
        let plasma_idx = i32(color_shift * 255.0);
        let plasma_color = plasmaBuffer[plasma_idx].rgb;

        let layer_weight = exp(-current_delay * delay_scale * f32(i));

        final_color += base_color * plasma_color * layer_weight;
    }

    final_color = final_color / f32(layer_count);

    // Mouse interaction - adds local disturbance
    let mouse_dist = distance(uv, mouse);
    if (mouse_dist < 0.1 && u.zoom_config.w > 0.5) {
        final_color += vec3<f32>(1.0 - mouse_dist * 10.0) * audio;
    }

    // Update delay texture (simple temporal evolution)
    // using dataTextureA for tracking
    let delay_track = textureLoad(dataTextureC, coords, 0);
    let delay_raw = delay_track.x + 0.01;
    let new_delay = delay_raw - floor(delay_raw);
    textureStore(dataTextureA, coords, vec4<f32>(new_delay, 0.0, 0.0, 1.0));

    textureStore(writeTexture, coords, vec4<f32>(final_color, 1.0));
}
