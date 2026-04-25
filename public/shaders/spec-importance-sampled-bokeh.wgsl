// ═══════════════════════════════════════════════════════════════════
//  spec-importance-sampled-bokeh
//  Category: advanced-hybrid
//  Features: importance-sampling, bokeh, HDR
//  Complexity: High
//  Chunks From: chunk-library (hash22)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  Importance-Sampled Bokeh Blur
//  Bokeh blur where sample distribution is guided by image brightness.
//  Bright pixels act as point light sources creating bokeh highlights.
//  Uses golden angle spiral with importance weighting.
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    let radius = mix(0.01, 0.08, u.zoom_params.x);
    let shapePower = mix(0.5, 4.0, u.zoom_params.y);
    let brightnessBoost = mix(0.5, 3.0, u.zoom_params.z);
    let chromaAmount = mix(0.0, 0.05, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Mouse controls focal point
    var focalUV = uv;
    if (isMouseDown) {
        focalUV = mousePos;
    }

    // Golden angle spiral sampling with importance weighting
    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;
    let sampleCount = 48;

    for (var i: i32 = 0; i < sampleCount; i = i + 1) {
        let angle = f32(i) * 2.39996322973;
        let r = sqrt(f32(i) / f32(sampleCount)) * radius;
        let offset = vec2<f32>(cos(angle), sin(angle)) * r;

        let sampleUV = uv + offset;
        // Clamp to avoid wrapping artifacts in bokeh
        let clampedUV = clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0));
        let sample = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0);
        let luma = dot(sample.rgb, vec3<f32>(0.299, 0.587, 0.114));

        // Importance weight: bright pixels contribute more
        let importance = pow(luma + 0.1, shapePower);

        // Chromatic aberration per sample based on radius
        let chromaShift = chromaAmount * r / radius;
        var shiftedColor = sample.rgb;
        let rSample = textureSampleLevel(readTexture, u_sampler, clamp(clampedUV + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
        let bSample = textureSampleLevel(readTexture, u_sampler, clamp(clampedUV - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
        shiftedColor = vec3<f32>(rSample, shiftedColor.g, bSample);

        accumColor += shiftedColor * importance * brightnessBoost;
        accumWeight += importance;
    }

    let result = accumColor / max(accumWeight, 0.001);

    // Preserve some sharpness from center
    let centerSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let blendFactor = 1.0 - smoothstep(0.0, radius * 2.0, length(uv - focalUV));
    let finalColor = mix(result, centerSample, blendFactor * 0.3);

    // Tone map
    let display = toneMapACES(finalColor);

    // Alpha stores average importance
    textureStore(writeTexture, gid.xy, vec4<f32>(display, accumWeight / f32(sampleCount)));
    textureStore(dataTextureA, gid.xy, vec4<f32>(result, accumWeight / f32(sampleCount)));
}
