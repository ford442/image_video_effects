// ═══════════════════════════════════════════════════════════════════
//  Phantom Lag - Temporal echo / motion trails effect
//  Category: visual-effects
//  Features: upgraded-rgba, depth-aware, temporal-echo, motion-trails
//  Upgraded: 2026-03-22
//  By: Agent 1A - Alpha Channel Specialist
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    var uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);

    let decay = 0.9 + u.zoom_params.x * 0.09;
    let echoX = (u.zoom_params.y - 0.5) * 0.05;
    let echoY = (u.zoom_params.z - 0.5) * 0.05;
    let hueShift = u.zoom_params.w;

    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Sample history with offset
    let historyUV = uv - vec2<f32>(echoX, echoY);
    let history = textureSampleLevel(dataTextureC, u_sampler, historyUV, 0.0);

    // Mix
    var newHistory = mix(current, history, decay);

    // Hue shift on history
    if (hueShift > 0.01) {
        let old = newHistory;
        newHistory.r = mix(old.r, old.g, hueShift * 0.1);
        newHistory.g = mix(old.g, old.b, hueShift * 0.1);
        newHistory.b = mix(old.b, old.r, hueShift * 0.1);
    }

    // Calculate alpha based on history accumulation
    let luma = dot(newHistory.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Higher alpha for brighter, more accumulated areas
    let alpha = mix(0.75, 1.0, luma * decay);
    let depthAlpha = mix(0.6, 1.0, depth);
    let finalAlpha = (alpha + depthAlpha) * 0.5;

    // Output to screen
    textureStore(writeTexture, coord, vec4<f32>(newHistory.rgb, finalAlpha));

    // Output to history buffer
    textureStore(dataTextureA, coord, vec4<f32>(newHistory.rgb, finalAlpha));

    // Pass depth
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
