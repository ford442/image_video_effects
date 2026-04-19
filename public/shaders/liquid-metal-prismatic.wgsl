// ═══════════════════════════════════════════════════════════════════
//  liquid-metal-prismatic
//  Category: advanced-hybrid
//  Features: spectral-rendering, liquid, metallic, physical-dispersion
//  Complexity: High
//  Chunks From: liquid-metal.wgsl, spec-prismatic-dispersion.wgsl
//  Created: 2026-04-18
//  By: Agent CB-1 — Spectral & Physical Light Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Liquid metal ripple distortion combined with 4-band spectral
//  prismatic dispersion. The curved metal surface acts as a dynamic
//  liquid prism — ripples create varying curvature that refracts
//  light into separated wavelength bands via Cauchy's equation.
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
  zoom_params: vec4<f32>,  // x=RippleSpeed, y=RippleIntensity, z=GlassCurvature, w=SpectralSat
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: fresnel (from liquid-metal.wgsl) ═══
fn fresnel(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// ═══ CHUNK: Cauchy IOR & wavelengthToRGB (from spec-prismatic-dispersion.wgsl) ═══
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
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let rippleSpeed = u.zoom_params.x;
    let rippleIntensity = u.zoom_params.y * 0.1;
    let glassCurvature = mix(0.1, 1.2, u.zoom_params.z);
    let spectralSat = mix(0.3, 1.2, u.zoom_params.w);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Liquid metal ripples — these become the dynamic prism curvature
    let ripple = sin(length(uv - 0.5) * 20.0 - time * rippleSpeed) * rippleIntensity;
    // Secondary ripple for more complex surface
    let ripple2 = cos(length(uv - vec2<f32>(0.3, 0.7)) * 30.0 - time * rippleSpeed * 1.3) * rippleIntensity * 0.5;
    let totalRipple = ripple + ripple2;
    let warpedUV = uv + vec2<f32>(totalRipple);

    // Metallic surface normal from ripple gradient
    let viewDir = normalize(uv - 0.5);
    let normal = normalize(vec2<f32>(totalRipple * 10.0, 0.01));
    let cosTheta = max(dot(viewDir, normal), 0.0);
    let F0 = 0.7; // High metallic F0
    let reflectivity = fresnel(cosTheta, F0);

    // ═══ Prismatic dispersion through liquid metal surface ═══
    // The ripple center becomes the dynamic lens center
    let lensCenter = vec2<f32>(
        0.5 + sin(time * 0.3) * 0.1 + totalRipple * 0.5,
        0.5 + cos(time * 0.2) * 0.1 + totalRipple * 0.5
    );

    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
    var finalColor = vec3<f32>(0.0);
    var spectralResponse = vec4<f32>(0.0);

    for (var i: i32 = 0; i < 4; i = i + 1) {
        let ior = cauchyIOR(WAVELENGTHS[i], 1.5, 0.04);
        // Ripple curvature modulates refraction strength per band
        let dynamicCurvature = glassCurvature * (1.0 + totalRipple * 5.0);
        let refractedUV = refractThroughSurface(warpedUV, lensCenter, ior, dynamicCurvature);
        let wrappedUV = fract(refractedUV);
        let sample = textureSampleLevel(readTexture, u_sampler, wrappedUV, 0.0);

        // Beer-Lambert absorption based on ripple depth
        let absorption = exp(-(1.0 + abs(totalRipple) * 10.0) * (4.0 - f32(i)) * 0.12);
        let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[i])) * absorption;

        spectralResponse[i] = bandIntensity;
        finalColor += wavelengthToRGB(WAVELENGTHS[i]) * bandIntensity * spectralSat;
    }

    // Add chromatic aberration glow from ripple edges
    let glowRadius = glassCurvature * 0.015 * (1.0 + abs(totalRipple) * 10.0);
    var glowColor = vec3<f32>(0.0);
    let glowSamples = 8;
    for (var j: i32 = 0; j < glowSamples; j = j + 1) {
        let angle = f32(j) * 0.785398 + time * 0.5;
        let offset = vec2<f32>(cos(angle), sin(angle)) * glowRadius;
        let gSample = textureSampleLevel(readTexture, u_sampler, fract(warpedUV + offset), 0.0);
        glowColor += gSample.rgb;
    }
    glowColor /= f32(glowSamples);
    finalColor += glowColor * 0.1 * glassCurvature;

    // Metallic reflection tint mixed with spectral result
    let metalTint = vec3<f32>(0.85, 0.88, 0.92);
    let metalColor = mix(finalColor, metalTint, reflectivity * 0.4);

    // Tone map
    let tonemapped = metalColor / (1.0 + metalColor * 0.25);

    // Alpha from displacement intensity
    let displacement = length(warpedUV - uv);
    let alpha = mix(0.5, 1.0, smoothstep(0.0, 0.1, displacement) * 1.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(tonemapped, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), spectralResponse);
}
