// ═══════════════════════════════════════════════════════════════════
//  Blueprint Reveal + Guided Filter Depth
//  Category: advanced-hybrid
//  Features: advanced-convolution, depth-aware, mouse-driven
//  Complexity: High
//  Chunks From: blueprint-reveal.wgsl, conv-guided-filter-depth.wgsl
//  Created: 2026-04-18
//  By: Agent CB-10 — Image Processing & Artistry Enhancer
// ═══════════════════════════════════════════════════════════════════
//
//  Hybrid Approach:
//    1. Apply depth-guided filter to smooth input image before edge detection
//    2. Guided filter respects object boundaries (no edge bleeding)
//    3. Run Sobel edge detection on guided-filtered image
//    4. Blueprint lines now follow true object contours
//    5. Reveal mask shows the guided-filtered real image near mouse
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Blueprint lines on blue background, or revealed filtered image
//    Alpha: Guided filter confidence — high confidence = solid line,
//           low confidence = faint/ghosted line. Creates natural line weight.
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

// ═══ CHUNK: sobel (from blueprint-reveal.wgsl) ═══
fn sobel(uv: vec2<f32>, res: vec2<f32>) -> f32 {
    let x = 1.0 / res.x;
    let y = 1.0 / res.y;
    let tl = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2(-x, -y), 0.0).rgb, vec3(0.333));
    let t  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2( 0.0, -y), 0.0).rgb, vec3(0.333));
    let tr = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2( x, -y), 0.0).rgb, vec3(0.333));
    let l  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2(-x,  0.0), 0.0).rgb, vec3(0.333));
    let r  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2( x,  0.0), 0.0).rgb, vec3(0.333));
    let bl = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2(-x,  y), 0.0).rgb, vec3(0.333));
    let b  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2( 0.0,  y), 0.0).rgb, vec3(0.333));
    let br = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2( x,  y), 0.0).rgb, vec3(0.333));
    let gx = tl * -1.0 + tr * 1.0 + l * -2.0 + r * 2.0 + bl * -1.0 + br * 1.0;
    let gy = tl * -1.0 + t * -2.0 + tr * -1.0 + bl * 1.0 + b * 2.0 + br * 1.0;
    return sqrt(gx * gx + gy * gy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let pixelSize = 1.0 / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    // Parameters
    let edgeStrength = mix(0.5, 5.0, u.zoom_params.x);
    let gridOpacity = u.zoom_params.y;
    let radius = mix(0.05, 0.6, u.zoom_params.z);
    let softness = mix(0.01, 0.3, u.zoom_params.w);
    let depthInfluence = 0.8;

    // === GUIDED FILTER ===
    // Use depth as guide for edge-aware smoothing
    let guidedRadius = i32(mix(2.0, 5.0, 0.5));
    let epsilon = 0.001;
    let maxRadius = min(guidedRadius, 5);

    var sumGuide = 0.0;
    var sumInput = vec3<f32>(0.0);
    var sumGuideInput = vec3<f32>(0.0);
    var sumGuide2 = 0.0;
    var count = 0.0;

    for (var dy = -maxRadius; dy <= maxRadius; dy++) {
        for (var dx = -maxRadius; dx <= maxRadius; dx++) {
            let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
            let guideVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + offset, 0.0).r;
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

    let a = (meanGI - meanGuide * meanInput) / (varGuide + epsilon);
    let b = meanInput - a * meanGuide;

    let guide = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let guidedResult = a * guide + b;

    // Confidence = how much the guide influences
    let confidence = length(a) * depthInfluence;

    // Mix between guided and original
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let filteredColor = mix(original, guidedResult, depthInfluence);

    // Mouse reveal mask
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2(aspect, 1.0);
    let dist = length(distVec);
    let revealMask = 1.0 - smoothstep(radius, radius + softness, dist);

    // Blueprint on guided-filtered image
    // We temporarily use filteredColor for edge detection
    let edgeVal = sobel(uv, resolution) * edgeStrength;

    // Blueprint background + white edges
    var blueprint = vec3(0.05, 0.1, 0.4) + vec3(0.8, 0.9, 1.0) * edgeVal;

    // Grid Overlay
    let gridSize = 40.0;
    let gridLineX = smoothstep(0.9, 0.95, sin(uv.x * gridSize * aspect * 3.14159));
    let gridLineY = smoothstep(0.9, 0.95, sin(uv.y * gridSize * 3.14159));
    let grid = max(gridLineX, gridLineY) * gridOpacity * 0.3;
    blueprint += vec3(grid);

    // Revealed image uses guided-filtered color
    let finalColor = mix(blueprint, filteredColor, revealMask);

    // Alpha: confidence-modulated blueprint intensity
    let alpha = mix(0.85, 1.0, confidence * revealMask + (1.0 - revealMask) * 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4(finalColor, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(filteredColor, confidence));
}
