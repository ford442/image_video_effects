// ═══════════════════════════════════════════════════════════════════
//  Astral Kaleidoscope + Morphological Operations
//  Category: advanced-hybrid
//  Features: advanced-convolution, upgraded-rgba, depth-aware, mouse-driven
//  Complexity: Very High
//  Chunks From: astral-kaleidoscope.wgsl, conv-morphological-erosion-dilation.wgsl
//  Created: 2026-04-18
//  By: Agent CB-10 — Image Processing & Artistry Enhancer
// ═══════════════════════════════════════════════════════════════════
//
//  Hybrid Approach:
//    1. Generate kaleidoscope mirror segments with chromatic separation
//    2. Apply morphological erosion/dilation to the kaleidoscope output
//    3. Morphological gradient creates glowing edge halos around segments
//    4. Top-hat transform isolates bright peaks for sparkling highlights
//    5. Blend erosion/dilation for geometric texture variation
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Morphologically processed kaleidoscope color
//    Alpha: Top-hat luminance — isolated bright peaks become sparkle alpha.
//           This naturally separates light sources from dark regions.
//
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;
@group(0) @binding(7) var historyBuf: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var unusedBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var historyTex: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_params: vec4<f32>,       // x=segments, y=rotationSpeed, z=morphBlend, w=trailPersistence
  zoom_config: vec4<f32>,       // x=colorShift, y=aberration, z=centerOsc, w=pulsePower
  ripples:     array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// ═══ CHUNK: fmod (from astral-kaleidoscope.wgsl) ═══
fn fmod(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

// ═══ CHUNK: rotate (from astral-kaleidoscope.wgsl) ═══
fn rotate(v: vec2<f32>, a: f32) -> vec2<f32> {
    let s = sin(a);
    let c = cos(a);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

// ═══ CHUNK: rgb2hsl (from astral-kaleidoscope.wgsl) ═══
fn rgb2hsl(c: vec3<f32>) -> vec3<f32> {
    let minVal = min(min(c.r, c.g), c.b);
    let maxVal = max(max(c.r, c.g), c.b);
    let delta = maxVal - minVal;
    var h = 0.0;
    var s = 0.0;
    var l = (maxVal + minVal) / 2.0;
    if (delta > 0.0) {
        s = delta / (1.0 - abs(2.0 * l - 1.0));
        if (maxVal == c.r) {
            var offset = 0.0;
            if (c.g < c.b) { offset = 6.0; }
            h = (c.g - c.b) / delta + offset;
        } else if (maxVal == c.g) {
            h = (c.b - c.r) / delta + 2.0;
        } else {
            h = (c.r - c.g) / delta + 4.0;
        }
        h = h / 6.0;
    }
    return vec3<f32>(h, s, l);
}

// ═══ CHUNK: hue2rgb (from astral-kaleidoscope.wgsl) ═══
fn hue2rgb(p: f32, q: f32, t: f32) -> f32 {
    var t2 = t;
    if (t2 < 0.0) { t2 = t2 + 1.0; }
    if (t2 > 1.0) { t2 = t2 - 1.0; }
    if (t2 < 1.0/6.0) { return p + (q - p) * 6.0 * t2; }
    if (t2 < 1.0/2.0) { return q; }
    if (t2 < 2.0/3.0) { return p + (q - p) * (2.0/3.0 - t2) * 6.0; }
    return p;
}

// ═══ CHUNK: hsl2rgb (from astral-kaleidoscope.wgsl) ═══
fn hsl2rgb(c: vec3<f32>) -> vec3<f32> {
    var h = c.x;
    var s = c.y;
    var l = c.z;
    if (s == 0.0) { return vec3<f32>(l); }
    var q = l + s - l * s;
    if (l < 0.5) { q = l * (1.0 + s); }
    var p = 2.0 * l - q;
    return vec3<f32>(
        hue2rgb(p, q, h + 1.0/3.0),
        hue2rgb(p, q, h),
        hue2rgb(p, q, h - 1.0/3.0)
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    var uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;

    // Parameters
    let segments    = max(3.0, u.zoom_params.x * 12.0 + 3.0);
    let rotSpeed    = u.zoom_params.y * 0.5;
    let morphBlend  = u.zoom_params.z;
    let trails      = u.zoom_params.w;
    let hueShift    = u.zoom_config.x;
    let aberration  = u.zoom_config.y * 0.02;
    let centerOsc   = u.zoom_config.z * 0.15;
    let pulsePower  = u.zoom_config.w * 0.5 + 0.5;

    // Dynamic Center
    var center = vec2<f32>(0.5, 0.5) + vec2<f32>(sin(time * 0.3), cos(time * 0.4)) * centerOsc;

    // Depth-Aware Coordinates
    let staticDepth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    let depthFactor = 1.0 + (1.0 - staticDepth) * 2.0;

    // Convert to Polar
    let toPixel = uv - center;
    var r = length(toPixel);
    var a = atan2(toPixel.y, toPixel.x);

    // Kaleidoscope Logic
    let spiral = r * 2.0 * sin(time * 0.2);
    let rotation = time * rotSpeed * depthFactor;
    a = a + rotation + spiral;
    let segmentAngle = 2.0 * PI / segments;
    a = fmod(a, segmentAngle);
    if (a < 0.0) { a = a + segmentAngle; }
    if (a > segmentAngle * 0.5) { a = segmentAngle - a; }
    let r_pulse = r - log(r + 0.1) * (pulsePower * sin(time));
    let sampleUV = center + vec2<f32>(cos(a), sin(a)) * r_pulse;

    // Chromatic Separation
    let chromaOffset = aberration * 3.0;
    let uvR = rotate(sampleUV - center, chromaOffset) + center;
    let uvG = sampleUV;
    let uvB = rotate(sampleUV - center, -chromaOffset) + center;

    let colR = textureSampleLevel(videoTex, videoSampler, clamp(uvR, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let colG = textureSampleLevel(videoTex, videoSampler, clamp(uvG, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let colB = textureSampleLevel(videoTex, videoSampler, clamp(uvB, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    var color = vec3<f32>(colR, colG, colB);

    // Psychedelic Color Grading
    var hsl = rgb2hsl(color);
    hsl.x = fract(hsl.x + time * 0.1 + r * hueShift);
    hsl.y = min(hsl.y * 1.2, 1.0);
    color = hsl2rgb(hsl);

    // === MORPHOLOGICAL OPERATIONS ===
    let pixelSize = 1.0 / dims;
    let kernelRadius = i32(mix(1.0, 4.0, morphBlend));
    let maxRadius = min(kernelRadius, 5);

    var minVal = vec3<f32>(999.0);
    var maxVal = vec3<f32>(-999.0);
    var minLuma = 999.0;
    var maxLuma = -999.0;

    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            if (dx*dx + dy*dy > maxRadius*maxRadius) { continue; }
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            // Sample from kaleidoscope-transformed position
            let morphUV = sampleUV + offset;
            let sample = textureSampleLevel(videoTex, videoSampler, clamp(morphUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
            let luma = dot(sample, vec3<f32>(0.299, 0.587, 0.114));
            minVal = min(minVal, sample);
            maxVal = max(maxVal, sample);
            minLuma = min(minLuma, luma);
            maxLuma = max(maxLuma, luma);
        }
    }

    let erosion = minVal;
    let dilation = maxVal;
    let gradient = (dilation - erosion) * mix(0.5, 2.0, morphBlend);
    let topHat = color - erosion;

    // Blend erosion <-> dilation via param
    let morphRGB = mix(erosion, dilation, morphBlend);

    // Add gradient glow to kaleidoscope color
    let gradientLuma = dot(gradient, vec3<f32>(0.299, 0.587, 0.114));
    color = color + gradient * 0.4 * morphBlend;

    // Mix morphological texture with kaleidoscope
    color = mix(color, morphRGB, morphBlend * 0.5);

    // Trails / Feedback
    let prev = textureSampleLevel(historyTex, depthSampler, uv, 0.0).rgb;
    let decay = 0.9 + (trails * 0.09);
    let feedback = max(color, prev * decay);
    textureStore(historyBuf, vec2<i32>(gid.xy), vec4<f32>(feedback, 1.0));

    let finalCol = mix(color, feedback, 0.5);

    // Top-hat alpha for sparkle highlights
    let topHatLuma = dot(topHat, vec3<f32>(0.299, 0.587, 0.114));
    let luma = dot(finalCol, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(0.7, 1.0, luma) + topHatLuma * morphBlend * 0.3;
    let finalAlpha = mix(alpha * 0.8, min(alpha, 1.0), staticDepth);

    textureStore(outTex, vec2<i32>(gid.xy), vec4<f32>(finalCol, finalAlpha));
    textureStore(outDepth, vec2<i32>(gid.xy), vec4<f32>(staticDepth, 0.0, 0.0, 0.0));
}
