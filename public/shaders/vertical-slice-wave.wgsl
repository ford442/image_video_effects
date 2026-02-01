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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
	var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let strips_param = u.zoom_params.x;    // Strip Count
    let speed_param = u.zoom_params.y;     // Base Speed
    let rgb_split = u.zoom_params.z;       // RGB Split
    let jitter_amt = u.zoom_params.w;      // Jitter

    let time = u.config.x;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    // Mouse X maps to Frequency (0.0 to 1.0 -> 1.0 to 50.0)
    let freq_mod = mouse.x * 40.0 + 1.0;
    // Mouse Y maps to Amplitude (0.0 to 1.0 -> 0.0 to 0.5)
    let amp_mod = mouse.y * 0.2;

    let num_strips = floor(strips_param * 100.0) + 5.0; // Min 5 strips
    let strip_id = floor(uv.x * num_strips);
    let strip_uv_x = strip_id / num_strips; // Normalized x of the strip

    // Base wave
    let wave_speed = speed_param * 5.0;
    let wave_phase = strip_uv_x * freq_mod + time * wave_speed;
    var offset = sin(wave_phase) * amp_mod;

    // Jitter (flicker noise)
    let noise_val = hash12(vec2<f32>(strip_id, floor(time * 10.0))); // Random per strip per 0.1s
    offset = offset + (noise_val - 0.5) * jitter_amt * 0.2;

    // RGB Split
    let split_factor = rgb_split * 0.05; // Max split 0.05 UV space

    let r_offset = offset - split_factor;
    let g_offset = offset;
    let b_offset = offset + split_factor;

    // Sample
    // We only offset Y
    let r = textureSampleLevel(readTexture, u_sampler, vec2<f32>(uv.x, uv.y + r_offset), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, vec2<f32>(uv.x, uv.y + g_offset), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, vec2<f32>(uv.x, uv.y + b_offset), 0.0).b;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(r, g, b, 1.0));
}
