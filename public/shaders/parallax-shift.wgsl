// ═══════════════════════════════════════════════════════════════════════════════
//  Parallax Shift
//  Category: distortion
//  Features: advanced-alpha, parallax, depth-aware, mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-09-08
//  Ideas: occlusion peel (near layers outweigh far); focus-plane CoC along the ray
//  A packing: ACES display RGBA
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Parameters — bass deepens the parallax separation
    let shiftAmount = u.zoom_params.x * 0.1 * (1.0 + bass * 0.5);
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
    
    let denomLayers = max(f32(layerCount - 1), 1.0);
    for (var i: i32 = 0; i < layerCount; i++) {
        let layerFactor = f32(i) / denomLayers;
        let layerOffset = parallaxDir * depthDiff * shiftAmount * (layerFactor - 0.5) * 2.0;
        let layerUV = clamp(uv + layerOffset, vec2<f32>(0.0), vec2<f32>(1.0));
        let layerDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, layerUV, 0.0).r;
        // Occlusion peel: a nearer sample owns the ray; farther layers drop out.
        let impliedDepth = mix(focusPlane, depth, layerFactor);
        let occlude = smoothstep(-0.08, 0.12, impliedDepth - layerDepth);
        let tent = 1.0 - abs(layerFactor - 0.5) * 2.0;
        var layerWeight = max(tent, 0.05) * (0.25 + occlude);
        // Focus-plane CoC: off-plane layers smear along the parallax ray.
        let coc = abs(layerDepth - focusPlane) * shiftAmount * 12.0;
        let smear = parallaxDir * coc * 0.35;
        let layerSample = textureSampleLevel(readTexture, u_sampler, layerUV, 0.0);
        let smearA = textureSampleLevel(readTexture, u_sampler, clamp(layerUV + smear, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
        let smearB = textureSampleLevel(readTexture, u_sampler, clamp(layerUV - smear, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
        let layerRgb = mix(layerSample.rgb, (smearA.rgb + smearB.rgb) * 0.5, clamp(coc, 0.0, 0.85));
        accumulatedColor += layerRgb * layerWeight;
        accumulatedWeight += layerWeight;
        maxDisplacement = max(maxDisplacement, length(layerOffset));
    }
    
    var finalColor = accumulatedColor / max(accumulatedWeight, 0.001);

    // Mids tint the layer separation — a chromatic ghost on displaced edges
    let ghostUV = clamp(uv + parallaxDir * depthDiff * shiftAmount * 1.5, vec2<f32>(0.0), vec2<f32>(1.0));
    let ghost = textureSampleLevel(readTexture, u_sampler, ghostUV, 0.0).rgb;
    finalColor = finalColor + (ghost - finalColor) * vec3<f32>(0.3, 0.0, -0.3) * mids;

    // Bass rim-lights the strongly displaced (off-focus-plane) regions
    let sep = clamp(maxDisplacement * 12.0, 0.0, 1.0);
    finalColor = finalColor + vec3<f32>(0.3, 0.5, 0.9) * sep * bass * 0.4;

    // Calculate displaced UV (average displacement)
    let displacedUV = clamp(uv + parallaxDir * depthDiff * shiftAmount, vec2<f32>(0.0), vec2<f32>(1.0));
    
    // ═══ ADVANCED ALPHA CALCULATION ═══
    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let alpha = clamp(calculateAdvancedAlpha(uv, displacedUV, baseSample.a, u.zoom_params)
                      + sep * bass * 0.2, 0.0, 1.0);

    let outColor = vec4<f32>(acesToneMap(finalColor), alpha);
    textureStore(writeTexture, vec2<i32>(global_id.xy), outColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), outColor);

    // Pass through depth
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
