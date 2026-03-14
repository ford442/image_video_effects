// ═══════════════════════════════════════════════════════════════════════════════
//  Chromatic Focus - Cauchy Dispersion Edition
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
// ═══════════════════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=AberrationIntensity, y=FocusPoint, z=SpectralSpread, w=AnimationSpeed
  ripples: array<vec4<f32>, 50>,
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Spectral Constants - ROYGBIV wavelengths in micrometers (for Cauchy equation)
// ═══════════════════════════════════════════════════════════════════════════════
const SPECTRAL_RED:     f32 = 0.65;   // 650nm - longest wavelength, least refraction
const SPECTRAL_ORANGE:  f32 = 0.59;   // 590nm
const SPECTRAL_YELLOW:  f32 = 0.57;   // 570nm
const SPECTRAL_GREEN:   f32 = 0.52;   // 520nm
const SPECTRAL_BLUE:    f32 = 0.45;   // 450nm
const SPECTRAL_INDIGO:  f32 = 0.40;   // 400nm
const SPECTRAL_VIOLET:  f32 = 0.38;   // 380nm - shortest wavelength, most refraction

// Cauchy coefficients (simplified glass model)
const CAUCHY_A: f32 = 1.5;    // Base refractive index
const CAUCHY_B: f32 = 0.01;   // Dispersion coefficient

// ═══════════════════════════════════════════════════════════════════════════════
//  CIE RGB Color Matching Functions weights for spectral synthesis
//  Approximate conversion from spectral samples to RGB
// ═══════════════════════════════════════════════════════════════════════════════
const RED_WEIGHTS:    vec3<f32> = vec3<f32>(0.95, 0.25, 0.01);    // Red band contribution
const ORANGE_WEIGHTS: vec3<f32> = vec3<f32>(0.85, 0.45, 0.02);    // Orange band
const YELLOW_WEIGHTS: vec3<f32> = vec3<f32>(0.75, 0.70, 0.05);    // Yellow band
const GREEN_WEIGHTS:  vec3<f32> = vec3<f32>(0.15, 0.95, 0.15);    // Green band
const BLUE_WEIGHTS:   vec3<f32> = vec3<f32>(0.05, 0.35, 0.85);    // Blue band
const INDIGO_WEIGHTS: vec3<f32> = vec3<f32>(0.10, 0.25, 0.75);    // Indigo band
const VIOLET_WEIGHTS: vec3<f32> = vec3<f32>(0.35, 0.15, 0.65);    // Violet band

// ═══════════════════════════════════════════════════════════════════════════════
//  Cauchy Dispersion Equation: n(λ) = A + B/λ²
//  Returns refractive index for a given wavelength (in micrometers)
// ═══════════════════════════════════════════════════════════════════════════════
fn cauchyRefractiveIndex(wavelength: f32) -> f32 {
    return CAUCHY_A + CAUCHY_B / (wavelength * wavelength);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Gaussian weight for smooth spectral transition
//  Creates continuous spectrum feel from discrete samples
// ═══════════════════════════════════════════════════════════════════════════════
fn gaussianWeight(x: f32, center: f32, sigma: f32) -> f32 {
    let diff = x - center;
    return exp(-(diff * diff) / (2.0 * sigma * sigma));
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Sample texture with wavelength-dependent displacement
//  Uses Snell's law approximation: displacement ∝ (n(λ) - 1)
// ═══════════════════════════════════════════════════════════════════════════════
fn sampleSpectralBand(
    uv: vec2<f32>,
    direction: vec2<f32>,
    wavelength: f32,
    baseStrength: f32,
    spectralSpread: f32,
    animationOffset: f32
) -> f32 {
    // Calculate refractive index using Cauchy's equation
    let n = cauchyRefractiveIndex(wavelength);
    
    // Displacement strength proportional to how much the index differs from air (n≈1)
    // Shorter wavelengths (blue/violet) have higher n, thus more displacement
    let dispersionStrength = (n - 1.0) * baseStrength * spectralSpread;
    
    // Apply animated wavelength sweep
    let animatedWavelength = wavelength + animationOffset * 0.05;
    let sweepFactor = sin(animatedWavelength * 10.0 + animationOffset * 2.0) * 0.1;
    
    // Calculate displaced UV
    let displacedUV = uv + direction * (dispersionStrength + sweepFactor * baseStrength * 0.5);
    
    // Sample luminance (grayscale for spectral processing)
    let sample = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
    return dot(sample.rgb, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;

    // ═══════════════════════════════════════════════════════════════════════════
    //  Parameters (zoom_params)
    //  x: Aberration intensity (0.0 - 1.0)
    //  y: Focus point / radius (0.0 - 1.0)
    //  z: Spectral spread (0.0 - 2.0)
    //  w: Animation speed (0.0 - 1.0)
    // ═══════════════════════════════════════════════════════════════════════════
    let aberIntensity = u.zoom_params.x * 0.08;           // Max displacement amount
    let focusRadius = u.zoom_params.y * 0.4 + 0.05;       // Clear focus region radius
    let spectralSpread = u.zoom_params.z * 2.0 + 0.5;     // How much colors separate
    let animSpeed = u.zoom_params.w * 3.0;                // Animation speed
    
    // Time-based animation
    let currentTime = u.config.x;
    let animationOffset = currentTime * animSpeed;

    // ═══════════════════════════════════════════════════════════════════════════
    //  Focus Point Calculation
    //  Uses mouse position as focus center (where image is sharp)
    // ═══════════════════════════════════════════════════════════════════════════
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    
    // Distance-based aberration: sharp at focus, chromatic at edges
    let focusFactor = smoothstep(focusRadius, focusRadius + 0.4, dist);
    let effectiveStrength = aberIntensity * focusFactor;

    // Direction from focus point (radial dispersion)
    let angle = atan2(distVec.y, distVec.x);
    let radialDir = vec2<f32>(cos(angle), sin(angle));
    
    // Add some angular dispersion for prism-like effect
    let angularDispersion = vec2<f32>(cos(angle + 1.57), sin(angle + 1.57)) * 0.3;
    let dispersionDir = normalize(radialDir + angularDispersion);

    // ═══════════════════════════════════════════════════════════════════════════
    //  Spectral Sampling - Sample all 7 ROYGBIV bands
    //  Each wavelength refracts by a different amount per Cauchy's equation
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Sample each spectral band with wavelength-appropriate displacement
    let redSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_RED, effectiveStrength, spectralSpread, animationOffset);
    let orangeSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_ORANGE, effectiveStrength, spectralSpread, animationOffset);
    let yellowSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_YELLOW, effectiveStrength, spectralSpread, animationOffset);
    let greenSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_GREEN, effectiveStrength, spectralSpread, animationOffset);
    let blueSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_BLUE, effectiveStrength, spectralSpread, animationOffset);
    let indigoSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_INDIGO, effectiveStrength, spectralSpread, animationOffset);
    let violetSample = sampleSpectralBand(uv, dispersionDir, SPECTRAL_VIOLET, effectiveStrength, spectralSpread, animationOffset);

    // ═══════════════════════════════════════════════════════════════════════════
    //  Spectral Synthesis - Combine bands into RGB using CIE weights
    //  This approximates the continuous spectrum from discrete samples
    // ═══════════════════════════════════════════════════════════════════════════
    var finalColor = vec3<f32>(0.0);
    
    // Weight and accumulate each spectral band
    finalColor += RED_WEIGHTS * redSample;
    finalColor += ORANGE_WEIGHTS * orangeSample;
    finalColor += YELLOW_WEIGHTS * yellowSample;
    finalColor += GREEN_WEIGHTS * greenSample;
    finalColor += BLUE_WEIGHTS * blueSample;
    finalColor += INDIGO_WEIGHTS * indigoSample;
    finalColor += VIOLET_WEIGHTS * violetSample;
    
    // Normalize by total weight
    finalColor /= vec3<f32>(3.2, 3.1, 2.58);

    // ═══════════════════════════════════════════════════════════════════════════
    //  Prism Highlight Effect
    //  Add subtle glow at high-dispersion regions for glass-like appearance
    // ═══════════════════════════════════════════════════════════════════════════
    let dispersionAmount = effectiveStrength * spectralSpread;
    let prismGlow = dispersionAmount * 0.3 * (redSample + violetSample);
    finalColor += vec3<f32>(prismGlow * 0.5, prismGlow * 0.3, prismGlow * 0.7);

    // ═══════════════════════════════════════════════════════════════════════════
    //  Sharp Center Blend
    //  Blend with original sharp image near focus point for depth effect
    // ═══════════════════════════════════════════════════════════════════════════
    let sharpColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let sharpWeight = 1.0 - focusFactor;
    finalColor = mix(finalColor, sharpColor, sharpWeight * 0.4);

    // ═══════════════════════════════════════════════════════════════════════════
    //  Output with gamma correction
    // ═══════════════════════════════════════════════════════════════════════════
    finalColor = pow(finalColor, vec3<f32>(1.0 / 1.1)); // Slight gamma adjustment
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
