// ═══════════════════════════════════════════════════════════════════
//  spec-prismatic-dispersion
//  Category: advanced-hybrid
//  Features: spectral-rendering, mouse-driven, physical-dispersion
//  Complexity: High
//  Chunks From: chunk-library (hash12)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  4-Band Spectral Dispersion Through Glass
//  Treats RGBA as 4 physical wavelength bands (450nm, 520nm, 600nm, 680nm).
//  Each band refracts at a different angle via Cauchy's equation.
//  Final color reconstructed using CIE color matching.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Cauchy's equation for refractive index
fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
    let lambdaUm = wavelengthNm * 0.001;
    return A + B / (lambdaUm * lambdaUm);
}

// Simplified CIE 1931 color matching for wavelength
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    let glassCurvature = mix(0.1, 1.2, u.zoom_params.x);
    let cauchyB = mix(0.01, 0.08, u.zoom_params.y);
    let glassThickness = mix(0.3, 1.5, u.zoom_params.z);
    let spectralSat = mix(0.3, 1.2, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Dynamic lens center: mouse if clicked, else slow orbit
    var lensCenter = vec2<f32>(0.5, 0.5);
    if (isMouseDown) {
        lensCenter = mousePos;
    } else {
        lensCenter = vec2<f32>(
            0.5 + sin(time * 0.2) * 0.25,
            0.5 + cos(time * 0.15) * 0.2
        );
    }

    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
    var finalColor = vec3<f32>(0.0);
    var spectralResponse = vec4<f32>(0.0);

    for (var i: i32 = 0; i < 4; i = i + 1) {
        let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyB);
        let refractedUV = refractThroughSurface(uv, lensCenter, ior, glassCurvature);

        // Wrap UV for continuous refraction
        let wrappedUV = fract(refractedUV);
        let sample = textureSampleLevel(readTexture, u_sampler, wrappedUV, 0.0);

        // Beer-Lambert absorption based on thickness and wavelength
        let absorption = exp(-glassThickness * (4.0 - f32(i)) * 0.15);
        let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[i])) * absorption;

        spectralResponse[i] = bandIntensity;
        finalColor += wavelengthToRGB(WAVELENGTHS[i]) * bandIntensity * spectralSat;
    }

    // Add subtle chromatic aberration glow
    let glowRadius = glassCurvature * 0.02;
    var glowColor = vec3<f32>(0.0);
    let glowSamples = 8;
    for (var j: i32 = 0; j < glowSamples; j = j + 1) {
        let angle = f32(j) * 0.785398 + time * 0.5;
        let offset = vec2<f32>(cos(angle), sin(angle)) * glowRadius;
        let gSample = textureSampleLevel(readTexture, u_sampler, fract(uv + offset), 0.0);
        glowColor += gSample.rgb;
    }
    glowColor /= f32(glowSamples);
    finalColor += glowColor * 0.08 * glassCurvature;

    // Tone map and clamp
    finalColor = finalColor / (1.0 + finalColor * 0.3);

    textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, spectralResponse.w));
    textureStore(dataTextureA, gid.xy, spectralResponse);
}
