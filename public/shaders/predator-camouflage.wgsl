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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)),
                   hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)),
                   hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Parameters
    let camou_radius = 0.1 + u.zoom_params.x * 0.4;
    let distortion_strength = 0.01 + u.zoom_params.y * 0.05;
    let shimmer_speed = 2.0 + u.zoom_params.z * 5.0;

    let mouse = u.zoom_config.yz;

    // Calculate distance from mouse (cloaked entity)
    let d_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(d_vec);

    // Create the camouflage mask (1.0 at center, 0.0 at edge)
    // We use a smooth transition at the edge
    let mask = 1.0 - smoothstep(camou_radius * 0.8, camou_radius, dist);

    if (mask <= 0.001) {
        // Optimization: No effect outside radius
        let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
        textureStore(writeTexture, vec2<i32>(global_id.xy), color);
        // Write depth
        let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
        textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
        return;
    }

    let time = u.config.x * shimmer_speed;

    // Generate low frequency noise for bulk distortion
    let n_scale = 10.0;
    let n1 = noise(uv * n_scale + vec2<f32>(time * 0.2, 0.0));
    let n2 = noise(uv * n_scale + vec2<f32>(0.0, time * 0.2));
    let displacement_dir = vec2<f32>(n1, n2) - 0.5;

    // High frequency noise for "glitch/shimmer"
    let hf_noise = noise(uv * 50.0 + time);

    // Calculate displacement
    // Distortion is strongest in the middle but fades at edges
    let displacement = displacement_dir * distortion_strength * mask;

    // Chromatic Aberration
    // Offset channels differently
    let r_off = displacement * (1.0 + 10.0 * distortion_strength);
    let b_off = displacement * (1.0 - 5.0 * distortion_strength);

    let r = textureSampleLevel(readTexture, u_sampler, uv + r_off, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + displacement, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + b_off, 0.0).b;

    var color = vec4<f32>(r, g, b, 1.0);

    // Add specular shimmer
    let shimmer_intensity = smoothstep(0.6, 0.8, hf_noise) * mask * 0.2;
    color = color + vec4<f32>(shimmer_intensity);

    // Add a subtle edge highlight to define the cloaked shape
    let edge_mask = smoothstep(camou_radius * 0.8, camou_radius * 0.85, dist) * (1.0 - smoothstep(camou_radius * 0.95, camou_radius, dist));
    color = mix(color, color + vec4<f32>(0.1), edge_mask);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // Write depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
