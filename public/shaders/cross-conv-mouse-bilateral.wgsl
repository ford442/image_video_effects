// ═══════════════════════════════════════════════════════════════════
//  Crossover: Convolution + Mouse — Bilateral Paint
//  Category: image
//  Features: crossover, mouse-driven, advanced-convolution
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
    return textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
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
    
    // Parameters
    let brushSize = mix(0.05, 0.25, u.zoom_params.x);
    let edgePreserve = mix(0.02, 0.2, u.zoom_params.y);
    let strength = mix(0.0, 1.0, u.zoom_params.z);
    let clickBoost = select(1.0, 2.5, mouseDown);
    
    let mouseDist = length(uv - mousePos);
    let brushFalloff = exp(-mouseDist * mouseDist / (brushSize * brushSize));
    let localStrength = strength * brushFalloff * clickBoost;
    
    if (localStrength < 0.01) {
        let col = sampleColor(uv);
        textureStore(writeTexture, global_id.xy, vec4<f32>(col, 1.0));
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
    let finalColor = mix(centerCol, filtered, localStrength);
    
    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
