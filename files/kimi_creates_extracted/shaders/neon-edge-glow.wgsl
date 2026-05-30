// ═══════════════════════════════════════════════════════════════════
//  Neon Edge Glow
//  Category: visual-effects
//  Features: post-processing, edge-detection, neon-glow, bloom
//  Complexity: Medium
//  Created: 2026-05-31
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

const PI: f32 = 3.141592653589793;

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let pixel = vec2<f32>(1.0) / resolution;

    let edgeStrength = u.zoom_params.x * 4.0;
    let glowRadius = u.zoom_params.y * 0.04 + 0.005;
    let neonTint = u.zoom_params.z;
    let glowIntensity = u.zoom_params.w * 2.0;

    // Sobel edge detection
    let s00 = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-pixel.x, -pixel.y), 0.0).rgb);
    let s01 = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -pixel.y), 0.0).rgb);
    let s02 = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixel.x, -pixel.y), 0.0).rgb);
    let s10 = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-pixel.x, 0.0), 0.0).rgb);
    let s12 = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixel.x, 0.0), 0.0).rgb);
    let s20 = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-pixel.x, pixel.y), 0.0).rgb);
    let s21 = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixel.y), 0.0).rgb);
    let s22 = luminance(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixel.x, pixel.y), 0.0).rgb);

    let sobelX = (-s00 + s02) + (-2.0 * s10 + 2.0 * s12) + (-s20 + s22);
    let sobelY = (-s00 - 2.0 * s01 - s02) + (s20 + 2.0 * s21 + s22);
    let edgeMag = sqrt(sobelX * sobelX + sobelY * sobelY) * edgeStrength;

    // Glow: radial blur at detected edges
    var glow = vec3<f32>(0.0);
    let glowSamples = 8;
    for (var i: i32 = 0; i < glowSamples; i = i + 1) {
        let angle = f32(i) / f32(glowSamples) * 2.0 * PI;
        let dir = vec2<f32>(cos(angle), sin(angle));
        let sampleUV = clamp(uv + dir * glowRadius, vec2<f32>(0.0), vec2<f32>(1.0));
        let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let sampleEdge = luminance(sampleColor);
        // Weight by edge magnitude
        let weight = smoothstep(0.05, 0.2, sampleEdge) * (1.0 / f32(glowSamples));
        glow += sampleColor * weight;
    }

    // Neon color from edge angle
    let edgeAngle = atan2(sobelY, sobelX);
    let hue = fract((edgeAngle / (2.0 * PI)) + time * 0.02 + neonTint);
    let neonColor = vec3<f32>(
        0.5 + 0.5 * cos(hue * 6.283 + 0.0),
        0.5 + 0.5 * cos(hue * 6.283 + 2.094),
        0.5 + 0.5 * cos(hue * 6.283 + 4.189)
    );

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Composite: base + neon edges + glow
    let edgeMask = smoothstep(0.02, 0.15, edgeMag);
    let neonLine = neonColor * edgeMask * glowIntensity;
    let glowBloom = glow * glowIntensity * 0.5 * edgeMask;

    let finalColor = baseColor + neonLine + glowBloom;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
