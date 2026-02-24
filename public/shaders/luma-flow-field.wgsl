// Luma Flow Field - Simulation
// Features: flow field, luminance driven, simulation
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn getLuma(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(textureDimensions(readTexture));
    let id = vec2<i32>(global_id.xy);
    if (id.x >= i32(resolution.x) || id.y >= i32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(id) / resolution;

    // Sample previous frame for feedback
    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Calculate flow based on luminance gradient
    let e = 1.0 / resolution;
    let luma = getLuma(color);
    let luma_r = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(e.x, 0.0), 0.0).rgb);
    let luma_u = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, e.y), 0.0).rgb);

    let grad = vec2<f32>(luma_r - luma, luma_u - luma) * 10.0;

    // Displace UV based on flow
    let displacement = grad * u.zoom_params.x * 0.1;
    let new_uv = uv + displacement;

    // Read from displaced position
    let new_color = textureSampleLevel(readTexture, u_sampler, new_uv, 0.0).rgb;

    // Fade and update
    color = mix(color, new_color, 0.9);
    color *= 0.99; // decay

    textureStore(writeTexture, id, vec4<f32>(color, 1.0));
}
