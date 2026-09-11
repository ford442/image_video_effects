// ═══════════════════════════════════════════════════════════════════
//  PP SSAO
//  Category: post-processing
//  Features: depth-aware, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: cosine-weighted hemisphere; bent-normal color bleed
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

fn random(uv: vec2<f32>) -> f32 {
    return fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn getNormalFromDepth(uv: vec2<f32>, invRes: vec2<f32>) -> vec3<f32> {
    let center = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let left = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(invRes.x, 0.0), 0.0).r;
    let right = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(invRes.x, 0.0), 0.0).r;
    let top = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, invRes.y), 0.0).r;
    let bottom = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, invRes.y), 0.0).r;
    return normalize(vec3<f32>(left - right, top - bottom, 0.01));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let invRes = 1.0 / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let held = step(0.5, u.zoom_config.w);
    let mouseDelta = (uv - u.zoom_config.yz) * vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
    let pointerField = exp(-dot(mouseDelta, mouseDelta) * 18.0) * held;

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var rippleIndex: u32 = 0u; rippleIndex < rippleCount; rippleIndex = rippleIndex + 1u) {
        let ripple = u.ripples[rippleIndex];
        let rippleAge = max(time - ripple.z, 0.0);
        let front = abs(distance(uv, ripple.xy) - rippleAge * (0.20 + bass * 0.10));
        clickFront += exp(-front * 120.0) * exp(-rippleAge * 1.6);
    }

    let scanPacket = pow(max(0.0, sin((uv.y + uv.x * 0.27) * 58.0 - time * (14.0 + mids * 7.0))), 16.0);
    let kernelPulse = 0.5 + 0.5 * sin(uv.x * 31.0 + uv.y * 19.0 - time * (9.0 + treble * 6.0));
    let radius = (0.01 + u.zoom_params.x * 0.05) * (1.0 + pointerField * 0.45 + bass * 0.18);
    let intensity = u.zoom_params.y * (1.0 + clickFront * 0.35 + mids * 0.20);
    let quality = u.zoom_params.z;
    let colorBleed = u.zoom_params.w;

    var sampleCount: i32 = 4;
    sampleCount = select(sampleCount, 8, quality >= 0.33);
    sampleCount = select(sampleCount, 16, quality >= 0.66);

    let centerDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let centerNormal = getNormalFromDepth(uv, invRes);
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    var occlusion = 0.0;
    var colorInfluence = vec3<f32>(0.0);
    var bent = vec2<f32>(0.0);
    var weightSum = 0.0;

    for (var i: i32 = 0; i < sampleCount; i = i + 1) {
        let angle = f32(i) / f32(sampleCount) * 6.28318 + random(uv + f32(i)) * 0.5 + time * (0.75 + treble * 0.35);
        let dist = radius * (0.5 + random(uv * 2.0 + f32(i)) * 0.5);
        let offset = vec2<f32>(cos(angle), sin(angle)) * dist;
        let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
        let inBounds = f32(uv.x + offset.x >= 0.0 && uv.x + offset.x <= 1.0 && uv.y + offset.y >= 0.0 && uv.y + offset.y <= 1.0);

        let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
        let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let depthDiff = sampleDepth - centerDepth;
        let offsetDir = vec3<f32>(offset.x, offset.y, 0.002);
        let cosine = max(dot(centerNormal, normalize(offsetDir)), 0.0);
        let occluding = f32(depthDiff < 0.0 && depthDiff > -radius * 2.0) * inBounds;
        let falloff = (1.0 - smoothstep(0.0, radius, -depthDiff)) * cosine;
        let occW = falloff * occluding;
        occlusion += occW;
        colorInfluence += sampleColor * occW;
        weightSum += occW;
        bent += offset * (1.0 - occluding) * inBounds * cosine;
    }

    occlusion = clamp(occlusion / max(f32(sampleCount), 1.0), 0.0, 1.0) * intensity;
    let ao = 1.0 - occlusion;
    var finalColor = src.rgb * (0.5 + 0.5 * ao);

    let bleedSrc = colorInfluence / max(weightSum, 0.001);
    let bentDir = bent / max(length(bent), 0.0001);
    let bentUV = clamp(uv + bentDir * radius * 0.65, vec2<f32>(0.0), vec2<f32>(1.0));
    let bentColor = textureSampleLevel(readTexture, u_sampler, bentUV, 0.0).rgb;
    let bleedColor = mix(bleedSrc, bentColor, 0.45);
    finalColor = mix(finalColor, finalColor * bleedColor * 1.5, occlusion * colorBleed);

    finalColor += vec3<f32>(0.10, 0.24, 0.48) * scanPacket * (0.05 + colorBleed * 0.16 + mids * 0.12);
    finalColor += vec3<f32>(0.65, 0.32, 0.12) * clickFront * (0.04 + colorBleed * 0.12);
    finalColor *= 1.0 - kernelPulse * occlusion * (0.04 + treble * 0.08);
    finalColor = aces(max(finalColor, vec3<f32>(0.0)));

    let alpha = clamp(src.a * 0.35 + occlusion * 0.55 + pointerField * 0.15 + clickFront * 0.12, 0.0, 1.0);
    let outColor = vec4<f32>(finalColor, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(centerDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
