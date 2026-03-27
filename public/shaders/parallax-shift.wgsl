// ═══════════════════════════════════════════════════════════════════════════════
//  Parallax Shift - Advanced Alpha
//  Category: distortion
//  Alpha Mode: Effect Intensity Alpha + Depth-Layered
//  Features: advanced-alpha, parallax, depth-aware
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
    
    return baseAlpha * mix(0.5, 1.0, displacementAlpha * intensity) * edgeFade;
}

// Mode 1: Depth-Layered Alpha - foreground more opaque
fn depthLayeredAlpha(uv: vec2<f32>, depthWeight: f32) -> f32 {
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    // Foreground (depth near 1.0) = more opaque
    let depthAlpha = mix(0.3, 1.0, depth);
    return mix(1.0, depthAlpha, depthWeight);
}

// Combined advanced alpha
fn calculateAdvancedAlpha(
    originalUV: vec2<f32>,
    displacedUV: vec2<f32>,
    baseAlpha: f32,
    params: vec4<f32>
) -> f32 {
    let effectAlpha = effectIntensityAlpha(originalUV, displacedUV, baseAlpha, params.x);
    let depthAlpha = depthLayeredAlpha(displacedUV, params.z);
    
    return clamp(effectAlpha * depthAlpha, 0.0, 1.0);
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
    let shiftAmount = u.zoom_params.x * 0.1;     // Parallax shift amount
    let layerCount = i32(u.zoom_params.y * 4.0 + 2.0);  // Number of depth layers
    let depthWeight = u.zoom_params.z;           // Depth influence on alpha
    let focusPlane = u.zoom_params.w;            // Focus plane depth
    
    // Mouse position for parallax center
    let mousePos = u.zoom_config.yz;
    
    // Sample depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Calculate parallax offset based on depth difference from focus plane
    let depthDiff = depth - focusPlane;
    let parallaxDir = normalize(uv - mousePos + vec2<f32>(0.001));
    
    // Multi-layer sampling
    var accumulatedColor = vec3<f32>(0.0);
    var accumulatedWeight = 0.0;
    var maxDisplacement = 0.0;
    
    for (var i: i32 = 0; i < layerCount; i++) {
        let layerFactor = f32(i) / f32(layerCount - 1);
        let layerOffset = parallaxDir * depthDiff * shiftAmount * (layerFactor - 0.5) * 2.0;
        let layerUV = clamp(uv + layerOffset, vec2<f32>(0.0), vec2<f32>(1.0));
        
        let layerSample = textureSampleLevel(readTexture, u_sampler, layerUV, 0.0);
        let layerWeight = 1.0 - abs(layerFactor - 0.5) * 2.0;
        
        accumulatedColor += layerSample.rgb * layerWeight;
        accumulatedWeight += layerWeight;
        maxDisplacement = max(maxDisplacement, length(layerOffset));
    }
    
    let finalColor = accumulatedColor / max(accumulatedWeight, 0.001);
    
    // Calculate displaced UV (average displacement)
    let displacedUV = clamp(uv + parallaxDir * depthDiff * shiftAmount, vec2<f32>(0.0), vec2<f32>(1.0));
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let alpha = calculateAdvancedAlpha(uv, displacedUV, baseSample.a, u.zoom_params);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    
    // Pass through depth
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
