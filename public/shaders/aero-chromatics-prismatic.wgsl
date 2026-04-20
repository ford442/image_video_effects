// ═══════════════════════════════════════════════════════════════════
//  aero-chromatics-prismatic
//  Category: advanced-hybrid
//  Features: prismatic-dispersion, chromatic-advection, cauchy-equation
//  Complexity: High
//  Chunks From: aero-chromatics.wgsl, spec-prismatic-dispersion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-8 — Thermal & Atmospheric Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Wind-driven chromatic smoke trails enhanced with physical prismatic
//  dispersion. Each RGB channel is refracted through a virtual lens
//  at a different wavelength via Cauchy's equation, creating rainbow
//  edge effects on the advected smoke.
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

// ═══ CHUNK: Cauchy IOR (from spec-prismatic-dispersion.wgsl) ═══
fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
    let lambdaUm = wavelengthNm * 0.001;
    return A + B / (lambdaUm * lambdaUm);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
    let g = 1.0 - abs(t - 0.4) * 3.0;
    let b = 1.0 - smoothstep(0.0, 0.4, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn refractThroughSurface(uv: vec2<f32>, center: vec2<f32>, ior: f32, curvature: f32) -> vec2<f32> {
    let toCenter = uv - center;
    let dist = length(toCenter);
    let lensStrength = curvature * 0.4;
    let offset = toCenter * (1.0 - 1.0 / ior) * lensStrength * (1.0 + dist * 2.0);
    return uv + offset;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / res.y;
    let mouse = u.zoom_config.yz;

    // Parameters
    let windStrength = mix(0.5, 5.0, u.zoom_params.x);
    let decay = mix(0.8, 0.995, u.zoom_params.y);
    let chromaSplit = u.zoom_params.z * 0.02;
    let sourceMix = mix(0.01, 0.2, u.zoom_params.w);

    // Glass curvature from wind strength
    let glassCurvature = mix(0.1, 0.8, u.zoom_params.x);
    let cauchyB = mix(0.01, 0.06, u.zoom_params.z);
    let spectralSat = mix(0.3, 1.2, u.zoom_params.w);

    let currentFrame = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(currentFrame.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let drag = 1.0 - (luma * 0.8);

    // Wind vector (from aero-chromatics)
    let dVec = uv - mouse;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
    let mouseInfluence = smoothstep(0.5, 0.0, dist);
    let baseWind = vec2<f32>(0.0, -0.001);
    let mouseWind = normalize(dVec) * 0.01 * mouseInfluence * windStrength;
    let velocity = (baseWind + mouseWind) * (luma * 2.0);

    // Chromatic advection offsets
    let offsetR = velocity * (1.0 + chromaSplit);
    let offsetG = velocity;
    let offsetB = velocity * (1.0 - chromaSplit);

    let prevR = textureSampleLevel(dataTextureC, u_sampler, uv - offsetR, 0.0).r;
    let prevG = textureSampleLevel(dataTextureC, u_sampler, uv - offsetG, 0.0).g;
    let prevB = textureSampleLevel(dataTextureC, u_sampler, uv - offsetB, 0.0).b;
    let prevAlpha = textureSampleLevel(dataTextureC, u_sampler, uv - velocity, 0.0).a;

    let historyColor = vec3<f32>(prevR, prevG, prevB);
    let injectAmount = sourceMix * luma;
    var advectedColor = mix(historyColor * decay, currentFrame.rgb, injectAmount);
    advectedColor = max(vec3<f32>(0.0), advectedColor);

    // ═══ Prismatic Dispersion (from spec-prismatic-dispersion) ═══
    let lensCenter = mouse;
    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
    var prismaticColor = vec3<f32>(0.0);
    var spectralResponse = vec4<f32>(0.0);

    for (var i: i32 = 0; i < 4; i = i + 1) {
        let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyB);
        let refractedUV = refractThroughSurface(uv, lensCenter, ior, glassCurvature);
        let wrappedUV = fract(refractedUV);
        let sample = textureSampleLevel(readTexture, u_sampler, wrappedUV, 0.0);
        let absorption = exp(-glassCurvature * (4.0 - f32(i)) * 0.15);
        let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[i])) * absorption;
        spectralResponse[i] = bandIntensity;
        prismaticColor += wavelengthToRGB(WAVELENGTHS[i]) * bandIntensity * spectralSat;
    }

    // Blend advected smoke with prismatic tint
    let lumaFinal = dot(advectedColor, vec3<f32>(0.299, 0.587, 0.114));
    let prismaticBlend = smoothstep(0.1, 0.5, lumaFinal) * mouseInfluence;
    var finalColor = mix(advectedColor, prismaticColor, prismaticBlend * 0.6);

    // Alpha calculation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = mix(0.7, 1.0, lumaFinal);
    let finalAlpha = mix(alpha * 0.8, alpha, depth);

    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4(depth, 0.0, 0.0, 0.0));
}
