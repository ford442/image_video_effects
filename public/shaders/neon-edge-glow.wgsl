// ═══════════════════════════════════════════════════════════════════
//  Neon Edge Glow
//  Category: visual-effects
//  Features: edge-glow, neon, bloom, sobel, audio-reactive, post-processing, semantic-alpha
//  Complexity: Medium
//  Created: 2026-05-30
//  Updated: 2026-06-01
//  By: Kimi Agent (integrated + upgraded for semantic alpha + modern header)
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

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let edgeStrength = u.zoom_params.x;
    let glowRadius = u.zoom_params.y;
    let neonTint = u.zoom_params.z;
    let intensity = u.zoom_params.w;

    // Audio
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));

    // Simple Sobel edge detection
    let texel = 1.0 / resolution;
    let l  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb, vec3<f32>(0.299,0.587,0.114));
    let r  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( texel.x, 0.0), 0.0).rgb, vec3<f32>(0.299,0.587,0.114));
    let t  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb, vec3<f32>(0.299,0.587,0.114));
    let b  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0,  texel.y), 0.0).rgb, vec3<f32>(0.299,0.587,0.114));

    let edgeMag = length(vec2<f32>(l - r, t - b)) * edgeStrength * (1.0 + bass * 0.4);

    // Neon color cycling
    let hue = fract(time * 0.12 + neonTint * 0.6 + mids * 0.3);
    let neonColor = vec3<f32>(
        0.5 + 0.5 * cos(hue * 6.283 + 0.0),
        0.5 + 0.5 * cos(hue * 6.283 + 2.094),
        0.5 + 0.5 * cos(hue * 6.283 + 4.189)
    );

    let edgeMask = smoothstep(0.02, 0.18, edgeMag);
    let neonLine = neonColor * edgeMask * intensity * (0.7 + treble * 0.6);

    // Soft glow around edges
    let glow = smoothstep(0.0, glowRadius * 0.08, edgeMag) * (1.0 - smoothstep(glowRadius * 0.04, glowRadius * 0.12, edgeMag));
    let glowBloom = glow * intensity * 0.45 * neonColor;

    let finalColor = baseColor + neonLine + glowBloom;

    // Semantic alpha - stronger where the neon effect is active
    let effectStrength = edgeMask * 0.6 + glow * 0.4;
    let semantic_alpha = clamp(0.55 + effectStrength * 0.65, 0.45, 1.0);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, semantic_alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}