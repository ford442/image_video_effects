// ═══════════════════════════════════════════════════════════════════
//  Guided Filter Depth
//  Category: image
//  Features: advanced-convolution, rgba32float-exploiting, depth-aware, mouse-driven
//  Convolution Type: guided-filter
//  Complexity: High
//  Upgraded: 2026-09-08
//  Ideas: joint luma range on the depth guide; photo-edge hold when depth misses
//  A packing: ACES display RGBA
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }
    
    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let pixelSize = 1.0 / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Parameters
    let radiusBase = i32(mix(2.0, 8.0, u.zoom_params.x) * (1.0 + bass * 0.25));
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
    let rippleCount = min(u32(u.config.y), 50u);
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
    
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let centerLuma = dot(original.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let pixel = vec2<i32>(global_id.xy);

    var sumGuide = 0.0;
    var sumInput = vec3<f32>(0.0);
    var sumGuideInput = vec3<f32>(0.0);
    var sumGuide2 = 0.0;
    var count = 0.0;
    
    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let p = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            let guideVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, p, 0.0).r + rippleDepth * 0.1;
            let inputVal = textureSampleLevel(readTexture, u_sampler, p, 0.0).rgb;
            let sampleLuma = dot(inputVal, vec3<f32>(0.299, 0.587, 0.114));
            let lumaW = exp(-pow(sampleLuma - centerLuma, 2.0) / 0.025);
            sumGuide += guideVal * lumaW;
            sumInput += inputVal * lumaW;
            sumGuideInput += inputVal * guideVal * lumaW;
            sumGuide2 += guideVal * guideVal * lumaW;
            count += lumaW;
        }
    }
    
    let meanGuide = sumGuide / max(count, 1.0);
    let meanInput = sumInput / max(count, 1.0);
    let meanGI = sumGuideInput / max(count, 1.0);
    let meanGuide2 = sumGuide2 / max(count, 1.0);
    let varGuide = meanGuide2 - meanGuide * meanGuide;
    
    // Linear model coefficients: output = a * guide + b
    let a = (meanGI - meanGuide * meanInput) / (varGuide + epsilon);
    let b = meanInput - a * meanGuide;
    
    let guide = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + rippleDepth * 0.1;
    let result = a * guide + b;
    
    // Confidence = how much the guide influences the result
    let confidence = length(a) * depthInfluence;
    let finalResult = mix(original.rgb, result, depthInfluence);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    let lumaN = dot(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, pixelSize.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let depthN = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + vec2<f32>(0.0, pixelSize.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let keepPhoto = smoothstep(0.02, 0.14, abs(lumaN - centerLuma) - abs(depthN - guide));
    let mixed = mix(finalResult, original.rgb, keepPhoto * 0.5);
    let mapped = acesToneMap(mixed * (1.0 + mids * 0.2));
    let alpha = clamp(confidence + original.a * 0.2, 0.0, 1.0);
    let packed = vec4<f32>(mapped, alpha);
    textureStore(writeTexture, pixel, packed);
    textureStore(dataTextureA, pixel, packed);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
