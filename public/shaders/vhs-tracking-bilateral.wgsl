// ═══════════════════════════════════════════════════════════════════
//  VHS Tracking Bilateral
//  Category: advanced-hybrid
//  Features: vhs-simulation, bilateral-filter, chroma-noise, temporal
//  Complexity: High
//  Chunks From: vhs-tracking.wgsl, conv-bilateral-dream.wgsl
//  Created: 2026-04-18
//  By: Agent CB-13 — Retro & Glitch Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Full VHS signal chain physics merged with edge-preserving bilateral
//  smoothing. Chroma noise and tracking errors are filtered while
//  preserving sharp edges, creating a dreamlike analog degradation.
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

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn rgbToYuv(rgb: vec3<f32>) -> vec3<f32> {
    let y = dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
    let u_ch = dot(rgb, vec3<f32>(-0.14713, -0.28886, 0.436));
    let v = dot(rgb, vec3<f32>(0.615, -0.51499, -0.10001));
    return vec3<f32>(y, u_ch, v);
}

fn yuvToRgb(yuv: vec3<f32>) -> vec3<f32> {
    let y = yuv.x;
    let u_ch = yuv.y;
    let v = yuv.z;
    let r = y + 1.13983 * v;
    let g = y - 0.39465 * u_ch - 0.58060 * v;
    let b = y + 2.03211 * u_ch;
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let trackingError = u.zoom_params.x;
    let chromaNoiseAmt = u.zoom_params.y;
    let spatialSigma = mix(0.5, 4.0, u.zoom_params.z);
    let colorSigma = mix(0.05, 0.5, u.zoom_params.w);

    let pixelSize = 1.0 / resolution;

    // ═══ 1. VHS TIMEBASE JITTER ═══
    let scanlineIndex = floor(uv.y * resolution.y);
    let jitterSeed = scanlineIndex * 0.1 + time * 10.0;
    let jitterNoise = hash2(vec2<f32>(jitterSeed, time));
    let timebaseJitter = (jitterNoise - 0.5) * trackingError * 0.02;
    let jitteredUV = vec2<f32>(uv.x + timebaseJitter, uv.y);

    // Sample with jitter
    let sampledColor = textureSampleLevel(readTexture, u_sampler, jitteredUV, 0.0).rgb;
    var yuv = rgbToYuv(sampledColor);

    // Chroma noise
    let chromaNoiseU = noise(uv * 300.0 + vec2<f32>(time * 50.0, 0.0)) - 0.5;
    let chromaNoiseV = noise(uv * 320.0 + vec2<f32>(0.0, time * 45.0)) - 0.5;
    let driftFreq = 2.0 + trackingError * 5.0;
    let chromaDrift = sin(uv.y * 100.0 + time * driftFreq) * chromaNoiseAmt * 0.1;
    yuv.x += (noise(uv * 200.0 + time * 60.0) - 0.5) * chromaNoiseAmt * 0.1;
    yuv.y += chromaNoiseU * chromaNoiseAmt * 0.4 + chromaDrift;
    yuv.z += chromaNoiseV * chromaNoiseAmt * 0.4 + chromaDrift * 0.7;

    var color = yuvToRgb(yuv);

    // ═══ 2. CONTROL TRACK DROPOUTS ═══
    let dropoutBase = uv.y * 20.0 - time * 2.0;
    let dropoutPhase = fract(dropoutBase);
    let dropoutEnvelope = exp(-dropoutPhase * 10.0);
    let dropoutRand = hash2(vec2<f32>(floor(dropoutBase), time * 0.5));
    let dropoutActive = step(1.0 - trackingError * 0.3, dropoutRand);
    let dropoutNoise = (noise(uv * 500.0 + time * 100.0) - 0.5) * dropoutEnvelope * dropoutActive;
    color += dropoutNoise * 0.5;

    // Head switching noise
    let headSwitchY = 0.95 + sin(time * 2.0) * 0.02;
    let headSwitchBand = smoothstep(0.03, 0.0, abs(uv.y - headSwitchY));
    color += (hash2(vec2<f32>(uv.x * 100.0, time * 30.0)) - 0.5) * headSwitchBand * trackingError * 0.3;

    // ═══ 3. BILATERAL DREAM SMOOTHING ═══
    let center = color;
    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;
    let radius = i32(ceil(spatialSigma * 2.5));
    let maxRadius = min(radius, 5);

    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let neighbor = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
            let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
            let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * spatialSigma * spatialSigma + 0.001));
            let colorDist = length(neighbor - center);
            let rangeWeight = exp(-colorDist * colorDist / (2.0 * colorSigma * colorSigma + 0.001));
            let weight = spatialWeight * rangeWeight;
            accumColor += neighbor * weight;
            accumWeight += weight;
        }
    }

    if (accumWeight > 0.001) {
        color = mix(color, accumColor / accumWeight, 0.6);
    }

    // ═══ 4. SCANLINES & QUANTIZATION ═══
    let scanlineFreq = resolution.y * 0.5;
    let scanline = sin(uv.y * scanlineFreq * 3.14159) * 0.5 + 0.5;
    let luma = rgbToYuv(color).x;
    let scanlineMod = mix(0.7, 1.0, luma);
    color *= mix(1.0, scanline * scanlineMod, 0.15);

    let quantizationSteps = 32.0 + (1.0 - chromaNoiseAmt) * 64.0;
    color = floor(color * quantizationSteps) / quantizationSteps;

    // VHS color grading
    color = color * 0.92 + 0.05;
    let gray = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = mix(vec3<f32>(gray), color, 0.85);
    color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
