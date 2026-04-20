// ═══════════════════════════════════════════════════════════════════
//  spec-blue-noise-stipple
//  Category: artistic
//  Features: blue-noise, pointillism, stochastic-sampling
//  Complexity: Medium
//  Chunks From: chunk-library (hash22)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  Blue-Noise Dithered Pointillism
//  Uses a blue-noise distribution (golden-ratio low-discrepancy) to
//  create Seurat-style pointillist rendering with perceptually
//  optimal, uniformly-spaced yet non-regular dot distributions.
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

// Blue-noise offset via plastic constant low-discrepancy sequence
fn blueNoiseOffset(pixelCoord: vec2<f32>, frame: f32) -> vec2<f32> {
    let phi2 = vec2<f32>(1.3247179572, 1.7548776662);
    return fract(pixelCoord * phi2 + frame * phi2);
}

// Golden angle spiral for dot placement
fn goldenAngleDisk(index: f32, total: f32) -> vec2<f32> {
    let angle = index * 2.39996322973; // golden angle
    let radius = sqrt(index / total);
    return vec2<f32>(cos(angle), sin(angle)) * radius;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    let dotScale = mix(8.0, 40.0, u.zoom_params.x);
    let dotSizeBase = mix(0.3, 1.2, u.zoom_params.y);
    let colorVar = mix(0.0, 0.3, u.zoom_params.z);
    let density = mix(0.5, 1.5, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Cell-based stippling
    let cellSize = 1.0 / dotScale;
    let cellId = floor(uv * dotScale);
    let cellLocal = fract(uv * dotScale) - 0.5;

    // Blue-noise jittered dot center within each cell
    let jitter = blueNoiseOffset(cellId, time * 0.1);
    let dotCenter = (jitter - 0.5) * 0.8;

    // Sample local color
    let sampleUV = (cellId + 0.5) / dotScale;
    let localColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let luma = dot(localColor, vec3<f32>(0.299, 0.587, 0.114));

    // Dot size based on luminance (darker = bigger dot, lighter = smaller)
    let dotSize = mix(dotSizeBase * 0.9, dotSizeBase * 0.15, luma) * density;

    // Distance to dot center
    let dist = length(cellLocal - dotCenter);

    // Anti-aliased dot edge
    let edgeWidth = 0.08;
    let dotMask = 1.0 - smoothstep(dotSize - edgeWidth, dotSize + edgeWidth, dist);

    // Add secondary dot for mid-tones (2-dot dither)
    let jitter2 = blueNoiseOffset(cellId + vec2<f32>(37.0, 17.0), time * 0.1);
    let dotCenter2 = (jitter2 - 0.5) * 0.6;
    let dotSize2 = mix(dotSizeBase * 0.5, dotSizeBase * 0.05, luma) * density * 0.7;
    let dist2 = length(cellLocal - dotCenter2);
    let dotMask2 = 1.0 - smoothstep(dotSize2 - edgeWidth, dotSize2 + edgeWidth, dist2);

    let combinedMask = max(dotMask, dotMask2 * 0.5);

    // Background color (paper/ canvas)
    let paperColor = vec3<f32>(0.95, 0.93, 0.88);

    // Dot color with slight chromatic variation
    let chromaticShift = hash22(cellId) - 0.5;
    let dotColor = localColor + chromaticShift.xyx * colorVar;

    var outColor = mix(paperColor, dotColor, combinedMask);

    // Mouse interaction: local magnification
    if (isMouseDown) {
        let mouseDist = length(uv - mousePos);
        let influence = exp(-mouseDist * mouseDist * 2000.0);
        if (influence > 0.01) {
            // Sharpen dots near mouse
            let sharpMask = select(0.0, 1.0, dist < dotSize * 0.8);
            outColor = mix(outColor, dotColor, sharpMask * influence * 0.5);
        }
    }

    textureStore(writeTexture, gid.xy, vec4<f32>(outColor, 1.0));
    textureStore(dataTextureA, gid.xy, vec4<f32>(localColor, combinedMask));
}
