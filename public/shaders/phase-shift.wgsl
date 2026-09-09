// ═══════════════════════════════════════════════════════════════════
//  Phase Shift
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: per-channel angular period; distance-modulated phase
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

fn ping_pong(a: f32) -> f32 {
    return 1.0 - abs((fract(a * 0.5) * 2.0) - 1.0);
}

fn ping_pong_v2(v: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(ping_pong(v.x), ping_pong(v.y));
}

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 = p3 + vec3(dot(p3, p3 + vec3(33.33)));
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u2 = f * f * (vec2(3.0) - 2.0 * f);
    return mix(
        mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
        u2.y
    );
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn reconstruct_normal(uv: vec2<f32>) -> vec3<f32> {
    let offset = 1.0 / u.config.zw;
    let dx = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(offset.x, 0.0), 0.0).r
           - textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(offset.x, 0.0), 0.0).r;
    let dy = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, offset.y), 0.0).r
           - textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, offset.y), 0.0).r;
    return normalize(vec3<f32>(-dx, -dy, 1.0));
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn calculateVolumetricAlpha(layerDepth: f32, fogDensity: f32, viewDotNormal: f32, accumulatedWeight: f32) -> f32 {
    let fres = schlickFresnel(max(0.0, viewDotNormal), 0.03);
    let fogAmount = exp(-layerDepth * fogDensity * 3.0);
    let depthAlpha = mix(0.95, 0.4, fogAmount);
    let weightAlpha = mix(0.5, 0.9, smoothstep(0.0, 1.0, accumulatedWeight));
    return clamp(depthAlpha * weightAlpha * (1.0 - fres * 0.2), 0.0, 1.0);
}

fn rotateAround(uv: vec2<f32>, center: vec2<f32>, angle: f32) -> vec2<f32> {
    let toCenter = uv - center;
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(c * toCenter.x - s * toCenter.y, s * toCenter.x + c * toCenter.y) + center;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(gid.x) >= resolution.x || f32(gid.y) >= resolution.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let zoom_time = u.zoom_config.x;
    let zoom_center = u.zoom_config.yz;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let speedLow = u.zoom_params.x;
    let speedHigh = u.zoom_params.y;
    let edgeGlowParam = u.zoom_params.z;
    let fogDensity = u.zoom_params.w;

    let toMouse = uv - zoom_center;
    let dist = length(toMouse);
    // Idea 2 — distance-modulated phase.
    let distPhase = dist * (1.8 + bass * 0.4);

    var accumulatedColor = vec3<f32>(0.0);
    var accumulatedDepth = 0.0;
    var totalWeight = 0.0;
    for (var i = 0; i < 5; i = i + 1) {
        let layerDepth = f32(i) / 4.0;
        let layerSpeed = mix(speedLow, speedHigh, layerDepth);
        let layerZoom = 1.0 + fract(zoom_time * layerSpeed) * 4.0;
        let flow = vec2<f32>(
            noise(uv * 6.0 + vec2<f32>(time * 0.15, 0.0)),
            noise(uv * 6.0 + vec2<f32>(0.0, time * 0.15))
        );
        let flowUV = uv + flow * 0.015 * layerDepth;
        let transformed = (flowUV - zoom_center) / layerZoom + zoom_center;
        let wrapped = ping_pong_v2(transformed);
        let sampleColor = textureSampleLevel(readTexture, u_sampler, wrapped, 0.0).rgb;
        let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, wrapped, 0.0).r;
        let density = exp(-layerDepth * 1.5);
        let weight = density * (1.0 + sampleDepth * 0.5);
        accumulatedColor += sampleColor * weight;
        accumulatedDepth += sampleDepth * weight;
        totalWeight += weight;
    }
    let baseColor = accumulatedColor / max(totalWeight, 0.0001);
    let baseDepth = accumulatedDepth / max(totalWeight, 0.0001);

    // Idea 1 — per-channel angular period around the mouse (not a linear RGB split).
    let angR = distPhase * (0.55 + speedLow * 0.5) + time * 0.11;
    let angG = distPhase * (0.85 + mix(speedLow, speedHigh, 0.5) * 0.4) + time * 0.17;
    let angB = distPhase * (1.20 + speedHigh * 0.45) + time * 0.23 + 2.094;
    let uvR = clamp(rotateAround(uv, zoom_center, angR * 0.08), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(rotateAround(uv, zoom_center, angG * 0.08), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(rotateAround(uv, zoom_center, angB * 0.08), vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
    let chromaticColor = mix(baseColor, vec3<f32>(r, g, b), 0.55 + mids * 0.15);

    let ps = 1.0 / resolution;
    let depthX = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(ps.x, 0.0), 0.0).r;
    let depthY = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, ps.y), 0.0).r;
    let depthGrad = length(vec2<f32>(depthX - baseDepth, depthY - baseDepth));
    let edgeGlow = (exp(-depthGrad * 30.0) * baseDepth * 2.0) * mix(0.5, 2.0, edgeGlowParam);
    var finalColor = chromaticColor + vec3<f32>(edgeGlow, edgeGlow * 0.8, edgeGlow * 0.6);

    let n = reconstruct_normal(uv);
    let viewDotNormal = dot(vec3<f32>(0.0, 0.0, 1.0), n);
    let alpha = calculateVolumetricAlpha(0.5, fogDensity, viewDotNormal, totalWeight / 5.0);
    let fog = exp(-baseDepth * fogDensity * 3.0);
    let fogColor = vec3<f32>(0.02, 0.05, 0.1);
    let outRGB = aces(max(mix(finalColor, fogColor, 1.0 - fog), vec3<f32>(0.0)));
    let outColor = vec4<f32>(outRGB, clamp(alpha + dist * 0.12 + treble * 0.05, 0.0, 1.0));

    textureStore(writeTexture, coord, outColor);
    textureStore(dataTextureA, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(baseDepth, 0.0, 0.0, 0.0));
}
