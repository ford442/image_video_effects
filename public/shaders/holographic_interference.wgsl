// ═══════════════════════════════════════════════════════════════════════════════
//  Holographic Interference - Advanced Alpha with Depth-Layered
//  Category: complex-multi-effect
//  Alpha Mode: Depth-Layered Alpha + Physical Transmittance
//  Features: advanced-alpha, interference-patterns, thin-film
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

// Mode 1: Depth-Layered Alpha
fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthAlpha = mix(0.4, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

// Thin film interference alpha
fn interferenceAlpha(opticalPath: f32, baseAlpha: f32) -> f32 {
    let interference = 0.5 + 0.5 * cos(opticalPath * 10.0);
    return baseAlpha * (0.7 + interference * 0.3);
}

// Combined alpha
fn calculateInterferenceAlpha(
    uv: vec2<f32>,
    opticalPath: f32,
    params: vec4<f32>
) -> f32 {
    let depthAlpha = depthLayeredAlpha(uv, params.z);
    let intAlpha = interferenceAlpha(opticalPath, params.x);
    return clamp(depthAlpha * intAlpha, 0.0, 1.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let filmThickness = u.zoom_params.x * 2.0 + 0.5;
    let wavelengthScale = u.zoom_params.y * 5.0 + 1.0;
    let depthWeight = u.zoom_params.z;
    let interferenceStrength = u.zoom_params.w;
    
    // Sample depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Thin film interference calculation
    let angle = length(uv - 0.5) * wavelengthScale;
    let opticalPath = filmThickness * cos(angle) + time * 0.2;
    
    // RGB interference
    let rPhase = opticalPath / 650.0;
    let gPhase = opticalPath / 530.0;
    let bPhase = opticalPath / 460.0;
    
    let r = 0.5 + 0.5 * cos(rPhase * 20.0);
    let g = 0.5 + 0.5 * cos(gPhase * 20.0);
    let b = 0.5 + 0.5 * cos(bPhase * 20.0);
    
    let interferenceColor = vec3<f32>(r, g, b) * interferenceStrength;
    
    // Sample base
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    // Blend interference with base
    let finalColor = mix(baseSample.rgb, interferenceColor, interferenceStrength * 0.5);
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let alpha = calculateInterferenceAlpha(uv, opticalPath, u.zoom_params);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    
    // Pass through depth
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
