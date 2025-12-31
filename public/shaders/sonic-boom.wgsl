
struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

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
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dim = textureDimensions(readTexture);
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));

    if (coord.x >= i32(dim.x) || coord.y >= i32(dim.y)) {
        return;
    }

    let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
    let aspect = vec2<f32>(f32(dim.x) / f32(dim.y), 1.0);

    // Parameters
    let radius = u.zoom_params.x;     // Ring Radius
    let width = u.zoom_params.y;      // Ring Width
    let strength = u.zoom_params.z;   // Distortion Strength
    let split = u.zoom_params.w;      // Chromatic Split

    // Mouse Position
    let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    // Calculate distance to mouse (corrected for aspect ratio for circular ring)
    let to_pixel = (uv - mouse_pos) * aspect;
    let dist = length(to_pixel);

    // Normalize to_pixel direction
    var dir = vec2<f32>(0.0, 0.0);
    if (dist > 0.0001) {
        dir = to_pixel / dist;
    }

    // Calculate ring influence
    // smoothstep creates a soft transition. We want a peak at 'radius' with width 'width'.
    let inner_edge = radius - width * 0.5;
    let outer_edge = radius + width * 0.5;

    // Gaussian-like curve approximation for the ring profile
    let x_val = (dist - radius) / (width * 0.5);
    let ring_intensity = exp(-x_val * x_val * 4.0); // Bell curve

    // Distortion vector: pushes pixels outwards from the ring center
    let distortion = dir * ring_intensity * strength * 0.1;

    // Chromatic Aberration: sample R, G, B at slightly different offsets along the distortion vector

    let uv_r = uv - distortion * (1.0 + split * 10.0);
    let uv_g = uv - distortion;
    let uv_b = uv - distortion * (1.0 - split * 10.0);

    // Sample texture with filtering
    let r_val = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
    let g_val = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
    let b_val = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

    textureStore(writeTexture, coord, vec4<f32>(r_val, g_val, b_val, 1.0));
}
