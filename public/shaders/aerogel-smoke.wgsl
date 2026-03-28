// ═══════════════════════════════════════════════════════════════════
//  aerogel-smoke
//  Category: atmospheric
//  Features: upgraded-rgba, depth-aware, volumetric-alpha
//  Upgraded: 2026-03-22
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

// Physical constants for aerogel (silica nanoparticles)
const SIGMA_T_AEROGEL: f32 = 1.5;       // Total extinction coefficient
const SIGMA_S_RAYLEIGH: f32 = 0.6;      // Rayleigh scattering (fine particles)
const SIGMA_S_MIE: f32 = 0.7;           // Mie scattering (particle clumps)
const SIGMA_A: f32 = 0.2;               // Absorption (minimal for silica)
const STEP_SIZE: f32 = 0.025;           // Ray step through medium

// Phase function approximations
const RAYLEIGH_G: f32 = 0.0;            // Rayleigh: isotropic-ish
const MIE_G: f32 = 0.75;                // Mie: forward scattering

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pp = p;
    for (var i = 0; i < 5; i++) {
        v += a * noise(pp);
        pp = rot * pp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// Henyey-Greenstein phase function approximation
fn phaseHG(cosTheta: f32, g: f32) -> f32 {
    let g2 = g * g;
    return (1.0 - g2) / (4.0 * 3.14159265 * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Parameters
    let densityMult = u.zoom_params.x * 2.0;
    let scattering = u.zoom_params.y; // Blue tint intensity
    let glow = u.zoom_params.z;       // Light intensity
    let bgMix = u.zoom_params.w;      // 0 = Full Aerogel, 1 = Show Background

    // Base Image
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Generate Volume Density (Aerogel Smoke)
    var p = uv * 3.0 + vec2<f32>(time * 0.05, time * 0.02);
    var density = fbm(p);

    // Add detail layers
    density += fbm(p * 4.0) * 0.5;
    density += fbm(p * 8.0) * 0.25;
    density = smoothstep(0.2, 0.8, density) * densityMult;

    // ═══════════════════════════════════════════════════════════════
    //  Volumetric Light Transport for Aerogel
    // ═══════════════════════════════════════════════════════════════
    
    // Calculate optical depth through the medium
    // τ = ∫ σ_t ds ≈ density * step_size * extinction_coeff
    let optical_depth = density * STEP_SIZE * SIGMA_T_AEROGEL;
    
    // Transmittance (Beer-Lambert law): T = exp(-τ)
    let transmittance = exp(-optical_depth);
    
    // Volumetric alpha: α = 1 - T
    let alpha = 1.0 - transmittance;
    
    // Lighting calculation with scattering
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let lightFalloff = 1.0 / (1.0 + dist * dist * 10.0);
    
    // Light direction (from mouse)
    let lightDir = normalize(vec3<f32>(mouse - uv, 0.5));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let cosTheta = dot(viewDir, lightDir);
    
    // Combined scattering (Rayleigh + Mie)
    let phaseR = 0.75 * (1.0 + cosTheta * cosTheta); // Rayleigh phase
    let phaseM = phaseHG(cosTheta, MIE_G);           // Mie phase
    let combinedPhase = mix(phaseR, phaseM, 0.5);
    
    // Light color (cool white for aerogel)
    let lightColor = vec3<f32>(0.9, 0.95, 1.0) * glow * lightFalloff;
    
    // In-scattered light
    // L_s = L_i * σ_s * phase * density
    let scatterCoeff = mix(SIGMA_S_RAYLEIGH, SIGMA_S_MIE, density);
    let inScattered = lightColor * scatterCoeff * combinedPhase * density;
    
    // Rayleigh scattering tint (Aerogel Blue) - wavelength-dependent scattering
    // Shorter wavelengths (blue) scatter more
    let rayleighTint = vec3<f32>(0.3, 0.6, 1.0) * scattering * lightFalloff * density * SIGMA_S_RAYLEIGH;
    
    // Aerogel albedo (white/translucent)
    let aerogelAlbedo = vec3<f32>(0.95, 0.97, 1.0);
    let scatteredColor = inScattered * aerogelAlbedo + rayleighTint;
    
    // Volumetric compositing
    // Final color = in_scattered + transmitted_background
    // where transmitted = background * transmittance
    var finalColor = scatteredColor + baseColor * transmittance;
    
    // Allow fading out the effect
    finalColor = mix(scatteredColor, finalColor, bgMix);
    
    // Tone map (simple gamma correction)
    finalColor = pow(finalColor, vec3<f32>(1.0/1.2));
    
    // Output RGBA with volumetric alpha
    // RGB: In-scattered + transmitted light
    // A: Volumetric opacity from optical depth
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));

    // Pass depth with optical depth information
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    // Store modified depth accounting for volumetric opacity
    let volumetricDepth = mix(depth, 0.5, alpha * 0.5);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(volumetricDepth, optical_depth, 0.0, alpha));
}
