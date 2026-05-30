// ═══════════════════════════════════════════════════════════════════
//  Anamorphic Flare
//  Category: visual-effects
//  Features: post-processing, anamorphic, lens-flare, bloom
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let threshold = u.zoom_params.x;
    let streakLength = u.zoom_params.y * 0.3 + 0.02;
    let intensity = u.zoom_params.z * 3.0;
    let tintAmount = u.zoom_params.w;

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luminance = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));

    // Anamorphic blur: sample along horizontal axis at bright spots
    var streakColor = vec3<f32>(0.0);
    var totalWeight = 0.0;

    let sampleCount = 16;
    for (var i: i32 = -sampleCount; i <= sampleCount; i = i + 1) {
        let offset = f32(i) / f32(sampleCount);
        let weight = exp(-abs(offset) * 3.0);
        let sampleUV = clamp(uv + vec2<f32>(offset * streakLength, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
        let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let sampleLum = dot(sampleColor, vec3<f32>(0.299, 0.587, 0.114));

        // Only bright areas contribute
        let brightMask = smoothstep(threshold, threshold + 0.3, sampleLum);
        streakColor += sampleColor * brightMask * weight;
        totalWeight += brightMask * weight;
    }

    if (totalWeight > 0.0) {
        streakColor /= totalWeight;
    }

    // Anamorphic tint (cyan/blue horizontal, warm vertical)
    let anamorphicTint = vec3<f32>(0.7, 0.85, 1.0);
    streakColor *= mix(vec3<f32>(1.0), anamorphicTint, tintAmount);

    // Star burst from bright center points
    var starBurst = vec3<f32>(0.0);
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 1.5) {
            let pos = ripple.xy;
            let d = length(uv - pos);
            let starSize = 0.008 * (1.0 + elapsed);
            let starFade = 1.0 - elapsed / 1.5;
            let star = exp(-d * d / (starSize * starSize)) * starFade * intensity;
            let starColor = vec3<f32>(1.0, 0.95, 0.8) * star;
            starBurst += starColor;
        }
    }

    let finalColor = baseColor + streakColor * intensity * 0.5 + starBurst;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
