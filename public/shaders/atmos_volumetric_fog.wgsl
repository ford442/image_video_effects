// ═══════════════════════════════════════════════════════════════════
//  atmos_volumetric_fog
//  Category: atmospheric
//  Features: upgraded-rgba, depth-aware, physical-transmittance, volumetric-fog
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
    let depthAlpha = mix(0.2, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

// Combined fog alpha
fn calculateFogAlpha(
    uv: vec2<f32>,
    opticalDepth: f32,
    density: f32,
    params: vec4<f32>
) -> f32 {
    let volAlpha = volumetricAlpha(density, opticalDepth);
    let depthAlpha = depthLayeredAlpha(uv, params.z);
    return clamp(volAlpha * depthAlpha, 0.0, 1.0);
}

// Noise
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i++) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let fogDensity = u.zoom_params.x * 3.0;
    let fogHeight = u.zoom_params.y;
    let depthWeight = u.zoom_params.z;
    let fogColorShift = u.zoom_params.w;
    
    // Sample depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Fog density based on height and noise
    let fogUV = uv * 3.0 + vec2<f32>(time * 0.02, 0.0);
    let noiseVal = fbm(fogUV, 4);
    let heightFog = exp(-uv.y / fogHeight);
    let density = fogDensity * heightFog * (0.5 + noiseVal * 0.5);
    
    // Fog color (atmospheric scattering)
    let fogColor = vec3<f32>(
        0.7 + fogColorShift * 0.2,
        0.75 + fogColorShift * 0.1,
        0.85
    );
    
    // Sample background
    let bgSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    // Calculate optical depth
    let opticalDepth = density * (1.0 + (1.0 - depth));
    
    // Apply Beer's Law
    let absorptionCoeff = vec3<f32>(0.3, 0.4, 0.5);
    let transmitted = physicalTransmittance(bgSample.rgb, opticalDepth, absorptionCoeff);
    
    // Final color
    let alpha = calculateFogAlpha(uv, opticalDepth, density, u.zoom_params);
    let finalColor = mix(transmitted, fogColor, alpha * 0.7);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    
    // Pass through depth
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
