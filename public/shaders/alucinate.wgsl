/// Alucinate - Psychedelic interactive warping and color shifting.
/// Warps texture coordinates with flowing sine waves and introduces
/// chromatic aberration that intensifies with mouse interaction.

@group(0) @binding(0) var s: sampler;
@group(0) @binding(1) var inputTexture: texture_2d<f32>;
@group(0) @binding(2) var outputTexture: texture_storage_2d<rgba8unorm, write>;

struct Uniforms {
    time: f32,
    ripple_count: f32,
    mouse: vec4<f32>,
    config: vec4<f32>, // x: zoom, y: unused, z: width, w: height
    audio: vec4<f32>, // x: bass, y: mid, z: treble, w: volume
};
@group(0) @binding(3) var<uniform> u: Uniforms;

@group(0) @binding(4) var depthTexture: texture_2d<f32>;
@group(0) @binding(5) var linearSampler: sampler;
@group(0) @binding(6) var depthOutputTexture: texture_storage_2d<r32float, write>;

@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba16float, read_write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba16float, read_write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extra: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var plasmaTexture: texture_2d<f32>;

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(outputTexture);
    if (global_id.x >= dims.x || global_id.y >= dims.y) {
        return;
    }

    let uv = vec2<f32>(f32(global_id.x) / f32(dims.x), f32(global_id.y) / f32(dims.y));
    let time = u.time * 0.5;

    let mouse_uv = u.mouse.xy / u.config.zw;
    let mouse_active = u.mouse.z > 0.0;
    let dist_to_mouse = distance(uv, mouse_uv);
    let mouse_effect = smoothstep(0.3, 0.0, dist_to_mouse) * f32(mouse_active);

    let warp_freq = mix(4.0, 10.0, mouse_effect);
    let warp_amp = mix(0.02, 0.1, mouse_effect);
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let radius = distance(uv, vec2(0.5));
    let warp_offset_x = sin(uv.y * warp_freq - time) * cos(radius * 10.0 + time) * warp_amp;
    let warp_offset_y = cos(uv.x * warp_freq + time) * sin(radius * 10.0 - time) * warp_amp;
    let warped_uv = uv + vec2(warp_offset_x, warp_offset_y);

    let shift_amount = mix(0.005, 0.02, mouse_effect) * sin(time * 2.0);
    let r = textureSample(inputTexture, s, warped_uv + vec2(shift_amount, shift_amount)).r;
    let g = textureSample(inputTexture, s, warped_uv).g;
    let b = textureSample(inputTexture, s, warped_uv - vec2(shift_amount, shift_amount)).b;

    textureStore(outputTexture, global_id.xy, vec4<f32>(r, g, b, 1.0));
}