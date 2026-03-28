// ═══════════════════════════════════════════════════════════════════════════════
//  Chromatic Focus - Cauchy Dispersion Edition with Wavelength-Dependent Alpha
//  Scientific Implementation: Wavelength-dependent refraction via Cauchy's Equation
//  
//  Cauchy's Equation: n(λ) = A + B/λ² + C/λ⁴
//  Simplified: n(λ) = 1.5 + 0.01/λ² (λ in micrometers)
//  
//  Spectral bands: ROYGBIV (7 wavelengths)
//  - Red:    650nm (0.65 μm)  - lowest refraction
//  - Orange: 590nm (0.59 μm)
//  - Yellow: 570nm (0.57 μm)
//  - Green:  520nm (0.52 μm)
//  - Blue:   450nm (0.45 μm)
//  - Indigo: 400nm (0.40 μm)
//  - Violet: 380nm (0.38 μm)  - highest refraction
//
//  ALPHA MODEL:
//  - Beer-Lambert law: alpha = exp(-thickness * absorption)
//  - Absorption varies by wavelength
//  ═══════════════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════════════
//  Spectral Constants - ROYGBIV wavelengths in micrometers (for Cauchy equation)
// ═══════════════════════════════════════════════════════════════════════════════
const SPECTRAL_RED:     f32 = 0.65;
const SPECTRAL_ORANGE:  f32 = 0.59;
const SPECTRAL_YELLOW:  f32 = 0.57;
const SPECTRAL_GREEN:   f32 = 0.52;
const SPECTRAL_BLUE:    f32 = 0.45;
const SPECTRAL_INDIGO:  f32 = 0.40;
const SPECTRAL_VIOLET:  f32 = 0.38;

// Cauchy coefficients
const CAUCHY_A: f32 = 1.5;
const CAUCHY_B: f32 = 0.01;

// ═══════════════════════════════════════════════════════════════════════════════
//  CIE RGB Color Matching Functions weights for spectral synthesis
// ═══════════════════════════════════════════════════════════════════════════════
const RED_WEIGHTS:    vec3<f32> = vec3<f32>(0.95, 0.25, 0.01);
const ORANGE_WEIGHTS: vec3<f32> = vec3<f32>(0.85, 0.45, 0.02);
const YELLOW_WEIGHTS: vec3<f32> = vec3<f32>(0.75, 0.70, 0.05);
const GREEN_WEIGHTS:  vec3<f32> = vec3<f32>(0.15, 0.95, 0.15);
const BLUE_WEIGHTS:   vec3<f32> = vec3<f32>(0.05, 0.35, 0.85);
const INDIGO_WEIGHTS: vec3<f32> = vec3<f32>(0.10, 0.25, 0.75);
const VIOLET_WEIGHTS: vec3<f32> = vec3<f32>(0.35, 0.15, 0.65);

// ═══════════════════════════════════════════════════════════════════════════════
//  WAVELENGTH-DEPENDENT ALPHA CONSTANTS (nm)
// ═══════════════════════════════════════════════════════════════════════════════
const WAVELENGTH_RED_NM:    f32 = 650.0;
const WAVELENGTH_GREEN_NM:  f32 = 550.0;
const WAVELENGTH_BLUE_NM:   f32 = 450.0;

// ═══════════════════════════════════════════════════════════════════════════════
//  Cauchy Dispersion Equation: n(λ) = A + B/λ²
// ═══════════════════════════════════════════════════════════════════════════════
fn cauchyRefractiveIndex(wavelength: f32) -> f32 {
    return CAUCHY_A + CAUCHY_B / (wavelength * wavelength);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  WAVELENGTH-DEPENDENT ALPHA
// ═══════════════════════════════════════════════════════════════════════════════
fn calculateChannelAlpha(thickness: f32, wavelength: f32) -> f32 {
    let lambda_norm = (800.0 - wavelength) / 400.0;
    let absorption = mix(0.3, 1.0, lambda_norm);
    return exp(-thickness * absorption);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Sample texture with wavelength-dependent displacement
// ═══════════════════════════════════════════════════════════════════════════════
fn sampleSpectralBand(
    uv: vec2<f32>,
    direction: vec2<f32>,
    wavelength: f32,
    baseStrength: f32,
    spectralSpread: f32,
    animationOffset: f32
) -> f32 {
    let n = cauchyRefractiveIndex(wavelength);
    let dispersionStrength = (n - 1.0) * baseStrength * spectralSpread;
    
    let animatedWavelength = wavelength + animationOffset * 0.05;
    let sweepFactor = sin(animatedWavelength * 10.0 + animationOffset * 2.0) * 0.1;
    
    let displacedUV = uv + direction * (dispersionStrength + sweepFactor * baseStrength * 0.5);
    
    let sample = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
    return dot(sample.rgb, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;

    let aberIntensity = u.zoom_params.x * 0.08;
    let focusRadius = u.zoom_params.y * 0.4 + 0.05;
    let spectralSpread = u.zoom_params.z * 2.0 + 0.5;
    let animSpeed = u.zoom_params.w * 3.0;
    
    let currentTime = u.config.x;
    let animationOffset = currentTime * animSpeed;

    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    
    let focusFactor = smoothstep(focusRadius, focusRadius + 0.4, dist);
    let effectiveStrength = aberIntensity * focusFactor;

    let angle = atan2(distVec.y, distVec.x);
    let radialDir = vec2<f32>(cos(angle), sin(angle));
    
    let angularDispersion = vec2<f32>(cos(angle + 1.57), sin(angle + 1.57)) * 0.3;
    let dispersionDir = normalize(radialDir + angularDispersion);

    // Sample each spectral band
    let redSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_RED, effectiveStrength, spectralSpread, animationOffset);
    let orangeSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_ORANGE, effectiveStrength, spectralSpread, animationOffset);
    let yellowSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_YELLOW, effectiveStrength, spectralSpread, animationOffset);
    let greenSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_GREEN, effectiveStrength, spectralSpread, animationOffset);
    let blueSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_BLUE, effectiveStrength, spectralSpread, animationOffset);
    let indigoSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_INDIGO, effectiveStrength, spectralSpread, animationOffset);
    let violetSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_VIOLET, effectiveStrength, spectralSpread, animationOffset);

    // Spectral Synthesis
    var finalColor = vec3<f32>(0.0);
    
    finalColor += RED_WEIGHTS * redSample;
    finalColor += ORANGE_WEIGHTS * orangeSample;
    finalColor += YELLOW_WEIGHTS * yellowSample;
    finalColor += GREEN_WEIGHTS * greenSample;
    finalColor += BLUE_WEIGHTS * blueSample;
    finalColor += INDIGO_WEIGHTS * indigoSample;
    finalColor += VIOLET_WEIGHTS * violetSample;
    
    finalColor /= vec3<f32>(3.2, 3.1, 2.58);

    // Prism Highlight Effect
    let dispersionAmount = effectiveStrength * spectralSpread;
    let prismGlow = dispersionAmount * 0.3 * (redSample + violetSample);
    finalColor += vec3<f32>(prismGlow * 0.5, prismGlow * 0.3, prismGlow * 0.7);

    // Sharp Center Blend
    let sharpColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let sharpWeight = 1.0 - focusFactor;
    finalColor = mix(finalColor, sharpColor, sharpWeight * 0.4);

    // ═══════════════════════════════════════════════════════════════════════════════
    //  WAVELENGTH-DEPENDENT ALPHA
    //  Thickness derived from dispersion amount
    // ═══════════════════════════════════════════════════════════════════════════════
    let dispersionThickness = dispersionAmount * 10.0 + focusFactor * 2.0;
    
    let alphaR = calculateChannelAlpha(dispersionThickness, WAVELENGTH_RED_NM);
    let alphaG = calculateChannelAlpha(dispersionThickness, WAVELENGTH_GREEN_NM);
    let alphaB = calculateChannelAlpha(dispersionThickness, WAVELENGTH_BLUE_NM);
    
    let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
    let finalAlpha = dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights);
    
    let alphaModulatedColor = vec3<f32>(
        finalColor.r * alphaR,
        finalColor.g * alphaG,
        finalColor.b * alphaB
    );

    // Output with gamma correction
    let gammaCorrected = pow(alphaModulatedColor, vec3<f32>(1.0 / 1.1));
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(gammaCorrected, finalAlpha));
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
