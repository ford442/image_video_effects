// ═══════════════════════════════════════════════════════════════════
//  Pixel Sort Glitch — Batch 61
//  Edge-aware threshold sort + spring epicenter, held, ripples, audio,
//  ACES display, semantic alpha. A: edgeDir.xy packed, edgeMag, mask.
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

fn sortWindow(uv: vec2<f32>, resolution: vec2<f32>,
              sortDir: vec2<f32>, windowSize: i32,
              currentLuma: f32, currentColor: vec3<f32>) -> vec3<f32> {
    var samples: array<vec4<f32>, 32>;
    var count: i32 = 0;
    let halfWindow = windowSize / 2;
    for (var i: i32 = -halfWindow; i <= halfWindow; i = i + 1) {
        if (count >= 32) { break; }
        let sampleUV = uv + sortDir * f32(i) / resolution;
        let col = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(0.999)), 0.0).rgb;
        samples[count] = vec4<f32>(col, luminance(col));
        count = count + 1;
    }
    for (var j: i32 = 0; j < count - 1; j = j + 1) {
        if (samples[j].w > samples[j + 1].w) {
            let temp = samples[j];
            samples[j] = samples[j + 1];
            samples[j + 1] = temp;
        }
    }
    var result = currentColor;
    var minDiff: f32 = 1000.0;
    for (var k: i32 = 0; k < count; k = k + 1) {
        let diff = abs(samples[k].w - currentLuma);
        if (diff < minDiff) {
            minDiff = diff;
            result = samples[k].rgb;
        }
    }
    return result;
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
    var mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);

    if (global_id.x == 0u && global_id.y == 0u) {
        if (mousePos.x == 0.0 && mousePos.y == 0.0 && currentTime < 2.0) {
            mousePos = rawMouse;
            mouseVel = vec2<f32>(0.0);
        }
        mouseVel = (mouseVel + (rawMouse - mousePos) * 0.16) * 0.74;
        mousePos = mousePos + mouseVel;
        extraBuffer[133] = mousePos.x;
        extraBuffer[134] = mousePos.y;
        extraBuffer[135] = mouseVel.x;
        extraBuffer[136] = mouseVel.y;
    }

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
    if (mask) {
        let iWindowSize = i32(clamp(windowSize, 1.0, 32.0));
        let flowStrength = (currentLuma - effectiveThreshold) / (1.0 - effectiveThreshold + 0.001);
        if (flowStrength > 0.5 && edgeInfluence > 0.5) {
            outputColor = flowSort(sortUV, resolution, sortDir, flowStrength * 50.0, effectiveThreshold);
        } else {
            outputColor = sortWindow(sortUV, resolution, sortDir, iWindowSize, currentLuma, currentColor);
        }
        let binIndex = (u32(uv.x * 8.0) % 8u) + 1u;
        let blockVoice = plasmaBuffer[binIndex].x;
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

    let alpha = clamp(maskSmooth * 0.55 + edgeMag * 0.25 + epicenterBoost * 0.15 + bass * 0.05, 0.0, 1.0);
    let displayRgb = acesToneMap(outputColor);

    textureStore(writeTexture, coord, vec4<f32>(displayRgb, alpha));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(edgeDir * 0.5 + 0.5, edgeMag, maskSmooth));
}
