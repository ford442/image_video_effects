struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
}

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = vec2<f32>(u.config.zw);
    var uv = vec2<f32>(global_id.xy) / dimensions;

    // Parameters
    let drift_speed = u.zoom_params.x; // 0.0 to 0.05
    let slit_width = u.zoom_params.y; // 0.001 to 0.1
    let time_scale = u.zoom_params.z; // 0.0 to 1.0
    let decay = u.zoom_params.w;      // 0.9 to 1.0 (Trail persistence)

    var mouse = u.zoom_config.yz;
    let aspect = dimensions.x / dimensions.y;

    // Audio reactivity on drift speed
    let audioPulse = 1.0 + plasmaBuffer[0].x * 0.5;

    // Calculate sampling coordinate for history (drifted)
    let drift = vec2<f32>(drift_speed * 0.1 * audioPulse, 0.0);
    let history_uv = fract(uv + drift); // Wrap around

    // Sample history
    var history_color = textureSampleLevel(dataTextureC, u_sampler, history_uv, 0.0);

    // Sample current input
    let input_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Determine slit position
    let slit_center = mouse.x;

    // Check if we are inside the slit
    let dist_x = abs(uv.x - slit_center);

    var final_color = history_color * decay;

    // If inside slit, update with new frame
    if (dist_x < slit_width) {
        final_color = input_color;
    }

    // Write to output and history
    textureStore(writeTexture, vec2<i32>(global_id.xy), final_color);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), final_color);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
