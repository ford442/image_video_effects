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
  zoom_params: vec4<f32>,  // x=Frequency, y=Amplitude, z=Speed, w=Separation
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
    let freq = u.zoom_params.x * 50.0 + 10.0;
    let amp = u.zoom_params.y * 0.05;
    let speed = u.zoom_params.z * 5.0;
    let separation = u.zoom_params.w * 0.5;

    // Mouse
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let to_mouse = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(to_mouse);

    // Wave function
    let phase = dist * freq - u.config.x * speed;
    let decay = exp(-dist * 3.0); // Decay with distance from mouse

    // RGB split logic
    // Each channel samples a slightly different phase or offset
    let wave_r = sin(phase) * amp * decay;
    let wave_g = sin(phase + separation) * amp * decay;
    let wave_b = sin(phase + separation * 2.0) * amp * decay;

    let dir = normalize(to_mouse);
    // Handle center case
    let safe_dir = select(dir, vec2<f32>(1.0, 0.0), dist < 0.001);

    let uv_r = uv + safe_dir * wave_r;
    let uv_g = uv + safe_dir * wave_g;
    let uv_b = uv + safe_dir * wave_b;

    let col_r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
    let col_g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
    let col_b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

    textureStore(writeTexture, global_id.xy, vec4<f32>(col_r, col_g, col_b, 1.0));
}
