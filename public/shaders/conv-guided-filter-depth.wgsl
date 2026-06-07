// ═══════════════════════════════════════════════════════════════════
//  Guided Filter Depth
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, depth-aware, mouse-driven
//  Convolution Type: guided-filter
//  Complexity: High
//  Created: 2026-04-18
//  By: Agent 1C — RGBA Convolution Architect
// ═══════════════════════════════════════════════════════════════════
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Filtered image (HDR, unclamped during accumulation)
//    Alpha: Filtering confidence — the 'a' coefficient from the guided filter
//           linear model. High |a| means strong edge guidance, low |a| means
//           smooth region. This encodes how "reliable" the filtered result is.
//
//  Uses depth texture as guide for edge-aware filtering that respects
//  object boundaries without bleeding.
//
//  MOUSE INTERACTIVITY:
//    Mouse creates a localized "focus aperture" where the guided filter
//    uses a smaller radius (sharper) and lower epsilon (stronger edges).
//    Far from mouse = dreamy depth-of-field blur with larger radius.
//    Ripples create transient depth discontinuities.
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
    let radiusBase = i32(mix(2.0, 8.0, u.zoom_params.x));
    let epsilonBase = mix(0.0001, 0.05, u.zoom_params.y);
    let depthInfluence = u.zoom_params.z;  // How much depth guides the filter
    let mouseInfluence = u.zoom_params.w;
    
    // Mouse focus aperture
    let mouseDist = length(uv - mousePos);
    let mouseFactor = exp(-mouseDist * mouseDist * 6.0) * mouseInfluence;
    let radius = i32(mix(f32(radiusBase), f32(radiusBase) * 0.4, mouseFactor));
    let epsilon = mix(epsilonBase * 3.0, epsilonBase * 0.1, mouseFactor);
    
    // Ripple depth discontinuities
    var rippleDepth = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rPos = ripple.xy;
        let rStart = ripple.z;
        let rElapsed = time - rStart;
        if (rElapsed > 0.0 && rElapsed < 2.5) {
            let rDist = length(uv - rPos);
            let wave = exp(-rDist * rDist * 40.0) * (1.0 - rElapsed / 2.5);
            rippleDepth = rippleDepth + wave;
        }
    }
    
    let maxRadius = min(radius, 7);
    
    var sumGuide = 0.0;
    var sumInput = vec3<f32>(0.0);
    var sumGuideInput = vec3<f32>(0.0);
    var sumGuide2 = 0.0;
    var count = 0.0;
    
    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let guideVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + offset, 0.0).r + rippleDepth * 0.1;
            let inputVal = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
            sumGuide += guideVal;
            sumInput += inputVal;
            sumGuideInput += inputVal * guideVal;
            sumGuide2 += guideVal * guideVal;
            count += 1.0;
        }
    }
    
    let meanGuide = sumGuide / count;
    let meanInput = sumInput / count;
    let meanGI = sumGuideInput / count;
    let meanGuide2 = sumGuide2 / count;
    let varGuide = meanGuide2 - meanGuide * meanGuide;
    
    // Linear model coefficients: output = a * guide + b
    let a = (meanGI - meanGuide * meanInput) / (varGuide + epsilon);
    let b = meanInput - a * meanGuide;
    
    let guide = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + rippleDepth * 0.1;
    let result = a * guide + b;
    
    // Confidence = how much the guide influences the result
    let confidence = length(a) * depthInfluence;
    
    // Mix between guided result and original based on depth influence
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let finalResult = mix(original, result, depthInfluence);
    
    // Store: RGB = filtered image, Alpha = filtering confidence
    textureStore(writeTexture, global_id.xy, vec4<f32>(finalResult, confidence));
    
    // Depth pass-through (with ripple)
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
