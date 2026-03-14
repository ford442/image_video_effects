// ═══════════════════════════════════════════════════════════════
//  Anamorphic Flare - Cinema-quality lens flare simulation
//  Category: lighting-effects
//  Features: hexagonal diffraction, spectral dispersion, ghost reflections
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

// Constants for lens flare physics
const PI: f32 = 3.14159265359;
const TWO_PI: f32 = 6.28318530718;

// Hexagon aperture function - returns 1.0 inside hexagon, 0.0 outside
fn hexagonAperture(uv: vec2<f32>, size: f32) -> f32 {
    // Convert to polar-like coordinates for hexagon
    let r = length(uv);
    let angle = atan2(uv.y, uv.x);
    
    // Hexagon has 6-fold symmetry
    // Normalize angle to 0-PI/3 sector
    let sectorAngle = fract(angle / (PI / 3.0)) * (PI / 3.0) - PI / 6.0;
    
    // Distance to hexagon edge in this sector
    let dist = r * cos(sectorAngle) / cos(PI / 6.0);
    
    return smoothstep(size + 0.01, size - 0.01, dist);
}

// Spectral dispersion - returns RGB offset based on wavelength
fn spectralDispersion(angle: f32, dispersion: f32) -> vec3<f32> {
    // Wavelength-dependent offsets
    // Red (~700nm) bends least, Violet (~400nm) bends most
    let redOffset = 1.0 - dispersion * 0.3;
    let greenOffset = 1.0;
    let blueOffset = 1.0 + dispersion * 0.5;
    
    return vec3<f32>(redOffset, greenOffset, blueOffset);
}

// Anamorphic streak calculation with spectral dispersion
fn anamorphicStreak(uv: vec2<f32>, lightPos: vec2<f32>, streakLength: f32, width: f32, dispersion: f32) -> vec3<f32> {
    let aspect = 1.0; // Assume square for calculation, adjust outside
    let toLight = uv - lightPos;
    let distX = abs(toLight.x);
    let distY = abs(toLight.y);
    
    // Horizontal streak (anamorphic characteristic)
    let hStreak = exp(-distX / streakLength) * exp(-distY * 50.0 / width);
    
    // Vertical component (much weaker)
    let vStreak = exp(-distY / (streakLength * 0.1)) * exp(-distX * 100.0 / width);
    
    // Combined streak
    let streak = hStreak * 0.9 + vStreak * 0.1;
    
    // Apply spectral dispersion to streak edges
    let edgeFactor = abs(distX / streakLength); // 0 at center, 1 at edges
    let dispersionColor = spectralDispersion(0.0, dispersion * edgeFactor);
    
    // Classic anamorphic blue tint with dispersion
    let baseTint = vec3<f32>(0.5, 0.7, 1.0);
    return streak * baseTint * dispersionColor;
}

// Ghost reflection element
fn ghostElement(uv: vec2<f32>, lightPos: vec2<f32>, offset: vec2<f32>, size: f32, intensity: f32) -> vec3<f32> {
    // Ghost appears opposite to light source relative to center
    let center = vec2<f32>(0.5, 0.5);
    let ghostPos = center + (center - lightPos) * offset * 2.0 + offset;
    
    let dist = length(uv - ghostPos);
    
    // Hexagonal aperture shape for bokeh
    let hexUV = (uv - ghostPos) / size;
    let hex = hexagonAperture(hexUV, 0.8);
    
    // Gaussian falloff
    let falloff = exp(-dist * dist * 8.0 / size);
    
    // Ghost color with slight tint variation
    let ghostTint = vec3<f32>(1.0, 0.95, 0.9); // Slightly warm
    
    return hex * falloff * intensity * ghostTint;
}

// Volumetric light rays (god rays simulation)
fn volumetricRays(uv: vec2<f32>, lightPos: vec2<f32>, intensity: f32) -> f32 {
    let toLight = lightPos - uv;
    let angle = atan2(toLight.y, toLight.x);
    let dist = length(toLight);
    
    // Ray pattern based on angle
    let rayPattern = pow(sin(angle * 12.0 + dist * 20.0), 4.0);
    let radialFalloff = 1.0 / (1.0 + dist * 3.0);
    
    return rayPattern * radialFalloff * intensity * 0.3;
}

// Central glow/halo
fn centralGlow(uv: vec2<f32>, lightPos: vec2<f32>, size: f32) -> vec3<f32> {
    let dist = length(uv - lightPos);
    
    // Core glow
    let core = exp(-dist * 15.0 / size);
    
    // Corona (wider, softer)
    let corona = exp(-dist * 5.0 / size) * 0.3;
    
    // Combined with slight blue tint
    let glowTint = vec3<f32>(0.8, 0.9, 1.0);
    
    return (core + corona) * glowTint;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let lightPos = u.zoom_config.yz;
    let time = u.config.x;
    
    // Parameters from zoom_params
    let flareIntensity = u.zoom_params.x * 3.0;      // x: Flare intensity
    let streakLength = u.zoom_params.y * 0.8 + 0.05;  // y: Streak length
    let dispersion = u.zoom_params.z * 2.0;           // z: Spectral dispersion
    let ghostCount = i32(u.zoom_params.w * 5.0 + 1.0); // w: Ghost count (1-6)
    
    // Sample base image
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    // Initialize flare accumulation
    var flareColor = vec3<f32>(0.0);
    
    // 1. Anamorphic streak with spectral dispersion
    let streak = anamorphicStreak(uv, lightPos, streakLength, 2.0, dispersion);
    flareColor += streak * flareIntensity;
    
    // 2. Hexagonal ghost reflections (aperture diffraction)
    for (var i: i32 = 0; i < ghostCount; i = i + 1) {
        let fi = f32(i);
        let ghostOffset = vec2<f32>(
            sin(fi * 1.3 + time * 0.1) * 0.15 + fi * 0.08,
            cos(fi * 0.7) * 0.1 + fi * 0.05
        );
        let ghostSize = 0.08 - fi * 0.01;
        let ghostIntensity = (0.4 - fi * 0.06) * flareIntensity;
        
        let ghost = ghostElement(uv, lightPos, ghostOffset, ghostSize, ghostIntensity);
        
        // Apply hexagonal diffraction pattern to each ghost
        let toGhost = uv - (vec2<f32>(0.5) + (vec2<f32>(0.5) - lightPos) * ghostOffset * 2.0);
        let hexPattern = hexagonAperture(toGhost / (ghostSize * 3.0), 0.5);
        
        // Spectral dispersion on ghost edges
        let ghostDist = length(toGhost);
        let ghostDispersion = spectralDispersion(ghostDist * 10.0, dispersion * 0.5);
        
        flareColor += ghost * hexPattern * ghostDispersion;
    }
    
    // 3. Central glow and bloom
    let glow = centralGlow(uv, lightPos, 0.15);
    flareColor += glow * flareIntensity * 0.8;
    
    // 4. Volumetric light rays
    let rays = volumetricRays(uv, lightPos, flareIntensity);
    flareColor += vec3<f32>(rays * 0.5, rays * 0.6, rays * 0.8);
    
    // 5. Starburst diffraction spikes (from aperture blades)
    let toLight = uv - lightPos;
    let angle = atan2(toLight.y, toLight.x);
    let dist = length(toLight);
    
    // 6-pointed star (hexagonal aperture)
    let starburst = pow(abs(sin(angle * 6.0)), 20.0) * exp(-dist * 3.0);
    flareColor += vec3<f32>(starburst * 0.3 * flareIntensity);
    
    // 6. Secondary rainbow halo (chromatic aberration effect)
    let haloDist = abs(dist - 0.25);
    let haloIntensity = exp(-haloDist * 100.0) * dispersion * 0.5;
    let rainbowPhase = angle * 3.0;
    let rainbow = vec3<f32>(
        (sin(rainbowPhase) + 1.0) * 0.5,
        (sin(rainbowPhase + TWO_PI / 3.0) + 1.0) * 0.5,
        (sin(rainbowPhase + 2.0 * TWO_PI / 3.0) + 1.0) * 0.5
    );
    flareColor += rainbow * haloIntensity * flareIntensity * 0.2;
    
    // Combine with base color using additive blending
    let finalColor = baseColor.rgb + flareColor;
    
    // Tone mapping for very bright areas (prevent pure white clipping)
    let tonemapped = finalColor / (1.0 + finalColor * 0.1);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(tonemapped, baseColor.a));
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
