// ═══════════════════════════════════════════════════════════════════
//  Pixel Sort Glitch
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: anchored span rank sort (per-line hashed span phase, pixel takes the k-th luma of its span); FFT-banded span length (column band's bin lengthens its drips); span-end channel slip (R/B tear along sortDir at the bright end)
//  A packing: edgeDir.xy*0.5+0.5, edgeMag, threshold mask (C unread)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn luminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn detectEdge(uv: vec2<f32>, resolution: vec2<f32>) -> vec2<f32> {
    let texel = 1.0 / resolution;
    let c00 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, -texel.y), 0.0);
    let c10 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0);
    let c20 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, -texel.y), 0.0);
    let c01 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0);
    let c21 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0);
    let c02 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, texel.y), 0.0);
    let c12 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0);
    let c22 = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, texel.y), 0.0);
    let gx = -1.0 * luminance(c00.rgb) + 1.0 * luminance(c20.rgb)
             -2.0 * luminance(c01.rgb) + 2.0 * luminance(c21.rgb)
             -1.0 * luminance(c02.rgb) + 1.0 * luminance(c22.rgb);
    let gy = -1.0 * luminance(c00.rgb) - 1.0 * luminance(c20.rgb)
              +1.0 * luminance(c02.rgb) + 1.0 * luminance(c22.rgb);
    return vec2<f32>(gx, gy);
}

fn edgeDirection(grad: vec2<f32>) -> vec2<f32> {
    let mag = length(grad);
    if (mag < 0.001) {
        return vec2<f32>(1.0, 0.0);
    }
    return grad / mag;
}

// IDEA 1: anchored span rank sort. Spans of `spanLen` pixels are laid along sortDir with a
// per-line hashed phase; every pixel of a span reads the same samples and outputs the
// element whose luma rank equals its own position in the span -> a true ascending sort.
// (HEAD did one bubble pass, then returned the sample nearest its own luma = identity.)
// Returns rgb + position-in-span t (0 = dark end, 1 = bright end).
fn spanSort(uv: vec2<f32>, resolution: vec2<f32>, sortDir: vec2<f32>, spanLen: i32) -> vec4<f32> {
    let pix = uv * resolution;
    let along = dot(pix, sortDir);
    let across = dot(pix, vec2<f32>(-sortDir.y, sortDir.x));
    let n = clamp(spanLen, 2, 32);
    let fn_ = f32(n);
    let phase = hash12(vec2<f32>(floor(across), 17.0)) * fn_;
    let local = along + phase;
    let pos = i32(clamp(floor(local - floor(local / fn_) * fn_), 0.0, fn_ - 1.0));
    let start = along - f32(pos);
    var cols: array<vec3<f32>, 32>;
    var lums: array<f32, 32>;
    for (var i: i32 = 0; i < n; i = i + 1) {
        let p = pix + sortDir * (start + f32(i) - along);
        let c = textureSampleLevel(readTexture, u_sampler, clamp(p / resolution, vec2<f32>(0.0), vec2<f32>(0.999)), 0.0).rgb;
        cols[i] = c;
        lums[i] = luminance(c) + f32(i) * 1e-5; // strict order for ties
    }
    var result = cols[pos];
    for (var i: i32 = 0; i < n; i = i + 1) {
        var rank = 0;
        for (var j: i32 = 0; j < n; j = j + 1) {
            if (lums[j] < lums[i]) { rank = rank + 1; }
        }
        if (rank == pos) { result = cols[i]; }
    }
    return vec4<f32>(result, f32(pos) / (fn_ - 1.0));
}

fn flowSort(uv: vec2<f32>, resolution: vec2<f32>,
            sortDir: vec2<f32>, flowStrength: f32, threshold: f32) -> vec3<f32> {
    var accum = vec3<f32>(0.0);
    var weight = 0.0;
    for (var i: i32 = 0; i < 8; i = i + 1) {
        let t = f32(i) / 7.0;
        let offset = (t - 0.5) * 2.0 * flowStrength;
        let sampleUV = uv + sortDir * offset / resolution;
        let col = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(0.999)), 0.0).rgb;
        let w = max(0.0, luminance(col) - threshold);
        accum = accum + col * w;
        weight = weight + w;
    }
    if (weight > 0.0) {
        return accum / weight;
    }
    return textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let currentTime = u.config.x;
    let held = u.zoom_config.w > 0.5;
    let aspect = resolution.x / resolution.y;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let threshold = u.zoom_params.x;
    let directionMode = u.zoom_params.y;
    var windowSize = u.zoom_params.z * 31.0 + 1.0;
    let edgeInfluence = u.zoom_params.w;

    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    // FIX: the extraBuffer[133..136] spring is re-zeroed every frame, so the epicenter sat
    // near (0,0) and the pointer-y threshold term was always ~0. Use the live pointer.
    let mousePos = rawMouse;

    let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
    let epicenterBoost = (1.0 - smoothstep(0.0, 0.45, mouseDist)) * select(1.0, 1.4, held);
    windowSize = windowSize * mix(1.0, 0.72, select(0.0, epicenterBoost, held));

    var tearOffset = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let ripple = u.ripples[ri];
        let age = currentTime - ripple.z;
        if (age >= 0.0 && age < 0.9) {
            let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
            let front = smoothstep(0.03, 0.0, abs(rDist - age * 0.4)) * exp(-age * 1.4);
            let seed = hash12(ripple.xy + vec2<f32>(ripple.z));
            tearOffset = tearOffset + vec2<f32>(cos(seed * 6.28), sin(seed * 6.28)) * front * 0.04;
        }
    }

    let sortUV = clamp(uv + tearOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let mouseThreshold = mousePos.y;
    let effectiveThreshold = clamp(threshold * 0.7 + mouseThreshold * 0.3 - epicenterBoost * 0.08, 0.0, 1.0);

    let currentColor = textureSampleLevel(readTexture, u_sampler, sortUV, 0.0).rgb;
    let currentLuma = luminance(currentColor);

    let edgeGrad = detectEdge(sortUV, resolution);
    let edgeMag = length(edgeGrad);
    let edgeDir = edgeDirection(edgeGrad);

    var sortDir: vec2<f32>;
    if (directionMode < 0.33) {
        sortDir = vec2<f32>(1.0, 0.0);
    } else if (directionMode < 0.66) {
        sortDir = vec2<f32>(0.0, 1.0);
    } else {
        sortDir = normalize(mix(vec2<f32>(1.0, 0.0), edgeDir, edgeInfluence));
    }

    let mask = currentLuma > effectiveThreshold;
    let maskSmooth = smoothstep(effectiveThreshold - 0.1, effectiveThreshold + 0.1, currentLuma);

    var outputColor: vec3<f32>;
    // IDEA 2: FFT-banded span length — the pixel's column band reads one FFT bin
    // (extraBuffer[5..132]); loud bands grow longer drips. Replaces dead plasmaBuffer[1..8].
    let band = u32(clamp(uv.x * 8.0, 0.0, 7.0));
    let blockVoice = clamp(extraBuffer[5u + band * 6u], 0.0, 1.0);
    var tSpan = 0.5;
    if (mask) {
        let iWindowSize = i32(clamp(windowSize * (1.0 + blockVoice * 0.8 + bass * 0.3), 2.0, 32.0));
        let flowStrength = (currentLuma - effectiveThreshold) / (1.0 - effectiveThreshold + 0.001);
        if (flowStrength > 0.5 && edgeInfluence > 0.5) {
            outputColor = flowSort(sortUV, resolution, sortDir, flowStrength * 50.0, effectiveThreshold);
        } else {
            let sorted = spanSort(sortUV, resolution, sortDir, iWindowSize);
            outputColor = sorted.rgb;
            tSpan = sorted.w;
            // IDEA 3: span-end channel slip — at the bright end of each span the R and B
            // channels tear along sortDir by a couple of pixels (treble widens the tear).
            let slip = smoothstep(0.7, 1.0, tSpan) * (1.5 + treble * 3.0) / resolution;
            let rS = textureSampleLevel(readTexture, u_sampler, clamp(sortUV + sortDir * slip, vec2<f32>(0.0), vec2<f32>(0.999)), 0.0).r;
            let bS = textureSampleLevel(readTexture, u_sampler, clamp(sortUV - sortDir * slip, vec2<f32>(0.0), vec2<f32>(0.999)), 0.0).b;
            let slipAmt = smoothstep(0.7, 1.0, tSpan) * 0.6;
            outputColor = vec3<f32>(mix(outputColor.r, rS, slipAmt), outputColor.g, mix(outputColor.b, bS, slipAmt));
        }
        let noise = fract(sin(dot(sortUV * currentTime, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        let glitchAmount = (currentLuma - effectiveThreshold) * 0.1 * noise * (1.0 + treble * 0.5 + blockVoice * 0.3);
        outputColor = mix(currentColor, outputColor, maskSmooth);
        outputColor = outputColor + vec3<f32>(glitchAmount * 0.2);
    } else {
        outputColor = currentColor;
    }

    let edgeHighlight = edgeMag * edgeInfluence * 0.5;
    outputColor = outputColor + vec3<f32>(edgeHighlight * 0.1);
    outputColor = outputColor * (1.0 + bass * 0.04 + mids * 0.02);
    outputColor = clamp(outputColor, vec3<f32>(0.0), vec3<f32>(4.0));

    // Semantic alpha: opaque picture, sorted coverage reads as full; untouched areas 0.85.
    let alpha = clamp(0.85 + maskSmooth * 0.15 + edgeMag * 0.05, 0.0, 1.0);
    let displayRgb = acesToneMap(outputColor);

    textureStore(writeTexture, coord, vec4<f32>(displayRgb, alpha));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(edgeDir * 0.5 + 0.5, edgeMag, maskSmooth));
}
