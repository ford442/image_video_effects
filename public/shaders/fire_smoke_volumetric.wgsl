// ═══════════════════════════════════════════════════════════════════════════════
//  Fire Smoke Volumetric - Advanced Alpha with Physical Transmittance
//  Category: volumetric/atmospheric
//  Alpha Mode: Physical Transmittance (Beer's Law) + Depth-Layered
//  Features: advanced-alpha, fire, smoke, volumetric
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

// Mode 4: Physical Transmittance
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

// Noise
fn hash(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(12.9898, 78.233, 54.53))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    let fireIntensity = u.zoom_params.x * 2.0;
    let smokeDensity = u.zoom_params.y;
    let depthWeight = u.zoom_params.z;
    let turbulence = u.zoom_params.w;
    
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Fire/Smoke noise
    let noiseUV = vec3<f32>(uv * 5.0, time * 0.5);
    let n = hash(vec3<f32>(noiseUV * 10.0));
    
    let fireShape = smoothstep(0.3, 0.7, 1.0 - uv.y + n * turbulence);
    let density = fireShape * smokeDensity;
    
    // Fire color gradient
    let fireColor = mix(
        vec3<f32>(1.0, 0.8, 0.1),
        vec3<f32>(0.8, 0.2, 0.05),
        uv.y * fireIntensity
    ) * fireShape;
    
    // Smoke color
    let smokeColor = vec3<f32>(0.3, 0.3, 0.35) * density;
    
    let finalColor = mix(smokeColor, fireColor, fireShape);
    
    let opticalDepth = density * (1.0 + turbulence);
    let absorptionCoeff = vec3<f32>(0.5, 0.6, 0.7);
    let transmitted = physicalTransmittance(finalColor, opticalDepth, absorptionCoeff);
    
    let volAlpha = volumetricAlpha(density, 1.0);
    let alpha = volAlpha * depthLayeredAlpha(uv, depthWeight);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(transmitted, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
