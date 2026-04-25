// ═══════════════════════════════════════════════════════════════════
//  Non-Local Means
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, mouse-driven
//  Convolution Type: non-local-means
//  Complexity: Very High
//  Created: 2026-04-18
//  By: Agent 1C — RGBA Convolution Architect
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Denoised / artistically blended color
//    Alpha: Self-similarity map — how many similar patches were found for
//           each pixel. Low similarity = isolated/unique texture = high alpha.
//           High similarity = repetitive texture = low alpha. This creates a
//           natural importance map for downstream shaders.
//
//  MOUSE INTERACTIVITY:
//    Mouse position sets a "focus zone" where patch similarity is computed
//    with higher precision (smaller h parameter). Far from mouse = more
//    artistic overdrive (larger h, more patch blending).
//    Ripples create localized "echo bursts" where similar patches merge.
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

fn patchDistance(uv1: vec2<f32>, uv2: vec2<f32>, patchRadius: i32, pixelSize: vec2<f32>) -> f32 {
    var dist = 0.0;
    for (var dy = -patchRadius; dy <= patchRadius; dy++) {
        for (var dx = -patchRadius; dx <= patchRadius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let p1 = textureSampleLevel(readTexture, u_sampler, uv1 + offset, 0.0).rgb;
            let p2 = textureSampleLevel(readTexture, u_sampler, uv2 + offset, 0.0).rgb;
            let diff = p1 - p2;
            dist += dot(diff, diff);
        }
    }
    return dist;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Parameters
    let patchRadius = i32(mix(1.0, 3.0, u.zoom_params.x));
    let searchRadius = i32(mix(3.0, 10.0, u.zoom_params.y));
    let hParamBase = mix(0.001, 0.1, u.zoom_params.z);  // Filter strength
    let overdrive = u.zoom_params.w;  // Artistic overdrive
    
    // Mouse focus zone
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 5.0);
    let hParam = mix(hParamBase * 2.0, hParamBase * 0.3, mouseFactor);
    
    // Ripple echo bursts
    var rippleEcho = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 3.0) {
            let rDist = length(uv - rPos);
            let wave = exp(-pow((rDist - rElapsed * 0.2) * 10.0, 2.0));
            rippleEcho = rippleEcho + wave * (1.0 - rElapsed / 3.0);
        }
    }
    let effectiveH = max(hParam * (1.0 + rippleEcho * 3.0), 0.0001);
    
    let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;
    var similaritySum = 0.0;
    var maxSimilarity = 0.0;
    
    let maxSearch = min(searchRadius, 8);
    
    for (var dy = -maxSearch; dy <= maxSearch; dy++) {
        for (var dx = -maxSearch; dx <= maxSearch; dx++) {
            if (dx == 0 && dy == 0) { continue; }
            
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let neighborUV = uv + offset;
            
            let pd = patchDistance(uv, neighborUV, patchRadius, pixelSize);
            let weight = exp(-pd / effectiveH);
            
            let neighborColor = textureSampleLevel(readTexture, u_sampler, neighborUV, 0.0).rgb;
            accumColor += neighborColor * weight;
            accumWeight += weight;
            similaritySum += weight;
            maxSimilarity = max(maxSimilarity, weight);
        }
    }
    
    // Self-weight for center pixel
    accumColor += center;
    accumWeight += 1.0;
    similaritySum += 1.0;
    maxSimilarity = max(maxSimilarity, 1.0);
    
    var result = vec3<f32>(0.0);
    if (accumWeight > 0.001) {
        result = accumColor / accumWeight;
    }
    
    // Artistic overdrive: blend with original based on similarity
    let avgSimilarity = similaritySum / (f32(maxSearch * maxSearch * 4) + 1.0);
    let overdriveBlend = overdrive * (1.0 - avgSimilarity);
    result = mix(result, center, overdriveBlend);
    
    // Self-similarity importance map: low similarity = unique = high alpha
    let importance = 1.0 - avgSimilarity;
    
    // Store: RGB = filtered/overdriven color, Alpha = importance map
    textureStore(writeTexture, global_id.xy, vec4<f32>(result, importance));
    
    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
