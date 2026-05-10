// ═══════════════════════════════════════════════════════════════════
//  Volumetric God Rays
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive
//  Complexity: Medium
//  Phase A Upgrade Swarm
//  Created: 2026-05-10
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
  zoom_params: vec4<f32>,  // x=Density, y=Decay, z=Weight, w=Exposure
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
    var mousePos = u.zoom_config.yz;

    let bass = plasmaBuffer[0].x;
    let density = max(u.zoom_params.x, 0.001);
    let decay = clamp(u.zoom_params.y, 0.0, 1.0);
    let weight = u.zoom_params.z * (1.0 + bass * 0.3);
    let exposure = clamp(u.zoom_params.w, 0.0, 1.0);

    let numSamples = 64;
    let deltaTextCoord = (uv - mousePos);
    let step = (deltaTextCoord * density) / f32(numSamples);

    var currentUV = uv;
    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    var illuminationDecay = 1.0;
    var accumulatedColor = vec4<f32>(0.0);

    for (var i = 0; i < numSamples; i++) {
        currentUV = currentUV - step;
        var sampleColor = textureSampleLevel(readTexture, u_sampler, currentUV, 0.0);
        sampleColor = sampleColor * illuminationDecay * weight;
        accumulatedColor = accumulatedColor + sampleColor;
        illuminationDecay = illuminationDecay * decay;
    }

    let finalColor = (color * ((1.0 - exposure) + 0.5)) + (accumulatedColor * exposure);

    // Alpha encodes ray accumulation strength — bright ray zones = higher blend weight
    let ray_luma = dot(accumulatedColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let base_luma = dot(finalColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.4 + ray_luma * exposure * 2.0 + base_luma * 0.2, 0.0, 1.0);

    textureStore(writeTexture, coords, vec4<f32>(finalColor.rgb, alpha));

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(d, 0.0, 0.0, 0.0));
}
