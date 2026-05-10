// ═══════════════════════════════════════════════════════════════════
//  Virtual Lens
//  Category: image
//  Features: mouse-driven, chromatic-aberration, audio-reactive
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Phase A Upgrade Swarm
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Magnification, y=Radius, z=Aberration, w=Softness
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coords = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;

    let bass = plasmaBuffer[0].x;
    let magnification = u.zoom_params.x * 0.8 * (1.0 + bass * 0.2);
    let radius = u.zoom_params.y;
    let aberration = u.zoom_params.z * 0.05 * (1.0 + bass * 0.3);
    let softness = u.zoom_params.w * 0.2;

    var uv_corrected = uv;
    uv_corrected.x *= aspect;
    var mouse_corrected = mouse;
    mouse_corrected.x *= aspect;

    let dist = distance(uv_corrected, mouse_corrected);
    let mask = smoothstep(radius + softness, radius, dist);

    var dir = uv - mouse;
    let distortion = sin(mask * 1.57079) * magnification;

    let r_uv = uv - dir * distortion * (1.0 + aberration);
    let g_uv = uv - dir * distortion;
    let b_uv = uv - dir * distortion * (1.0 - aberration);

    let r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, g_uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

    let rim = smoothstep(radius * 0.9, radius, dist) * mask * 0.2;
    var color = vec3<f32>(r, g, b) + vec3<f32>(rim);

    // Alpha: opaque outside lens; inside lens, modulated by luminance and rim glow
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(1.0, clamp(luma * 0.5 + rim * 0.8 + 0.5, 0.0, 1.0), mask);

    textureStore(writeTexture, coords, vec4<f32>(color, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
