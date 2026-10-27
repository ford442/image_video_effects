// ═══════════════════════════════════════════════════════════════════════════════
//  Parallax Shift
//  Category: distortion
//  Features: advanced-alpha, parallax, depth-aware, mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-10-27
//  Ideas: occlusion peel; focus-plane CoC; relief step from the depth residual; disocclusion gap
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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
        // ── Idea: relief step — nudge the sample by the depth residual at the first hit.
        let residual = (layerDepth - impliedDepth) * shiftAmount;
        let reliefUV = clamp(layerUV + parallaxDir * residual, vec2<f32>(0.0), vec2<f32>(1.0));
        let coc = abs(layerDepth - focusPlane) * shiftAmount * 12.0;
        let smear = parallaxDir * coc * 0.35;
        let layerSample = textureSampleLevel(readTexture, u_sampler, reliefUV, 0.0);
        let smearA = textureSampleLevel(readTexture, u_sampler, clamp(reliefUV + smear, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
        let smearB = textureSampleLevel(readTexture, u_sampler, clamp(reliefUV - smear, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
        var layerRgb = mix(layerSample.rgb, (smearA.rgb + smearB.rgb) * 0.5, clamp(coc, 0.0, 0.85));
        // ── Idea: disocclusion gap — a layer the nearer surface rejected goes dark.
        layerRgb = mix(layerRgb * 0.38, layerRgb, occlude);
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
