// ═══════════════════════════════════════════════════════════════════
//  Domain-Warped FBM Grid v2 - Audio-reactive lattice
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, temporal,
//            domain-warping, FBM-noise
//  Upgraded: 2026-05-02 (Tier-1 integration pass)
//  Creative additions: recursive mini-grid moiré, chromatic dispersion edges
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uS = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, uS.x), mix(c, d, uS.x), uS.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < 6; i = i + 1) {
        if (i >= octaves) { break; }
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

fn domainWarp(uv: vec2<f32>, time: f32, scale: f32, amount: f32, attractor: vec2<f32>, attractorStrength: f32) -> vec2<f32> {
    let q = vec2<f32>(
        fbm(uv * scale + vec2<f32>(0.0, time * 0.1), 4),
        fbm(uv * scale + vec2<f32>(5.2, 1.3 + time * 0.1), 4)
    );
    let r = vec2<f32>(
        fbm(uv * scale + 4.0 * q + vec2<f32>(1.7 - time * 0.15, 9.2), 4),
        fbm(uv * scale + 4.0 * q + vec2<f32>(8.3 - time * 0.15, 2.8), 4)
    );
    // Mouse-driven gravity well: pulls warp toward attractor
    let toMouse = attractor - uv;
    let gravityFalloff = 1.0 / (dot(toMouse, toMouse) * 8.0 + 0.05);
    let gravity = toMouse * gravityFalloff * attractorStrength;
    return uv + amount * r + gravity * amount * 0.5;
}

fn gridLine(warpedUV: vec2<f32>, gridSize: f32, thickness: f32) -> vec2<f32> {
    let gridPos = warpedUV * gridSize;
    let gridFract = fract(gridPos - 0.5) - 0.5;
    let lineDist = abs(gridFract);
    let nearestLine = min(lineDist.x, lineDist.y);
    let adjustedThickness = thickness * (1.0 + length(gridFract) * 0.5);
    let intensity = 1.0 - smoothstep(0.0, adjustedThickness, nearestLine);
    let glow = 0.3 * (1.0 - smoothstep(0.0, adjustedThickness * 3.0, nearestLine));
    return vec2<f32>(intensity, glow);
}

// Distance to nearest grid intersection (for sparkle and recursive minigrids)
fn intersectionDist(warpedUV: vec2<f32>, gridSize: f32) -> f32 {
    let gridPos = warpedUV * gridSize;
    let gridFract = fract(gridPos - 0.5) - 0.5;
    return length(gridFract);
}

fn colorPalette(t: f32, shift: f32) -> vec3<f32> {
    let cyan = vec3<f32>(0.0, 1.0, 0.9);
    let blue = vec3<f32>(0.1, 0.4, 1.0);
    let magenta = vec3<f32>(1.0, 0.0, 0.8);
    let purple = vec3<f32>(0.6, 0.0, 1.0);
    let gold = vec3<f32>(1.0, 0.7, 0.1);

    let shiftedT = fract(t + shift);
    var color: vec3<f32>;
    if (shiftedT < 0.25) {
        color = mix(cyan, blue, shiftedT * 4.0);
    } else if (shiftedT < 0.5) {
        color = mix(blue, magenta, (shiftedT - 0.25) * 4.0);
    } else if (shiftedT < 0.75) {
        color = mix(magenta, purple, (shiftedT - 0.5) * 4.0);
    } else {
        color = mix(purple, gold, (shiftedT - 0.75) * 4.0);
    }
    return color;
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let time = u.config.x;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);

    // Audio
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Domain-specific params
    let warpParam = u.zoom_params.x;       // Warp Amount
    let densityParam = u.zoom_params.y;    // Grid Density
    let thicknessParam = u.zoom_params.z;  // Line Thickness
    let paletteShift = u.zoom_params.w;    // Palette Shift

    // Bass distorts grid harder; mids shift palette phase
    let warpAmount = clamp(warpParam, 0.0, 1.0) * (1.0 + bass * 0.7);
    let gridDensity = mix(0.6, 2.4, densityParam);
    let thickness = mix(0.005, 0.05, thicknessParam);
    let shift = paletteShift + mids * 0.25 + time * 0.02;

    let opacity = mix(0.6, 1.0, thicknessParam);

    let aspect = resolution.x / max(resolution.y, 1.0);
    var p = uv;
    p.x = p.x * aspect;

    // Mouse attractor (gravity well)
    var mouseUV = u.zoom_config.yz;
    mouseUV.x = mouseUV.x * aspect;
    let mouseDown = step(0.5, u.zoom_config.w);
    let attractorStrength = mix(0.05, 0.5, mouseDown);

    let warpedP = domainWarp(p, time, gridDensity * 2.0, warpAmount, mouseUV, attractorStrength);
    let distortionMag = length(warpedP - p);

    let gridSize = 8.0 * gridDensity;
    let gr = gridLine(warpedP, gridSize, thickness);
    let lineIntensity = gr.x;
    let lineGlow = gr.y;

    // ─── Creative: chromatic dispersion — sample the grid 3 times slightly offset ───
    let dispersion = thickness * (0.6 + bass * 0.6);
    let warpR = domainWarp(p + vec2<f32>(dispersion, 0.0), time, gridDensity * 2.0, warpAmount, mouseUV, attractorStrength);
    let warpB = domainWarp(p - vec2<f32>(dispersion, 0.0), time, gridDensity * 2.0, warpAmount, mouseUV, attractorStrength);
    let lineR = gridLine(warpR, gridSize, thickness).x;
    let lineB = gridLine(warpB, gridSize, thickness).x;
    let chromaLine = vec3<f32>(lineR, lineIntensity, lineB);

    // ─── Creative: recursive mini-grid (moiré) ───
    let intDist = intersectionDist(warpedP, gridSize);
    let nearIntersection = smoothstep(0.18, 0.0, intDist);
    let miniRot = time * 0.4;
    let cR = cos(miniRot);
    let sR = sin(miniRot);
    let miniUV = vec2<f32>(
        warpedP.x * cR - warpedP.y * sR,
        warpedP.x * sR + warpedP.y * cR
    );
    let mini = gridLine(miniUV, gridSize * 4.0, thickness * 0.5).x * nearIntersection * 0.6;

    // Color composition
    let colorT = distortionMag * 2.0 + time * 0.05 + shift;
    let baseColor = colorPalette(colorT, shift);
    let accentT = distortionMag * 3.0 - time * 0.03 + 0.5 + shift;
    let accentColor = colorPalette(accentT, shift + 0.25);
    let mixFactor = smoothstep(0.0, 0.5, distortionMag);
    let lineColor = mix(baseColor, accentColor, mixFactor);

    var generatedColor = vec3<f32>(0.02, 0.02, 0.05);
    generatedColor = generatedColor + lineColor * lineIntensity;
    generatedColor = generatedColor + lineColor * lineGlow * 0.5;
    generatedColor = generatedColor + chromaLine * 0.35;
    generatedColor = generatedColor + accentColor * mini;
    generatedColor = generatedColor + accentColor * distortionMag * 0.15;

    // Treble sparkle on grid intersections
    let sparkleSeed = hash12(floor(warpedP * gridSize) + vec2<f32>(time * 4.0, 0.0));
    let sparkle = step(1.0 - treble * 0.55, sparkleSeed) * nearIntersection;
    generatedColor = generatedColor + vec3<f32>(sparkle);

    // Vignette
    let vignetteUV = uv * (1.0 - uv);
    let vignette = vignetteUV.x * vignetteUV.y * 15.0;
    generatedColor = generatedColor * clamp(vignette, 0.0, 1.0);

    // Temporal feedback: blend with previous frame for motion blur
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let motionBlur = clamp(warpAmount * 0.35, 0.0, 0.55);
    generatedColor = mix(generatedColor, prev, motionBlur);

    // Tone map
    generatedColor = acesToneMapping(generatedColor);

    // Sample input
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let luma = dot(generatedColor, vec3<f32>(0.299, 0.587, 0.114));
    let lineAlpha = mix(0.5, 1.0, lineIntensity + lineGlow);
    let alpha = max(lineAlpha, smoothstep(0.05, 0.4, luma));

    let finalColor = mix(inputColor.rgb, generatedColor, alpha * opacity);
    let finalAlpha = max(inputColor.a, alpha * opacity);

    let generatedDepth = distortionMag;
    let finalDepth = mix(inputDepth, generatedDepth, alpha * opacity);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));

    // Persist for temporal feedback
    textureStore(dataTextureA, coord, vec4<f32>(generatedColor, alpha));
}
