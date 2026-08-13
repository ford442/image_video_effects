// ═══════════════════════════════════════════════════════════════════
//  Crossover: Convolution + Mouse — Bilateral Paint
//  Category: image
//  Features: crossover, mouse-driven, advanced-convolution, audio-reactive, upgraded-rgba
//  Crosses: conv-bilateral-dream (1C) + mouse-paint-splatter (2C)
//  Complexity: Medium
//  Created: 2026-04-19
//  By: Agent 5C — Phase C Crossover Integration
// ═══════════════════════════════════════════════════════════════════
//
//  The mouse acts as a brush that paints bilateral-filter smoothness.
//  Near the cursor, the bilateral filter preserves edges while smoothing
//  noise; far from the cursor, the effect decays to the original image.
//  Clicking increases the spatial kernel radius for stronger smoothing.
//
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

fn sampleColor(uv: vec2<f32>) -> vec3<f32> {
    return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
}

fn gaussSpatial(dist2: f32, sigma: f32) -> f32 {
    return exp(-dist2 / (2.0 * sigma * sigma));
}

fn gaussRange(diff: f32, sigma: f32) -> f32 {
    return exp(-(diff * diff) / (2.0 * sigma * sigma));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixel = 1.0 / res;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    let time = u.config.x;
    let aspect = res.x / res.y;
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Parameters — bass swells the brush, mids sharpen edge preservation
    let brushSize = mix(0.05, 0.25, u.zoom_params.x) * (1.0 + bass * 0.4);
    let edgePreserve = mix(0.02, 0.2, u.zoom_params.y) * (1.0 + mids * 0.35);
    let strength = mix(0.0, 1.0, u.zoom_params.z);
    let clickBoost = select(1.0, 2.5, mouseDown);
    
    let mouseDelta = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let mouseDist = length(mouseDelta);
    let brushFalloff = exp(-mouseDist * mouseDist / (brushSize * brushSize));
    let travelDir = vec2<f32>(cos(time * 0.9), sin(time * 0.9));
    let brushRunner = pow(max(0.0, sin(dot(mouseDelta, travelDir) * 52.0 - time * 13.0)), 12.0) * brushFalloff;

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.8) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            clickFront += smoothstep(0.025, 0.0, abs(length(delta) - age * 0.45)) * exp(-age * 1.6);
        }
    }
    let localStrength = strength * clamp(brushFalloff * clickBoost + brushRunner * 0.45 + clickFront, 0.0, 1.5);
    
    if (localStrength < 0.01) {
        // Untouched region: alpha marks zero filter coverage
        let col = sampleColor(uv);
        let passthrough = vec4<f32>(col, 0.0);
        textureStore(writeTexture, global_id.xy, passthrough);
        textureStore(dataTextureA, vec2<i32>(global_id.xy), passthrough);
        let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
        textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
        return;
    }
    
    let centerCol = sampleColor(uv);
    let centerLuma = dot(centerCol, vec3<f32>(0.299, 0.587, 0.114));
    
    var sumColor = vec3<f32>(0.0);
    var sumWeight = 0.0;
    
    let sigmaS = mix(1.5, 4.0, localStrength) * pixel.x;
    let sigmaR = edgePreserve;
    
    for (var y: i32 = -3; y <= 3; y = y + 1) {
        for (var x: i32 = -3; x <= 3; x = x + 1) {
            let offset = vec2<f32>(f32(x), f32(y)) * pixel;
            let sUV = uv + offset;
            let sCol = sampleColor(sUV);
            let sLuma = dot(sCol, vec3<f32>(0.299, 0.587, 0.114));
            
            let spatialDist2 = dot(offset, offset);
            let rangeDiff = sLuma - centerLuma;
            
            let w = gaussSpatial(spatialDist2, sigmaS) * gaussRange(rangeDiff, sigmaR);
            sumColor = sumColor + sCol * w;
            sumWeight = sumWeight + w;
        }
    }
    
    let filtered = sumColor / max(sumWeight, 0.0001);
    var finalColor = mix(centerCol, filtered, localStrength);

    // Bass lifts the smoothed region so the brush reads as a glowing sheen
    let sheen = clamp(localStrength, 0.0, 1.0) * bass;
    finalColor = clamp(finalColor + vec3<f32>(0.4, 0.55, 0.8) * (sheen + clickFront * 0.4) * 0.25, vec3<f32>(0.0), vec3<f32>(4.0));

    // Alpha carries filter coverage — how much this pixel was actually smoothed
    let alpha = clamp(localStrength, 0.0, 1.0);
    let outColor = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, global_id.xy, outColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), outColor);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
