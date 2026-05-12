// ═══════════════════════════════════════════════════════════════════
//  Spectral Waves
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, image
//  Complexity: Medium
//  Chunks From: original spectral-waves
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
  zoom_params: vec4<f32>,  // x=Frequency, y=Speed, z=MaxAmplitude, w=Aberration
  ripples: array<vec4<f32>, 50>,
};

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = u.config.zw;
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }
    let coords = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / dims;
    let aspect = dims.x / dims.y;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let frequency = 10.0 + u.zoom_params.x * 90.0;
    let speed = u.zoom_params.y * 5.0;
    let maxAmplitude = u.zoom_params.z * 0.1 * (1.0 + bass * 0.3);
    let aberration = u.zoom_params.w * 0.05;

    var mousePos = u.zoom_config.yz;

    let uv_c = vec2<f32>(uv.x * aspect, uv.y);
    let mouse_c = vec2<f32>(mousePos.x * aspect, mousePos.y);
    let dist = distance(uv_c, mouse_c);

    let centerColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = getLuminance(centerColor);

    let wave = sin(dist * frequency - time * speed);
    let displacement = wave * maxAmplitude * luma;

    let safeDir = select(vec2<f32>(0.0), normalize(uv_c - mouse_c), dist > 0.001);

    let uv_r = uv - safeDir * displacement * (1.0 + aberration);
    let uv_g = uv - safeDir * displacement;
    let uv_b = uv - safeDir * displacement * (1.0 - aberration);

    let r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

    var finalColor = vec3<f32>(r, g, b);
    let highlight = smoothstep(0.8, 1.0, wave) * luma * 0.5;
    finalColor += vec3<f32>(highlight);

    // Alpha encodes wave crest brightness — peaks = higher compositing weight
    let wave_pos = clamp(wave * 0.5 + 0.5, 0.0, 1.0);
    let final_luma = getLuminance(finalColor);
    let alpha = clamp(0.4 + wave_pos * 0.3 + final_luma * 0.3, 0.0, 1.0);

    textureStore(writeTexture, coords, vec4<f32>(finalColor, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
