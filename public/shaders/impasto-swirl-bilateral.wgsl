// ═══════════════════════════════════════════════════════════════════
//  Impasto Swirl Bilateral
//  Category: advanced-hybrid
//  Features: bilateral-filter, halftone-impasto, edge-aware, hue-shift,
//            mouse-driven
//  Complexity: Very High
//  Chunks From: impasto-swirl, conv-bilateral-dream
//  Created: 2026-04-18
//  By: Agent CB-26
// ═══════════════════════════════════════════════════════════════════
//  Edge-preserving bilateral smoothing meets physical impasto
//  dot/halftone texture. Creates a painted-canvas look where smooth
//  color regions are punctuated by raised ink dots and edge strokes.
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    var p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
    var q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
    var d = q.x - min(q.w, q.y);
    let h = abs((q.w - q.y) / (6.0 * d + 1e-10) + K.x);
    return vec3<f32>(h, d, q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec3<f32>(1.0, 2.0/3.0, 1.0/3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - 3.0);
    return c.z * mix(vec3<f32>(1.0), clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(hue);
    return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));

    // Parameters
    let spatialSigmaBase = mix(0.1, 1.0, u.zoom_params.x);
    let colorSigma = mix(0.05, 1.0, u.zoom_params.y);
    let hueShiftAmt = u.zoom_params.z;
    let inkDensity = u.zoom_params.w;

    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // === BILATERAL FILTER ===
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 8.0);
    let spatialSigma = mix(spatialSigmaBase, spatialSigmaBase * 0.2, mouseFactor);

    // Ripple shockwaves
    var rippleSharpness = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rElapsed = time - ripple.z;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(uv - ripple.xy);
            let wave = exp(-pow((rDist - rElapsed * 0.3) * 12.0, 2.0));
            rippleSharpness += wave * (1.0 - rElapsed / 3.0);
        }
    }
    let finalSigma = max(spatialSigma * (1.0 - rippleSharpness * 0.8), 0.02);

    let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;
    let radius = i32(ceil(finalSigma * 2.5));
    let maxRadius = min(radius, 5);

    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let neighbor = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0);
            let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
            let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * finalSigma * finalSigma + 0.001));
            let colorDist = length(neighbor.rgb - center.rgb);
            let rangeWeight = exp(-colorDist * colorDist / (2.0 * colorSigma * colorSigma + 0.001));
            let weight = spatialWeight * rangeWeight;
            accumColor += neighbor.rgb * weight;
            accumWeight += weight;
        }
    }

    var smoothColor = vec3<f32>(0.0);
    if (accumWeight > 0.001) {
        smoothColor = accumColor / accumWeight;
    } else {
        smoothColor = center.rgb;
    }

    // === IMPASTO EDGE & DOT OVERLAY ===
    // Sobel edge detection on original
    var gx = vec3<f32>(0.0);
    var gy = vec3<f32>(0.0);
    for (var i = -1; i <= 1; i = i + 1) {
        for (var j = -1; j <= 1; j = j + 1) {
            let offset = vec2<f32>(f32(i), f32(j)) * pixelSize;
            let s = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
            let luma = getLuma(s);
            var wx = 0.0;
            var wy = 0.0;
            if (i == -1) { wx = -1.0; }
            if (i == 1) { wx = 1.0; }
            if (j == -1) { wy = -1.0; }
            if (j == 1) { wy = 1.0; }
            if (j == 0) { wx *= 2.0; }
            if (i == 0) { wy *= 2.0; }
            gx += vec3<f32>(luma * wx);
            gy += vec3<f32>(luma * wy);
        }
    }
    let edge = length(gx + gy);
    let edgeThresh = max(0.01, (1.0 - inkDensity) * 0.5);
    let isEdge = step(edgeThresh, edge);

    // Halftone dot pattern
    let dotSize = (u.zoom_params.x * 20.0) + 2.0;
    let levels = floor(u.zoom_params.y * 10.0) + 2.0;
    let gridPos = vec2<f32>(gid.xy) / vec2<f32>(dotSize);
    let gridCenter = floor(gridPos) + vec2<f32>(0.5);
    let distDot = length(gridPos - gridCenter);
    let lumaSmooth = getLuma(smoothColor);
    let dotRadius = (1.0 - lumaSmooth) * 0.7;
    let isDot = step(distDot, dotRadius);

    // Quantize colors
    let quantColor = floor(smoothColor * levels) / vec3<f32>(levels);

    // Apply ink effects
    var finalColor = quantColor;
    var inkAlpha = 0.0;

    if (isEdge > 0.5) {
        let lineDensity = inkDensity * 0.9 + 0.05;
        inkAlpha = lineDensity;
        finalColor = mix(finalColor, vec3<f32>(0.02, 0.02, 0.04), isEdge * inkDensity);
    }
    if (isDot > 0.5) {
        let dotCoverage = smoothstep(0.0, 0.7, 1.0 - lumaSmooth);
        let dotAlpha = dotCoverage * inkDensity * 0.85;
        finalColor = mix(finalColor, finalColor * 0.7, isDot * 0.8);
        inkAlpha = max(inkAlpha, dotAlpha);
    }
    if (inkAlpha < 0.01) {
        inkAlpha = mix(0.15, 0.45, lumaSmooth * inkDensity);
    }

    // Paper texture
    let paperTex = 0.95 + 0.05 * hash12(uv * time * 0.001 + vec2<f32>(100.0));
    inkAlpha *= paperTex;

    // Mouse vignette
    if (mousePos.x >= 0.0) {
        let d = length(uv - mousePos);
        let vignette = smoothstep(0.8, 0.2, d * 0.5);
        finalColor *= vignette;
        inkAlpha = mix(inkAlpha, min(1.0, inkAlpha * 1.2), vignette * 0.5);
    }

    // Psychedelic hue shift
    if (hueShiftAmt > 0.0) {
        let hsv = rgb2hsv(finalColor);
        let newHue = fract(hsv.x + hueShiftAmt + mouseDist * 0.3 + time * 0.05);
        finalColor = hsv2rgb(vec3<f32>(newHue, hsv.y, hsv.z));
    }

    textureStore(writeTexture, coord, vec4<f32>(finalColor, inkAlpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
