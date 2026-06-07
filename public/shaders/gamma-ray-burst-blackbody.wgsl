// ═══════════════════════════════════════════════════════════════════
//  gamma-ray-burst-blackbody
//  Category: advanced-hybrid
//  Features: radial-blur, blackbody-thermal, mouse-driven, HDR, exposure-burst
//  Complexity: Very High
//  Chunks From: gamma-ray-burst.wgsl, spec-blackbody-thermal.wgsl
//  Created: 2026-04-18
//  By: Agent CB-19 — Lighting & Energy Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Intense gamma-ray burst with physically-correct blackbody thermal
//  coloring. Radial blur samples are mapped to temperature via luminance,
//  creating an authentic stellar explosion from deep-red embers to
//  blue-white plasma at the epicenter.
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

// ═══ CHUNK: blackbodyColor (from spec-blackbody-thermal.wgsl) ═══
fn blackbodyColor(temperatureK: f32) -> vec3<f32> {
    let t = clamp(temperatureK / 1000.0, 0.5, 30.0);
    var r: f32;
    var g: f32;
    var b: f32;
    if (t <= 6.5) {
        r = 1.0;
        g = clamp(0.39 * log(t) - 0.63, 0.0, 1.0);
        b = clamp(0.54 * log(t - 1.0) - 1.0, 0.0, 1.0);
    } else {
        r = clamp(1.29 * pow(t - 0.6, -0.133), 0.0, 1.0);
        g = clamp(1.29 * pow(t - 0.6, -0.076), 0.0, 1.0);
        b = 1.0;
    }
    let radiance = pow(t / 6.5, 4.0);
    return vec3<f32>(r, g, b) * radiance;
}

// ═══ CHUNK: toneMapACES (from spec-blackbody-thermal.wgsl) ═══
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;

    // Parameters
    let intensity = u.zoom_params.x * 2.0 + 0.5;
    let decay = u.zoom_params.y * 0.1 + 0.9;
    let rayDensity = u.zoom_params.z * 50.0 + 10.0;
    let exposure = u.zoom_params.w * 2.0 + 1.0;
    let tempRangeLow = mix(800.0, 2500.0, u.zoom_params.x);
    let tempRangeHigh = mix(4000.0, 20000.0, u.zoom_params.y);
    let thermalIntensity = mix(0.5, 3.0, u.zoom_params.z);

    let mouse = u.zoom_config.yz;
    let dir = uv - mouse;
    let dist = length(dir * vec2<f32>(aspect, 1.0));

    // Radial blur with thermal coloring
    let samples = 20;
    var acc = vec3<f32>(0.0);
    var weightSum = 0.0;
    let dither = hash12(uv * time);

    for (var i = 0; i < samples; i = i + 1) {
        let t = (f32(i) + dither) / f32(samples);
        let sampleUV = mix(uv, mouse, t * 0.3 * intensity);
        let col = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let w = pow(decay, f32(i));
        let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
        let boost = smoothstep(0.5, 1.0, luma) * 2.0;

        // ═══ Blackbody thermal per sample ═══
        let temperature = mix(tempRangeLow, tempRangeHigh, luma);
        let thermal = blackbodyColor(temperature) * thermalIntensity;
        let thermallyTinted = mix(col, thermal, 0.6);

        acc += thermallyTinted * w * (1.0 + boost);
        weightSum += w;
    }

    var finalColor = acc / weightSum;

    // Rays
    let angle = atan2(dir.y, dir.x);
    let ray = sin(angle * rayDensity + time * 2.0)
            + 0.5 * sin(angle * rayDensity * 2.3 - time);
    let rayMask = smoothstep(0.0, 1.0, ray);
    let rayColor = mix(vec3<f32>(0.5, 0.8, 1.0), blackbodyColor(tempRangeHigh) * thermalIntensity, 0.5);
    finalColor += rayColor * rayMask * 0.1 * intensity / (dist + 0.1);

    // Central overexposure with thermal peak
    let glare = 1.0 / (dist * 10.0 + 0.1);
    let coreTemp = mix(tempRangeHigh * 0.8, tempRangeHigh, smoothstep(0.1, 0.0, dist));
    let coreColor = mix(vec3<f32>(1.0, 0.95, 0.8), blackbodyColor(coreTemp) * thermalIntensity, 0.5);
    finalColor += coreColor * glare * exposure * 0.5;

    // Vignette
    finalColor *= smoothstep(1.5, 0.0, dist);

    finalColor = toneMapACES(finalColor);

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(finalColor, dist));
}
