// ═══════════════════════════════════════════════════════════════════
//  ink-dispersion-guided
//  Category: advanced-hybrid
//  Features: depth-guided-filtering, ink-halftone, mouse-driven
//  Complexity: High
//  Chunks From: ink_dispersion_alpha (halftone dots, edge ink), conv-guided-filter-depth (guided filter, mouse aperture)
//  Created: 2026-04-18
//  By: Agent CB-6 — Alpha & Post-Process Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Depth-Guided Ink Halftone
//  Applies a depth-guided edge-preserving filter to the input, then
//  renders the result as ink-style halftone dots. The guided filter
//  radius and epsilon are modulated by depth and mouse distance,
//  creating sharper ink near edges and softer diffusion in smooth
//  depth regions.
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

fn getLuma(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn hash12_(p: vec2<f32>) -> f32 {
    var p3_ = fract(vec3<f32>(p.xyx) * 0.1031);
    p3_ = p3_ + dot(p3_, p3_.yzx + 33.33);
    return fract((p3_.x + p3_.y) * p3_.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixelSize = 1.0 / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let dotSize = u.zoom_params.x * 20.0 + 2.0;
    let edgeThresh = max(0.01, (1.0 - u.zoom_params.y) * 0.5);
    let levels = floor(u.zoom_params.z * 10.0) + 2.0;
    let inkDensity = u.zoom_params.w;

    // ═══ CHUNK: Guided filter preprocessing (from conv-guided-filter-depth.wgsl) ═══
    let radiusBase = i32(mix(1.0, 5.0, u.zoom_params.x));
    let epsilonBase = mix(0.0001, 0.05, u.zoom_params.y);
    let depthInfluence = u.zoom_params.z;
    let mouseInfluence = u.zoom_params.w;

    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 6.0) * mouseInfluence;
    let radius = i32(mix(f32(radiusBase), f32(radiusBase) * 0.4, mouseFactor));
    let epsilon = mix(epsilonBase * 3.0, epsilonBase * 0.1, mouseFactor);

    var rippleDepth = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rElapsed = time - ripple.z;
        if (rElapsed > 0.0 && rElapsed < 2.5) {
            let rDist = length(uv - ripple.xy);
            let wave = exp(-rDist * rDist * 40.0) * (1.0 - rElapsed / 2.5);
            rippleDepth = rippleDepth + wave;
        }
    }

    let maxRadius = min(radius, 4);
    var sumGuide = 0.0;
    var sumInput = vec3<f32>(0.0);
    var sumGuideInput = vec3<f32>(0.0);
    var sumGuide2 = 0.0;
    var count = 0.0;

    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let guideVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + offset, 0.0).r + rippleDepth * 0.1;
            let inputVal = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
            sumGuide += guideVal;
            sumInput += inputVal;
            sumGuideInput += inputVal * guideVal;
            sumGuide2 += guideVal * guideVal;
            count += 1.0;
        }
    }

    let meanGuide = sumGuide / count;
    let meanInput = sumInput / count;
    let meanGI = sumGuideInput / count;
    let meanGuide2 = sumGuide2 / count;
    let varGuide = meanGuide2 - meanGuide * meanGuide;

    let a = (meanGI - meanGuide * meanInput) / (varGuide + epsilon);
    let b = meanInput - a * meanGuide;
    let guide = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + rippleDepth * 0.1;
    let filteredColor = a * guide + b;
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let color = mix(original, filteredColor, depthInfluence);

    // ═══ CHUNK: Ink halftone (from ink_dispersion_alpha.wgsl) ═══
    var gx = vec3<f32>(0.0);
    var gy = vec3<f32>(0.0);
    for (var i: i32 = -1; i <= 1; i = i + 1) {
        for (var j: i32 = -1; j <= 1; j = j + 1) {
            let offset = vec2<f32>(f32(i), f32(j)) * pixelSize;
            let s = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).xyz;
            let luma = getLuma(s);
            var wx = 0.0;
            var wy = 0.0;
            if (i == -1) { wx = -1.0; }
            if (i == 1) { wx = 1.0; }
            if (j == -1) { wy = -1.0; }
            if (j == 1) { wy = 1.0; }
            if (j == 0) { wx = wx * 2.0; }
            if (i == 0) { wy = wy * 2.0; }
            gx = gx + vec3<f32>(luma * wx);
            gy = gy + vec3<f32>(luma * wy);
        }
    }
    let edge = length(gx + gy);
    let isEdge = select(0.0, 1.0, edge > edgeThresh);

    let luma = getLuma(color);
    let gridPos = vec2<f32>(global_id.xy) / vec2<f32>(dotSize);
    let gridCenter = floor(gridPos) + vec2<f32>(0.5);
    let dist = length(gridPos - gridCenter);
    let radius = sqrt(luma) * 0.5;
    let quantColor = floor(color * levels) / vec3<f32>(levels);
    let dotRadius = (1.0 - luma) * 0.7;
    let isDot = select(0.0, 1.0, dist < dotRadius);

    var finalColor = quantColor;
    var ink_alpha = 0.0;

    if (isEdge > 0.5) {
        let line_density = inkDensity * 0.9 + 0.05;
        ink_alpha = line_density;
        finalColor = mix(finalColor, vec3<f32>(0.02, 0.02, 0.04), isEdge * inkDensity);
    }
    if (isDot > 0.5) {
        let dot_coverage = smoothstep(0.0, 0.7, 1.0 - luma);
        let dot_alpha = dot_coverage * inkDensity * 0.85;
        finalColor = mix(finalColor, finalColor * 0.7, isDot * 0.8);
        ink_alpha = max(ink_alpha, dot_alpha);
    }
    if (ink_alpha < 0.01) {
        ink_alpha = mix(0.15, 0.45, luma * inkDensity);
    }

    let paper_tex = 0.95 + 0.05 * hash12_((uv * time) * 0.001 + vec2<f32>(100.0));
    ink_alpha = ink_alpha * paper_tex;

    if (mousePos.x >= 0.0) {
        let dVec = uv - mousePos;
        let d = length(dVec);
        let vignette = smoothstep(0.8, 0.2, d * 0.5);
        finalColor = finalColor * vignette;
        ink_alpha = mix(ink_alpha, min(1.0, ink_alpha * 1.2), vignette * 0.5);
    }

    // Depth-modulated dot size variation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthBoost = 1.0 + depth * 0.3;
    finalColor = finalColor * depthBoost;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, ink_alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(ink_alpha, 0.0, 0.0, ink_alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, ink_alpha));
}
