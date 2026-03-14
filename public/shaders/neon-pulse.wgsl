// ═══════════════════════════════════════════════════════════════
//  Neon Pulse - Blackbody Radiation Edition with Alpha Emission
//  Category: lighting-effects
//  Physics: Planck's Law of Blackbody Radiation + Alpha Emission
//  Temperature range: 1000K (red) to 10000K (blue-white)
//  Alpha: Physical occlusion (tube=0.3, glow=0.0, additive emission)
// ═══════════════════════════════════════════════════════════════

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

// Simple pseudo-random noise function
fn hash(p: vec2<f32>) -> f32 {
    let n = sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453;
    return fract(n);
}

// 1D noise for flicker
fn noise1d(t: f32) -> f32 {
    let i = floor(t);
    let f = fract(t);
    let a = hash(vec2<f32>(i, 0.0));
    let b = hash(vec2<f32>(i + 1.0, 0.0));
    return mix(a, b, f * f * (3.0 - 2.0 * f));
}

// Blackbody radiation color approximation
// Input: temperature T in Kelvin (1000-10000K range)
// Output: RGB color based on Planck's law
fn blackbodyColor(T: f32) -> vec3<f32> {
    var color: vec3<f32>;
    
    // Normalize to 0-1 range for internal calculations
    let t = clamp((T - 1000.0) / 9000.0, 0.0, 1.0);
    
    if (T < 4000.0) {
        // Cool temperatures: deep red to orange
        let localT = (T - 1000.0) / 3000.0;
        color.r = 1.0;
        color.g = localT * 0.8;
        color.b = 0.0;
    } else if (T < 7000.0) {
        // Medium temperatures: orange to yellow to white-ish
        let localT = (T - 4000.0) / 3000.0;
        color.r = 1.0 - localT * 0.5;
        color.g = 0.8 + localT * 0.2;
        color.b = localT * 0.5;
    } else {
        // Hot temperatures: white to blue-white
        let localT = (T - 7000.0) / 3000.0;
        let whiteLevel = 0.5 + localT * 0.5;
        color.r = whiteLevel * (1.0 - localT * 0.3);
        color.g = whiteLevel;
        color.b = whiteLevel + localT * 0.3;
    }
    
    // Apply intensity curve (Stefan-Boltzmann ~ T^4)
    let intensity = pow(T / 5000.0, 2.0) * 0.5 + 0.5;
    color = color * intensity;
    
    return clamp(color, vec3<f32>(0.0), vec3<f32>(2.0));
}

// Temperature to wavelength (Wien's displacement law approximation)
fn peakWavelength(T: f32) -> f32 {
    return 2898000.0 / T;
}

// Inverse square law for light falloff
fn inverseSquareFalloff(dist: f32, maxDist: f32) -> f32 {
    let d = max(dist, 0.001);
    return 1.0 / (1.0 + d * d * 10.0) * (1.0 - smoothstep(maxDist * 0.5, maxDist, dist));
}

// Alpha calculation for emissive materials
// Core tube: alpha ~ 0.3 (partial occlusion)
// Glow halo: alpha ~ 0.0 (transparent, additive)
fn calculateEmissiveAlpha(glowIntensity: f32, occlusionBalance: f32) -> f32 {
    let coreAlpha = 0.3 * glowIntensity;
    let glowAlpha = 0.0;
    return mix(glowAlpha, coreAlpha, saturate(glowIntensity) * occlusionBalance);
}

fn saturate(v: f32) -> f32 {
    return clamp(v, 0.0, 1.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters from zoom_params
    // x: Base temperature (mapped 0-1 -> 1000-10000K)
    // y: Temperature gradient strength
    // z: Flicker intensity
    // w: Occlusion balance (controls alpha: 0=transparent glow, 1=visible tube)
    let baseTempNorm = u.zoom_params.x;
    let tempGradient = u.zoom_params.y;
    let flickerIntensity = u.zoom_params.z;
    let occlusionBalance = u.zoom_params.w;
    let striaFreq = 10.0 + 1.0;
    
    // Map normalized parameter to temperature range (1000K - 10000K)
    let baseTemp = 1000.0 + baseTempNorm * 9000.0;
    
    // Mouse position for interaction center
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    
    // Aspect-corrected coordinates
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);
    
    // Calculate pulse direction (radial from mouse)
    let angle = atan2(uv.y - mouse.y, uv.x - mouse.x);
    
    // Gas discharge striations - periodic intensity bands
    let striaPhase = dist * striaFreq * 20.0 - time * 2.0;
    let stria = sin(striaPhase) * 0.5 + 0.5;
    let striaModulation = 1.0 + stria * 0.3;
    
    // Flicker - rapid random fluctuations in gas discharge
    let flicker = noise1d(time * 15.0) * flickerIntensity;
    let flickerModulation = 1.0 + flicker * 0.5;
    
    // Temperature gradient along pulse direction
    let tempVariation = sin(dist * 10.0 - time * 3.0) * tempGradient * 2000.0;
    let gradientOffset = (uv.x - 0.5) * tempGradient * 3000.0;
    
    // Local temperature at this pixel
    let localTemp = baseTemp + tempVariation + gradientOffset;
    let clampedTemp = clamp(localTemp, 1000.0, 10000.0);
    
    // Get blackbody color for this temperature
    let bbColor = blackbodyColor(clampedTemp);
    
    // Wien's displacement visualization
    let peakWL = peakWavelength(clampedTemp);
    let wlFactor = clamp(peakWL / 1000.0, 0.0, 1.0);
    
    // Edge detection for neon glow effect
    let pixelSize = 1.0 / resolution;
    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let l = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).rgb;
    let t = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).rgb;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).rgb;
    
    let edgeX = length(l - r);
    let edgeY = length(t - b);
    let edge = sqrt(edgeX * edgeX + edgeY * edgeY);
    
    // Pulse dynamics with physics-based timing
    let pulseSpeed = 2.0;
    let pulsePhase = time * pulseSpeed - dist * 15.0;
    let pulse = sin(pulsePhase) * 0.5 + 0.5;
    
    // Effect radius with modulation
    let effectRadius = 0.3 + pulse * 0.1;
    let falloff = smoothstep(effectRadius, 0.0, dist);
    
    // Thermal bloom - gas expands when hot
    let thermalExpansion = 1.0 + (clampedTemp - 5000.0) / 10000.0 * 0.2;
    
    // Composite the neon glow with emission physics
    // Base glow from edges (ionized gas emission)
    let glowStrength = edge * 3.0 * falloff * striaModulation * flickerModulation;
    var emission = bbColor * glowStrength;
    
    // Add pulse ring - the traveling ionization front
    let ringWidth = 0.02 * thermalExpansion;
    let ringDist = abs(dist - effectRadius * 0.8);
    let ring = smoothstep(ringWidth, 0.0, ringDist) * pulse;
    emission = emission + bbColor * ring * 2.0 * flickerModulation;
    
    // Gas tube core - brighter center line
    let coreWidth = 0.005 * thermalExpansion;
    let coreDist = abs(dist - effectRadius * 0.5);
    let core = smoothstep(coreWidth, 0.0, coreDist) * 0.5;
    emission = emission + bbColor * core * striaModulation;
    
    // Calculate alpha based on emission intensity and occlusion balance
    // High emission = more visible tube structure
    let totalGlowIntensity = length(emission);
    let finalAlpha = calculateEmissiveAlpha(totalGlowIntensity, occlusionBalance);
    
    // Apply inverse square falloff for physical light attenuation
    let lightFalloff = inverseSquareFalloff(dist, effectRadius * 1.5);
    emission = emission * lightFalloff;
    
    // Slight vignette based on temperature (hotter = more bloom)
    let bloomRadius = 1.0 + (clampedTemp / 10000.0) * 0.5;
    let vignette = smoothstep(bloomRadius, 0.3, dist);
    emission = emission * vignette;
    
    // Output RGBA: RGB = emitted light (HDR, can exceed 1.0), A = physical occlusion
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(emission, finalAlpha));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
