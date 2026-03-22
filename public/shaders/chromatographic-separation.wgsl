// ═══════════════════════════════════════════════════════════════════════════════
//  Chromatographic Separation - Advanced Alpha with Depth-Layered
//  Category: complex-multi-effect
//  Alpha Mode: Depth-Layered Alpha + Effect Intensity
//  Features: advanced-alpha, chromatic-separation, depth-aware
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
fn depthLayeredAlpha(color: vec3<f32>, uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    
    let depthAlpha = mix(0.4, 1.0, depth);
    let lumaAlpha = mix(0.5, 1.0, luma);
    
    return mix(lumaAlpha, depthAlpha, depthWeight);
}

// Mode 5: Effect Intensity Alpha
fn effectIntensityAlpha(
    originalUV: vec2<f32>,
    displacedUV: vec2<f32>,
    baseAlpha: f32,
    intensity: f32
) -> f32 {
    let displacement = length(displacedUV - originalUV);
    let displacementAlpha = smoothstep(0.0, 0.1, displacement);
    
    let edgeDist = min(min(originalUV.x, 1.0 - originalUV.x),
                       min(originalUV.y, 1.0 - originalUV.y));
    let edgeFade = smoothstep(0.0, 0.05, edgeDist);
    
    return baseAlpha * mix(0.6, 1.0, displacementAlpha * intensity) * edgeFade;
}

// Combined advanced alpha
fn calculateAdvancedAlpha(
    color: vec3<f32>,
    originalUV: vec2<f32>,
    displacedUV: vec2<f32>,
    baseAlpha: f32,
    params: vec4<f32>
) -> f32 {
    let depthAlpha = depthLayeredAlpha(color, displacedUV, params.z);
    let effectAlpha = effectIntensityAlpha(originalUV, displacedUV, baseAlpha, params.x);
    return clamp(depthAlpha * effectAlpha, 0.0, 1.0);
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
    let separationAmount = u.zoom_params.x * 0.1;
    let rotation = u.zoom_params.y * 6.28;
    let depthWeight = u.zoom_params.z;
    let separationMode = u.zoom_params.w;
    
    // Sample depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Calculate chromatic separation based on depth
    let depthOffset = (1.0 - depth) * separationAmount;
    
    // Rotation for separation direction
    let c = cos(rotation + time * 0.2);
    let s = sin(rotation + time * 0.2);
    
    // RGB channel separation
    let rOffset = vec2<f32>(c, s) * depthOffset * (1.0 + separationMode);
    let gOffset = vec2<f32>(c * 0.5, s * 0.5) * depthOffset;
    let bOffset = vec2<f32>(-c, -s) * depthOffset * (1.0 - separationMode * 0.5);
    
    // Sample channels
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + rOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + gOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + bOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    
    let finalColor = vec3<f32>(r, g, b);
    
    // Calculate displaced UV (average of offsets)
    let displacedUV = uv + (rOffset + gOffset + bOffset) / 3.0;
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let alpha = calculateAdvancedAlpha(finalColor, uv, displacedUV, baseSample.a, u.zoom_params);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    
    // Pass through depth
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
