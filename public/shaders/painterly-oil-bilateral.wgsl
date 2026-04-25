// ═══════════════════════════════════════════════════════════════════
//  Painterly Oil + Bilateral Dream
//  Category: advanced-hybrid
//  Features: advanced-convolution, upgraded-rgba, depth-aware, mouse-driven
//  Complexity: Very High
//  Chunks From: artistic_painterly_oil.wgsl, conv-bilateral-dream.wgsl
//  Created: 2026-04-18
//  By: Agent CB-10 — Image Processing & Artistry Enhancer
// ═══════════════════════════════════════════════════════════════════
//
//  Hybrid Approach:
//    1. Apply anisotropic Kuwahara filter for painterly segmentation
//    2. Quantize colors for oil-paint palette
//    3. Apply bilateral filter as post-process for dreamy smoothness
//    4. Mouse focus aperture: near mouse = sharp brushwork, far = dreamy blur
//    5. Impasto height and canvas texture preserved
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Bilateral-smoothed oil paint color
//    Alpha: Accumulated bilateral weight (deferred normalization factor)
//           + paint thickness for physical media realism
//
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=BrushSize, y=Wetness, z=BilateralDream, w=MouseFocus
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// ═══ CHUNK: luminance (from artistic_painterly_oil.wgsl) ═══
fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// ═══ CHUNK: sobel (from artistic_painterly_oil.wgsl) ═══
fn sobel(uv: vec2<f32>, invRes: vec2<f32>) -> vec2<f32> {
    let sx = array<f32, 9>(-1.0, 0.0, 1.0, -2.0, 0.0, 2.0, -1.0, 0.0, 1.0);
    let sy = array<f32, 9>(-1.0, -2.0, -1.0, 0.0, 0.0, 0.0, 1.0, 2.0, 1.0);
    let offsets = array<vec2<f32>, 9>(
        vec2<f32>(-1.0, -1.0), vec2<f32>(0.0, -1.0), vec2<f32>(1.0, -1.0),
        vec2<f32>(-1.0,  0.0), vec2<f32>(0.0,  0.0), vec2<f32>(1.0,  0.0),
        vec2<f32>(-1.0,  1.0), vec2<f32>(0.0,  1.0), vec2<f32>(1.0,  1.0)
    );
    var gx = 0.0;
    var gy = 0.0;
    for (var i: i32 = 0; i < 9; i = i + 1) {
        let lum = luminance(textureSampleLevel(readTexture, u_sampler, uv + offsets[i] * invRes, 0.0).rgb);
        gx += lum * sx[i];
        gy += lum * sy[i];
    }
    return vec2<f32>(gx, gy);
}

// ═══ CHUNK: kuwahara (from artistic_painterly_oil.wgsl) ═══
fn kuwahara(uv: vec2<f32>, invRes: vec2<f32>, radius: i32, edgeDir: vec2<f32>) -> vec3<f32> {
    var mean = vec3<f32>(0.0);
    var variance = 0.0;
    var bestMean = vec3<f32>(0.0);
    var minVariance = 999999.0;
    let perp = vec2<f32>(-edgeDir.y, edgeDir.x);
    for (var sector: i32 = 0; sector < 4; sector = sector + 1) {
        mean = vec3<f32>(0.0);
        variance = 0.0;
        for (var y: i32 = 0; y < radius; y = y + 1) {
            for (var x: i32 = 0; x < radius; x = x + 1) {
                var offset: vec2<f32>;
                switch(sector) {
                    case 0: { offset = vec2<f32>( f32(x),  f32(y)); }
                    case 1: { offset = vec2<f32>(-f32(x),  f32(y)); }
                    case 2: { offset = vec2<f32>( f32(x), -f32(y)); }
                    case 3: { offset = vec2<f32>(-f32(x), -f32(y)); }
                    default: { offset = vec2<f32>(0.0); }
                }
                offset = edgeDir * offset.x * 2.0 + perp * offset.y * 0.5;
                let sampleUV = uv + offset * invRes;
                let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
                mean += col;
                variance += luminance(col * col);
            }
        }
        let sectorSamples = f32(radius * radius);
        mean /= sectorSamples;
        variance = variance / sectorSamples - luminance(mean) * luminance(mean);
        if (variance < minVariance) {
            minVariance = variance;
            bestMean = mean;
        }
    }
    return bestMean;
}

// ═══ CHUNK: quantizeColor (from artistic_painterly_oil.wgsl) ═══
fn quantizeColor(c: vec3<f32>, levels: i32) -> vec3<f32> {
    let fLevels = f32(levels);
    return floor(c * fLevels) / fLevels;
}

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let invRes = 1.0 / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    // Parameters
    let brushSize = i32(3.0 + u.zoom_params.x * 8.0);
    let paintWetness = u.zoom_params.y;
    let bilateralDream = u.zoom_params.z;
    let mouseInfluence = u.zoom_params.w;

    // Edge detection for anisotropic direction
    let edge = sobel(uv, invRes);
    let edgeMag = length(edge);
    let edgeDir = normalize(edge + vec2<f32>(0.001));

    // Apply anisotropic Kuwahara filter
    var color = kuwahara(uv, invRes, brushSize, edgeDir);

    // Color quantization
    let colorLevels = i32(2.0 + paintWetness * 6.0);
    color = quantizeColor(color, colorLevels);

    // Impasto height
    let lum = luminance(color);
    let height = lum * 0.5 + edgeMag * 0.5;

    // === BILATERAL DREAM POST-PROCESS ===
    // Mouse focus aperture
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 8.0) * mouseInfluence;
    let spatialSigmaBase = mix(0.5, 2.0, bilateralDream);
    let spatialSigma = mix(spatialSigmaBase, spatialSigmaBase * 0.2, mouseFactor);
    let colorSigma = mix(0.1, 0.5, bilateralDream);

    // Ripple shockwaves
    var rippleSharpness = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(uv - rPos);
            let wave = exp(-pow((rDist - rElapsed * 0.3) * 12.0, 2.0));
            rippleSharpness = rippleSharpness + wave * (1.0 - rElapsed / 3.0);
        }
    }
    let finalSigma = max(spatialSigma * (1.0 - rippleSharpness * 0.8), 0.15);

    // Bilateral filter on the painterly result
    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;
    let radius = i32(ceil(finalSigma * 2.5));
    let maxRadius = min(radius, 6);

    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * invRes;
            let neighbor = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0);
            let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
            let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * finalSigma * finalSigma + 0.001));
            let colorDist = length(neighbor.rgb - color);
            let rangeWeight = exp(-colorDist * colorDist / (2.0 * colorSigma * colorSigma + 0.001));
            let weight = spatialWeight * rangeWeight;
            accumColor += neighbor.rgb * weight;
            accumWeight += weight;
        }
    }

    var bilateralResult = color;
    if (accumWeight > 0.001) {
        bilateralResult = accumColor / accumWeight;
    }

    // Blend original painterly with bilateral dream
    var finalColor = mix(color, bilateralResult, bilateralDream);

    // Canvas texture
    let canvas_tex = hash12(uv * 100.0) * 0.1 + 0.9;
    let canvas = sin(uv.x * 100.0) * sin(uv.y * 100.0);
    let canvasTex = canvas * 0.5 + 0.5;
    finalColor = mix(finalColor, finalColor * (0.9 + canvasTex * 0.2), 0.15);

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.4;
    finalColor *= vignette;

    // Paint thickness -> alpha mapping
    let paint_thickness = height * (0.5 + paintWetness);
    var paint_alpha = mix(0.35, 0.96, paint_thickness * paint_thickness);
    let dry_factor = 1.0 - paintWetness * 0.3;
    paint_alpha *= dry_factor;
    let weave_effect = mix(0.92, 1.0, canvas_tex);
    paint_alpha *= weave_effect;
    let stroke_edge = smoothstep(0.0, 0.4, edgeMag);
    paint_alpha *= mix(0.85, 1.0, stroke_edge);
    let pigment_density = 1.0 - lum;
    let opacity_boost = mix(0.0, 0.1, pigment_density * paintWetness);
    paint_alpha = min(1.0, paint_alpha + opacity_boost);
    let thickness_luma = mix(1.15, 0.9, paint_thickness);
    finalColor *= thickness_luma;

    finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(finalColor, paint_alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(paint_thickness, 0.0, 0.0, paint_alpha));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, paint_thickness));
}
