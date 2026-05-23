// ═══════════════════════════════════════════════════════════════════
//  Soft Vignette Bloom
//  Category: image
//  Features: upgraded-rgba, bloom, cinematic
//  Complexity: Medium
//  Created: 2026-05-23
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / res;
    let texel = 1.0 / res;

    let vignetteStrength = u.zoom_params.x;
    let bloomRadius = u.zoom_params.y;
    let temperature = u.zoom_params.z;
    let bloomIntensity = u.zoom_params.w;

    let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var col = base.rgb;
    let baseAlpha = base.a;

    // Simple box blur bloom on bright areas
    var bloom = vec3<f32>(0.0);
    let r = max(bloomRadius * 2.0, 1.0);
    var bloomSamples = 0.0;
    for (var dy = -2; dy <= 2; dy = dy + 1) {
        for (var dx = -2; dx <= 2; dx = dx + 1) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * texel * r;
            let sample = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
            let luma = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
            let brightMask = smoothstep(0.4, 0.8, luma);
            bloom = bloom + sample * brightMask;
            bloomSamples = bloomSamples + brightMask;
        }
    }
    if (bloomSamples > 0.0) {
        bloom = bloom / bloomSamples;
    }
    col = col + bloom * bloomIntensity * 0.5;

    // Color temperature shift
    let warm = vec3<f32>(1.05, 0.95, 0.85);
    let cool = vec3<f32>(0.85, 0.92, 1.05);
    let tempShift = mix(cool, warm, temperature * 0.5 + 0.5);
    col = col * tempShift;

    // Soft vignette
    let centerDist = length(uv - vec2<f32>(0.5));
    let vignette = smoothstep(0.7, 0.3, centerDist * (1.0 + vignetteStrength));
    col = col * vignette;

    // Subtle radial gradient tint
    let tintHue = fract(temperature * 0.05 + 0.05);
    let tintColor = vec3<f32>(
        0.95 + tintHue * 0.1,
        0.95 + (1.0 - abs(tintHue - 0.5) * 2.0) * 0.05,
        0.95 + (1.0 - tintHue) * 0.1
    );
    col = col * mix(vec3<f32>(1.0), tintColor, centerDist * vignetteStrength * 0.3);

    let finalColor = vec4<f32>(clamp(col, vec3<f32>(0.0), vec3<f32>(1.0)), baseAlpha);

    textureStore(writeTexture, coords, finalColor);
}
