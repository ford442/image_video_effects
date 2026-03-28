// ═══════════════════════════════════════════════════════════════════════════════
//  Kimi Liquid Glass - Advanced Alpha with Physical Transmittance
//  Category: complex-multi-effect
//  Alpha Mode: Physical Transmittance (Beer's Law) + Depth-Layered
//  Features: advanced-alpha, liquid-glass, physical-rendering
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ═══ ADVANCED ALPHA FUNCTIONS ═══

// Mode 4: Physical Transmittance (Beer's Law)
fn physicalTransmittance(
    baseColor: vec3<f32>,
    opticalDepth: f32,
    absorptionCoeff: vec3<f32>
) -> vec3<f32> {
    let transmittance = exp(-absorptionCoeff * opticalDepth);
    return baseColor * transmittance;
}

fn volumetricAlpha(density: f32, thickness: f32) -> f32 {
    return 1.0 - exp(-density * thickness);
}

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = mix(0.3, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

// Combined glass alpha
fn calculateGlassAlpha(
    uv: vec2<f32>,
    thickness: f32,
    density: f32,
    params: vec4<f32>
) -> f32 {
    let volAlpha = volumetricAlpha(density, thickness);
    let depthAlpha = depthLayeredAlpha(uv, params.z);
    return clamp(volAlpha * depthAlpha, 0.0, 1.0);
}

// Schlick Fresnel
fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Noise
fn noise(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn smoothNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(noise(i), noise(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(noise(i + vec2<f32>(0.0, 1.0)), noise(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // ═══ AUDIO REACTIVITY ═══
    let audioOverall = u.zoom_config.x;
    let audioBass = audioOverall * 1.5;
    let audioReactivity = 1.0 + audioOverall * 0.3;
    
    // Parameters
    let glassThickness = u.zoom_params.x * 2.0 + 0.5;
    let ior = u.zoom_params.y * 0.5 + 1.3;
    let depthWeight = u.zoom_params.z;
    let distortion = u.zoom_params.w * 0.1;
    
    // Liquid glass distortion
    let noiseVal = smoothNoise(uv * 5.0 + time * 0.1 * audioReactivity);
    let distortionVec = vec2<f32>(
        smoothNoise(uv * 3.0 + time * 0.15 * audioReactivity),
        smoothNoise(uv * 3.0 + time * 0.12 * audioReactivity + 100.0)
    ) * distortion;
    
    let warpedUV = clamp(uv + distortionVec, vec2<f32>(0.0), vec2<f32>(1.0));
    
    // Sample background
    let bgSample = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Glass absorption (blue-tinted)
    let absorptionCoeff = vec3<f32>(0.3, 0.5, 0.8) * glassThickness;
    let opticalDepth = glassThickness * (1.0 + noiseVal * 0.5);
    
    // Apply transmittance
    let transmitted = physicalTransmittance(bgSample.rgb, opticalDepth, absorptionCoeff);
    
    // Fresnel effect
    let viewDir = normalize(vec2<f32>(0.5) - uv);
    let surfaceNormal = normalize(distortionVec + vec2<f32>(0.0, 0.001));
    let cosTheta = max(dot(viewDir, surfaceNormal), 0.0);
    let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
    let fresnel = schlickFresnel(cosTheta, F0);
    
    // Reflection color (subtle)
    let reflection = vec3<f32>(0.9, 0.95, 1.0) * fresnel;
    
    let finalColor = transmitted + reflection;
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let density = 0.5 + noiseVal * 0.5;
    let alpha = calculateGlassAlpha(uv, opticalDepth, density, u.zoom_params);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    
    // Depth with glass modulation
    let depthMod = 1.0 + fresnel * 0.1;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth * depthMod, 0.0, 0.0, 0.0));
}
