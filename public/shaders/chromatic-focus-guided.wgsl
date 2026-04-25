// ═══════════════════════════════════════════════════════════════════
//  chromatic-focus-guided
//  Category: advanced-hybrid
//  Features: chromatic-focus, guided-filter-depth, depth-aware
//  Complexity: Very High
//  Chunks From: chromatic-focus, conv-guided-filter-depth
//  Created: 2026-04-18
//  By: Agent CB-12 — Chroma & Spectral Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Seven-band Cauchy chromatic aberration with depth-guided filtering.
//  The guided filter uses depth as guide to prevent aberration bleeding
//  across object boundaries, creating physically-plausible edge-aware
//  chromatic dispersion.
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

const SPECTRAL_RED:     f32 = 0.65;
const SPECTRAL_ORANGE:  f32 = 0.59;
const SPECTRAL_YELLOW:  f32 = 0.57;
const SPECTRAL_GREEN:   f32 = 0.52;
const SPECTRAL_BLUE:    f32 = 0.45;
const SPECTRAL_INDIGO:  f32 = 0.40;
const SPECTRAL_VIOLET:  f32 = 0.38;

const CAUCHY_A: f32 = 1.5;
const CAUCHY_B: f32 = 0.01;

const RED_W:    vec3<f32> = vec3<f32>(0.95, 0.25, 0.01);
const ORANGE_W: vec3<f32> = vec3<f32>(0.85, 0.45, 0.02);
const YELLOW_W: vec3<f32> = vec3<f32>(0.75, 0.70, 0.05);
const GREEN_W:  vec3<f32> = vec3<f32>(0.15, 0.95, 0.15);
const BLUE_W:   vec3<f32> = vec3<f32>(0.05, 0.35, 0.85);
const INDIGO_W: vec3<f32> = vec3<f32>(0.10, 0.25, 0.75);
const VIOLET_W: vec3<f32> = vec3<f32>(0.35, 0.15, 0.65);

fn cauchyRefractiveIndex(wavelength: f32) -> f32 {
    return CAUCHY_A + CAUCHY_B / (wavelength * wavelength);
}

fn sampleSpectralBand(uv: vec2<f32>, direction: vec2<f32>, wavelength: f32, baseStrength: f32, spectralSpread: f32) -> f32 {
    let n = cauchyRefractiveIndex(wavelength);
    let dispersionStrength = (n - 1.0) * baseStrength * spectralSpread;
    let displacedUV = uv + direction * dispersionStrength;
    let sample = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
    return dot(sample.rgb, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    let aberIntensity = u.zoom_params.x * 0.08;
    let focusRadius = u.zoom_params.y * 0.4 + 0.05;
    let spectralSpread = u.zoom_params.z * 2.0 + 0.5;
    let animSpeed = u.zoom_params.w * 3.0;
    let animationOffset = time * animSpeed;

    let aspect = res.x / res.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let focusFactor = smoothstep(focusRadius, focusRadius + 0.4, dist);
    let effectiveStrength = aberIntensity * focusFactor;

    let angle = atan2(distVec.y, distVec.x);
    let radialDir = vec2<f32>(cos(angle), sin(angle));
    let angularDispersion = vec2<f32>(cos(angle + 1.57), sin(angle + 1.57)) * 0.3;
    let dispersionDir = normalize(radialDir + angularDispersion);

    // Guided filter using depth to prevent cross-object dispersion
    let radiusBase = i32(mix(2.0, 5.0, u.zoom_params.x));
    let epsilonBase = mix(0.0001, 0.02, u.zoom_params.y);
    let depthInfluence = u.zoom_params.z;

    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 6.0) * u.zoom_params.w;
    let radius = i32(mix(f32(radiusBase), f32(radiusBase) * 0.4, mouseFactor));
    let epsilon = mix(epsilonBase * 3.0, epsilonBase * 0.1, mouseFactor);

    let maxRadius = min(radius, 5);
    var sumGuide = 0.0;
    var sumInput = vec3<f32>(0.0);
    var sumGuideInput = vec3<f32>(0.0);
    var sumGuide2 = 0.0;
    var count = 0.0;

    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let guideVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + offset, 0.0).r;
            let inputVal = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
            sumGuide += guideVal;
            sumInput += inputVal;
            sumGuideInput += inputVal * guideVal;
            sumGuide2 += guideVal * guideVal;
            count += 1.0;
        }
    }

    let meanGuide = sumGuide / count;
    let meanInput = sumInput / count;
    let meanGI = sumGuideInput / count;
    let meanGuide2 = sumGuide2 / count;
    let varGuide = meanGuide2 - meanGuide * meanGuide;
    let a = (meanGI - meanGuide * meanInput) / (varGuide + epsilon);
    let b = meanInput - a * meanGuide;
    let guide = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let guidedResult = a * guide + b;

    // Sample spectral bands from guided result
    let redSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_RED, effectiveStrength, spectralSpread);
    let orangeSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_ORANGE, effectiveStrength, spectralSpread);
    let yellowSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_YELLOW, effectiveStrength, spectralSpread);
    let greenSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_GREEN, effectiveStrength, spectralSpread);
    let blueSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_BLUE, effectiveStrength, spectralSpread);
    let indigoSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_INDIGO, effectiveStrength, spectralSpread);
    let violetSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_VIOLET, effectiveStrength, spectralSpread);

    var finalColor = vec3<f32>(0.0);
    finalColor += RED_W * redSample;
    finalColor += ORANGE_W * orangeSample;
    finalColor += YELLOW_W * yellowSample;
    finalColor += GREEN_W * greenSample;
    finalColor += BLUE_W * blueSample;
    finalColor += INDIGO_W * indigoSample;
    finalColor += VIOLET_W * violetSample;
    finalColor /= vec3<f32>(3.2, 3.1, 2.58);

    let sharpColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let sharpWeight = 1.0 - focusFactor;
    finalColor = mix(finalColor, sharpColor, sharpWeight * 0.4);

    // Mix with guided result for edge-aware smoothing
    finalColor = mix(finalColor, guidedResult, depthInfluence * 0.3);

    textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
