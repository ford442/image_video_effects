// ═══════════════════════════════════════════════════════════════════
//  divine-light-iridescence
//  Category: advanced-hybrid
//  Features: god-rays, thin-film-interference, volumetric-light, mouse-driven
//  Complexity: Very High
//  Chunks From: divine-light.wgsl, spec-iridescence-engine.wgsl
//  Created: 2026-04-18
//  By: Agent CB-19 — Lighting & Energy Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Volumetric god rays from cursor with thin-film iridescence.
//  Light beams shimmer with soap-bubble interference colors
//  driven by ray intensity and animated turbulence.
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

// ═══ CHUNK: hash12 (from spec-iridescence-engine.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: wavelengthToRGB (from spec-iridescence-engine.wgsl) ═══
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
    let g = 1.0 - abs(t - 0.45) * 2.5;
    let b = 1.0 - smoothstep(0.0, 0.45, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

// ═══ CHUNK: thinFilmColor (from spec-iridescence-engine.wgsl) ═══
fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
    let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
    let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
    let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;
    var color = vec3<f32>(0.0);
    var sampleCount = 0.0;
    for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 20.0) {
        let phase = opd / lambda;
        let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
        color += wavelengthToRGB(lambda) * interference;
        sampleCount = sampleCount + 1.0;
    }
    return color / max(sampleCount, 1.0);
}

// ═══ CHUNK: luminanceKeyAlpha (from divine-light.wgsl) ═══
fn luminanceKeyAlpha(color: vec3<f32>, threshold: f32, softness: f32) -> f32 {
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    return smoothstep(threshold - softness, threshold + softness, luma);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;

    // Parameters
    let rayIntensity = u.zoom_params.x * 2.0;
    let lumaThreshold = u.zoom_params.y * 0.3;
    let softness = u.zoom_params.z * 0.25;
    let rayCount = u.zoom_params.w * 20.0 + 5.0;
    let filmIOR = mix(1.2, 2.4, u.zoom_params.z);
    let iridIntensity = mix(0.3, 1.2, u.zoom_params.w);

    let lightPos = u.zoom_config.yz;
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // God ray calculation (from divine-light)
    let toLight = lightPos - uv;
    let lightAngle = atan2(toLight.y, toLight.x);
    let lightDist = length(toLight);

    var rayAccum = 0.0;
    for (var i: i32 = 0; i < i32(rayCount); i = i + 1) {
        let fi = f32(i);
        let rayAngle = lightAngle + fi * 0.3 + sin(time * 0.5 + fi) * 0.1;
        let rayDir = vec2<f32>(cos(rayAngle), sin(rayAngle));
        var pos = uv;
        var rIntensity = 0.0;
        for (var j: i32 = 0; j < 10; j = j + 1) {
            pos = pos + rayDir * 0.02;
            if (pos.x < 0.0 || pos.x > 1.0 || pos.y < 0.0 || pos.y > 1.0) { break; }
            let n = hash12(pos * 5.0 + time * 0.1);
            rIntensity += n * 0.1 / (1.0 + f32(j) * 0.1);
        }
        rayAccum += rIntensity;
    }

    // ═══ Iridescence on divine rays ═══
    let toCenter = uv - vec2<f32>(0.5);
    let viewDist = length(toCenter);
    let cosTheta = sqrt(max(1.0 - viewDist * viewDist * 0.5, 0.01));

    let noiseVal = hash12(uv * 12.0 + time * 0.1) * 0.5
                 + hash12(uv * 25.0 - time * 0.15) * 0.25;
    let filmThicknessBase = mix(300.0, 800.0, rayAccum);
    var thickness = filmThicknessBase * (0.7 + rayAccum * 0.6 + noiseVal * 0.3);

    let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * iridIntensity;

    // Fresnel blend
    let fresnel = pow(1.0 - cosTheta, 3.0);
    let divineColor = mix(vec3<f32>(1.0, 0.9, 0.7), iridescent, fresnel * 0.7);
    let finalDivine = divineColor * rayAccum * rayIntensity;

    let finalColor = baseSample.rgb + finalDivine;
    let alpha = luminanceKeyAlpha(finalDivine, rayAccum * rayIntensity, u.zoom_params);

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, max(baseSample.a, alpha)));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(finalDivine, thickness / 1000.0));
}
