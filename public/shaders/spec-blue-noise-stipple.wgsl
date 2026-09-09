// ═══════════════════════════════════════════════════════════════════
//  Blue Noise Stipple
//  Category: artistic
//  Features: blue-noise, pointillism, stochastic-sampling, mouse-driven,
//            audio-reactive, click-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: dark-cell packing (jitter shrinks with ink); neighbor occupancy skip
//  A packing: ACES display RGBA
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

fn blueNoiseOffset(pixelCoord: vec2<f32>, frame: f32) -> vec2<f32> {
    let phi2 = vec2<f32>(1.3247179572, 1.7548776662);
    return fract(pixelCoord * phi2 + frame * phi2);
}

fn goldenAngleDisk(index: f32, total: f32) -> vec2<f32> {
    let angle = index * 2.39996322973;
    let radius = sqrt(index / max(total, 1.0));
    return vec2<f32>(cos(angle), sin(angle)) * radius;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn cellLuma(cellId: vec2<f32>, dotScale: f32) -> f32 {
    let sampleUV = clamp((cellId + 0.5) / dotScale, vec2<f32>(0.0), vec2<f32>(1.0));
    let rgb = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    return dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let held = step(0.5, u.zoom_config.w);

    let dotScale = mix(8.0, 40.0, u.zoom_params.x);
    let dotSizeBase = mix(0.3, 1.2, u.zoom_params.y);
    let colorVar = mix(0.0, 0.3, u.zoom_params.z);
    let density = mix(0.5, 1.5, u.zoom_params.w) * mix(1.0, 1.35, held);

    let mousePos = u.zoom_config.yz;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = exp(-mouseDist * mouseDist * 2000.0) * held;

    let cellId = floor(uv * dotScale);
    let cellLocal = fract(uv * dotScale) - 0.5;

    let sampleUV = clamp((cellId + 0.5) / dotScale, vec2<f32>(0.0), vec2<f32>(1.0));
    let localSample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let localColor = localSample.rgb;
    let luma = dot(localColor, vec3<f32>(0.299, 0.587, 0.114));
    let ink = 1.0 - luma;

    // Idea 1: dark-cell packing — ink-heavy cells jitter less so dots nest.
    let pack = mix(1.0, 0.35, ink);
    let jitter = blueNoiseOffset(cellId, time * 0.1);
    let dotCenter = (jitter - 0.5) * 0.8 * pack;

    let dotSize = mix(dotSizeBase * 0.9, dotSizeBase * 0.15, luma) * density;
    let edgeWidth = 0.08;
    let dist = length(cellLocal - dotCenter);
    let dotMask = 1.0 - smoothstep(dotSize - edgeWidth, dotSize + edgeWidth, dist);

    // Idea 2: neighbor occupancy skip — crowded 4-neighbors drop extra dots.
    let nInk = (
        (1.0 - cellLuma(cellId + vec2<f32>(1.0, 0.0), dotScale)) +
        (1.0 - cellLuma(cellId + vec2<f32>(-1.0, 0.0), dotScale)) +
        (1.0 - cellLuma(cellId + vec2<f32>(0.0, 1.0), dotScale)) +
        (1.0 - cellLuma(cellId + vec2<f32>(0.0, -1.0), dotScale))
    ) * 0.25;
    let skipExtra = 1.0 - smoothstep(0.45, 0.85, nInk) * 0.85;

    let jitter2 = blueNoiseOffset(cellId + vec2<f32>(37.0, 17.0), time * 0.1);
    let dotCenter2 = (jitter2 - 0.5) * 0.6 * pack;
    let dotSize2 = mix(dotSizeBase * 0.5, dotSizeBase * 0.05, luma) * density * 0.7;
    let dist2 = length(cellLocal - dotCenter2);
    let dotMask2 = (1.0 - smoothstep(dotSize2 - edgeWidth, dotSize2 + edgeWidth, dist2)) * skipExtra;

    let tertiaryCenter = goldenAngleDisk(luma * 3.0 + 0.5, 4.0) * 0.45 * pack;
    let dotSize3 = dotSizeBase * 0.25 * density;
    let dist3 = length(cellLocal - tertiaryCenter);
    let dotMask3 = (1.0 - smoothstep(dotSize3 - edgeWidth, dotSize3 + edgeWidth, dist3)) * skipExtra;

    let crawlRunner = pow(max(0.0, sin(dotScale * 0.5 + time * (12.0 + treble * 6.0))), 14.0);
    var combinedMask = max(dotMask, dotMask2 * 0.5);
    combinedMask = max(combinedMask, dotMask3 * 0.35 * (1.0 - luma));

    var clickSplatter = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.5) {
            let rd = length(uv - ripple.xy);
            clickSplatter += exp(-rd * rd * 800.0) * exp(-age * 1.8);
        }
    }
    combinedMask = max(combinedMask, clickSplatter * 0.6);

    let paperColor = vec3<f32>(0.95, 0.93, 0.88);
    let chromaticShift = hash22(cellId) - 0.5;
    let trebleShift = vec3<f32>(treble * 0.08, mids * 0.02, -treble * 0.08) * crawlRunner;
    let dotColor = localColor + chromaticShift.xyx * colorVar + trebleShift;

    var outColor = mix(paperColor, dotColor, combinedMask);

    let sharpMask = select(0.0, 1.0, dist < dotSize * 0.8);
    outColor = mix(outColor, dotColor, sharpMask * mouseInfluence * 0.5);
    outColor = mix(outColor, dotColor, combinedMask * mouseInfluence * 0.15 * (1.0 + bass * 0.2));

    let mapped = acesToneMap(outColor);
    let alpha = clamp(combinedMask * 0.75 + mouseInfluence * 0.15 + localSample.a * 0.1 + 0.08, 0.0, 1.0);
    let outCol = vec4<f32>(mapped, alpha);
    textureStore(writeTexture, gid.xy, outCol);
    textureStore(dataTextureA, gid.xy, outCol);
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
