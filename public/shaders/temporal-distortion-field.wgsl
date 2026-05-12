@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Previous Frame
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=FieldRadius, y=TimeLag, z=Ghosting, w=WarpStrength
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    let radius = u.zoom_params.x;
    let time_lag = u.zoom_params.y;
    let ghosting = u.zoom_params.z;
    let warp_strength = u.zoom_params.w * (1.0 + bass * 0.2);

    var mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    let field = smoothstep(radius + 0.2, radius, dist);

    let angle = atan2(dist_vec.y, dist_vec.x);
    let twist = sin(dist * 10.0 - time * 2.0) * warp_strength * field;
    let warped_uv = uv + vec2<f32>(cos(angle + twist), sin(angle + twist)) * 0.01 * warp_strength;

    let current_color = textureSampleLevel(readTexture, u_sampler, warped_uv, 0.0);
    let prev_color = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    let base_rate = mix(0.05, 1.0, 1.0 - time_lag);
    let update_rate = mix(base_rate, 1.0, field);
    let final_mix = update_rate * (1.0 - ghosting * 0.5);

    let new_pixel = mix(prev_color, current_color, final_mix);

    let shimmer = sin(uv.y * 100.0 + time * 10.0) * 0.05 * (1.0 - field) * ghosting;
    let final_color = new_pixel.rgb + vec3<f32>(shimmer);

    // Alpha: temporal field strength and ghosting drive blend compositing weight
    let luma = dot(final_color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(field * 0.4 + ghosting * 0.3 + luma * 0.3, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(final_color, alpha));
    textureStore(dataTextureA, coord, new_pixel);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
