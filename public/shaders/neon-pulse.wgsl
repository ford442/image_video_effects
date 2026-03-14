// ═══════════════════════════════════════════════════════════════
//  Neon Pulse - Blackbody Radiation Edition
//  Category: lighting-effects
//  Physics: Planck's Law of Blackbody Radiation
//  Temperature range: 1000K (red) to 10000K (blue-white)
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
        // Red stays at 1.0, green increases, blue stays 0
        let localT = (T - 1000.0) / 3000.0;
        color.r = 1.0;
        color.g = localT * 0.8;
        color.b = 0.0;
    } else if (T < 7000.0) {
        // Medium temperatures: orange to yellow to white-ish
        // Red decreases slightly, green increases, blue starts rising
        let localT = (T - 4000.0) / 3000.0;
        color.r = 1.0 - localT * 0.5;
        color.g = 0.8 + localT * 0.2;
        color.b = localT * 0.5;
    } else {
        // Hot temperatures: white to blue-white
        // All channels rise toward white, then blue dominates
        let localT = (T - 7000.0) / 3000.0;
        let whiteLevel = 0.5 + localT * 0.5;
        color.r = whiteLevel * (1.0 - localT * 0.3);
        color.g = whiteLevel;
        color.b = whiteLevel + localT * 0.3;
    }
    
    // Apply intensity curve (Stefan-Boltzmann ~ T^4)
    // Normalize for visual display
    let intensity = pow(T / 5000.0, 2.0) * 0.5 + 0.5;
    color = color * intensity;
    
    return clamp(color, vec3<f32>(0.0), vec3<f32>(2.0));
}

// Temperature to wavelength (Wien's displacement law approximation)
// Peak wavelength in nanometers
fn peakWavelength(T: f32) -> f32 {
    // Wien's displacement constant: b ≈ 2.898 × 10^6 nm·K
    return 2898000.0 / T;
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
    // w: Stria frequency
    let baseTempNorm = u.zoom_params.x;
    let tempGradient = u.zoom_params.y;
    let flickerIntensity = u.zoom_params.z;
    let striaFreq = u.zoom_params.w * 10.0 + 1.0;
    
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
    // Simulates the standing wave patterns in neon tubes
    let striaPhase = dist * striaFreq * 20.0 - time * 2.0;
    let stria = sin(striaPhase) * 0.5 + 0.5;
    let striaModulation = 1.0 + stria * 0.3;
    
    // Flicker - rapid random fluctuations in gas discharge
    let flicker = noise1d(time * 15.0) * flickerIntensity;
    let flickerModulation = 1.0 + flicker * 0.5;
    
    // Temperature gradient along pulse direction
    // Hotter at center, cooler at edges, or vice versa based on gradient param
    let tempVariation = sin(dist * 10.0 - time * 3.0) * tempGradient * 2000.0;
    let gradientOffset = (uv.x - 0.5) * tempGradient * 3000.0;
    
    // Local temperature at this pixel
    let localTemp = baseTemp + tempVariation + gradientOffset;
    let clampedTemp = clamp(localTemp, 1000.0, 10000.0);
    
    // Get blackbody color for this temperature
    let bbColor = blackbodyColor(clampedTemp);
    
    // Wien's displacement visualization (optional subtle effect)
    let peakWL = peakWavelength(clampedTemp);
    let wlFactor = clamp(peakWL / 1000.0, 0.0, 1.0); // Normalize
    
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
    
    // Composite the neon glow
    // Base glow from edges (ionized gas emission)
    let glowStrength = edge * 3.0 * falloff * striaModulation * flickerModulation;
    var glow = bbColor * glowStrength;
    
    // Add pulse ring - the traveling ionization front
    let ringWidth = 0.02 * thermalExpansion;
    let ringDist = abs(dist - effectRadius * 0.8);
    let ring = smoothstep(ringWidth, 0.0, ringDist) * pulse;
    glow = glow + bbColor * ring * 2.0 * flickerModulation;
    
    // Gas tube core - brighter center line
    let coreWidth = 0.005 * thermalExpansion;
    let coreDist = abs(dist - effectRadius * 0.5);
    let core = smoothstep(coreWidth, 0.0, coreDist) * 0.5;
    glow = glow + bbColor * core * striaModulation;
    
    // Final color composition
    let finalColor = c + glow;
    
    // Slight vignette based on temperature (hotter = more bloom)
    let bloomRadius = 1.0 + (clampedTemp / 10000.0) * 0.5;
    let vignette = smoothstep(bloomRadius, 0.3, dist);
    let finalWithVignette = finalColor * vignette;
    
    // Output to writeTexture
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalWithVignette, 1.0));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
