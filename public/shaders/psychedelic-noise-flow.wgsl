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

// Simple pseudo-random hash
fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

// 2D Noise
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(mix(dot(hash2(i + vec2<f32>(0.0, 0.0)), f - vec2<f32>(0.0, 0.0)),
                   dot(hash2(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0)), u.x),
               mix(dot(hash2(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0)),
                   dot(hash2(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0)), u.x), u.y);
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
    let speed_param = u.zoom_params.x;     // Flow Speed
    let scale_param = u.zoom_params.y;     // Noise Scale
    let distort_param = u.zoom_params.z;   // Distortion Strength
    let color_shift = u.zoom_params.w;     // Color Separation

    let time = u.config.x * (speed_param * 2.0 + 0.1);
    let noise_scale = scale_param * 8.0 + 1.0;
    let strength = distort_param * 0.1;

    let mouse = u.zoom_config.yz;
    let mouse_dist = length((uv - mouse) * vec2<f32>(aspect, 1.0));

    // Mouse influence: add extra flow speed/direction near mouse
    let mouse_dir = normalize(uv - mouse + vec2<f32>(0.001));
    let mouse_influence = smoothstep(0.4, 0.0, mouse_dist);

    // Three distinct noise samples for R, G, B
    // We offset the noise coordinate by time and by channel

    // Red Channel Noise
    let n_r = noise(uv * noise_scale + vec2<f32>(time, time * 0.5) - mouse_influence * mouse_dir);
    // Green Channel Noise (Different phase)
    let n_g = noise(uv * noise_scale + vec2<f32>(time + 10.0, time * 0.6 + 10.0) + mouse_influence * mouse_dir * 0.5);
    // Blue Channel Noise (Different phase)
    let n_b = noise(uv * noise_scale + vec2<f32>(time + 20.0, time * 0.7 + 20.0));

    // Calculate displacement vectors
    let d_r = vec2<f32>(n_r, noise(uv * noise_scale + vec2<f32>(n_r, time))) * strength;
    let d_g = vec2<f32>(n_g, noise(uv * noise_scale + vec2<f32>(n_g, time + 5.0))) * strength;
    let d_b = vec2<f32>(n_b, noise(uv * noise_scale + vec2<f32>(n_b, time + 10.0))) * strength;

    // Apply color separation based on parameter
    // If param is 0, displacements are similar. If 1, they diverge.
    let final_d_r = d_r;
    let final_d_g = mix(d_r, d_g, color_shift);
    let final_d_b = mix(d_r, d_b, color_shift);

    // Sample Texture
    let r = textureSampleLevel(readTexture, u_sampler, uv + final_d_r, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + final_d_g, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + final_d_b, 0.0).b;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(r, g, b, 1.0));
}
