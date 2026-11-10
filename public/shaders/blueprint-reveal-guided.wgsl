// ═══════════════════════════════════════════════════════════════════
//  Blueprint Reveal + Guided Filter Depth
//  Category: advanced-hybrid
//  Features: advanced-convolution, depth-aware, mouse-driven, upgraded-rgba
//  Complexity: High
//  Chunks From: blueprint-reveal.wgsl, conv-guided-filter-depth.wgsl
//  Created: 2026-04-18
//  By: Agent CB-10 — Image Processing & Artistry Enhancer
//  Upgraded: 2026-11-10
//  Ideas: hairline thinning by gradient-oriented non-max suppression, outline weight from depth steps; tone hatching from the guided-filtered luma (dark = dense: 45° / cross / interleaved)
//  A packing: display-space (A = guided-filtered colour + confidence; nothing reads C). ACES on the blueprint background + hatch only (grid and pen lines are added after the tone-map); the revealed photo stays LDR
//  Revealed image (unchanged HEAD behaviour, disclosed 2026-11-10): an 80 % blend to a 7x7 depth-guided mean (a·guide+b, ε 0.001), keeping roughly 23 % of the
//  source's high-frequency energy. With a flat or absent depth map the guided filter degenerates to a plain 7x7 box mean — by design, not guarded.
// ═══════════════════════════════════════════════════════════════════
//
//  Hybrid Approach:
//    1. Apply depth-guided filter to smooth input image before edge detection
//    2. Guided filter respects object boundaries (no edge bleeding)
//    3. Run Sobel edge detection on guided-filtered image
//       (NOTE 2026-11-10: the Sobel still reads the RAW image; the depth guide sets the
//        outline weight instead — see Idea 1)
//    4. Blueprint lines now follow true object contours
//    5. Reveal mask shows the guided-filtered real image near mouse
//
//  RGBA32FLOAT EXPLOITATION:
//    RGB: Blueprint lines on blue background, or revealed filtered image
//    Alpha: Guided filter confidence — high confidence = solid line,
//           low confidence = faint/ghosted line. Creates natural line weight.
//
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Hatch pitch in pixels and hatch brightness.
const HATCH_PX: f32 = 8.0;
const HATCH_GAIN: f32 = 1.0;
// Pen-line brightness gain (1 = lines peak at white after the tone-map).
const LINE_GAIN: f32 = 1.0;

const LUMA: vec3<f32> = vec3<f32>(0.299, 0.587, 0.114);

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: sobel (from blueprint-reveal.wgsl) ═══
// Returns the luma gradient (gx, gy); the magnitude is length(); the direction is what
// Idea 1 uses (HEAD returned only the magnitude and threw the direction away).
fn sobelGrad(uv: vec2<f32>, res: vec2<f32>) -> vec2<f32> {
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
    return vec2<f32>(gx, gy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    // Pixel-centre uv: every tap below lands exactly on a texel centre (HEAD's gid/res
    // read texel corners, i.e. a 2x2 bilinear box in front of every filter tap).
    var uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
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
    let guidedRadius = i32(mix(2.0f, 5.0f, 0.5f));
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

    let meanGuide = sumGuide / max(count, 1.0);
    let meanInput = sumInput / max(count, 1.0);
    let meanGI = sumGuideInput / max(count, 1.0);
    let meanGuide2 = sumGuide2 / max(count, 1.0);
    let varGuide = meanGuide2 - meanGuide * meanGuide;

    let a = (meanGI - meanGuide * meanInput) / (varGuide + epsilon);
    let b = meanInput - a * meanGuide;

    let guide = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let guidedResult = a * guide + b;

    // Confidence = how much the guide influences
    let confidence = length(a) * depthInfluence;

    // Mix between guided and original
    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    // the guided fit can overshoot below zero at depth steps
    let filteredColor = max(mix(original, guidedResult, depthInfluence), vec3<f32>(0.0));

    // Mouse reveal mask
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2(aspect, 1.0);
    let dist = length(distVec);
    let revealMask = 1.0 - smoothstep(radius, radius + softness, dist);

    // Blueprint edges (Sobel on the source luma)
    let g0 = sobelGrad(uv, resolution);
    let m0 = length(g0);

    // ── Idea 1: pen hairlines (non-max suppression) + depth-step outline weight ──
    // HEAD's Sobel magnitude drew a 3-px smear that saturated to white. A drafting pen
    // draws ONE hairline, heavier where an object ends. Compare the magnitude with its
    // two neighbours along the gradient direction and keep only the ridge; Edge Strength
    // stays the line gain. A depth step (object boundary) loosens the ridge test and
    // adds weight, so outlines read heavier than interior detail.
    let gDir = g0 / (m0 + 1e-4);
    let m1 = length(sobelGrad(uv + gDir * pixelSize, resolution));
    let m2 = length(sobelGrad(uv - gDir * pixelSize, resolution));
    // Depth-step probe: ±3 px, so the gentle ramps of a depth-estimation map register as a step.
    let dTap = 3.0 * pixelSize;
    let dStep = abs(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(dTap.x, 0.0), 0.0).r
                  - textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(dTap.x, 0.0), 0.0).r)
              + abs(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, dTap.y), 0.0).r
                  - textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, dTap.y), 0.0).r);
    let outline = smoothstep(0.008, 0.06, dStep);
    let ridgeTol = mix(0.14, 0.55, outline);
    let ridge = clamp((m0 - max(m1, m2)) / (ridgeTol * m0 + 1e-4) + 1.0, 0.0, 1.0);
    // lineMask is the pen coverage 0..1: it blends toward white AFTER the tone-map, so a
    // strong ridge peaks at 1.0 (HEAD's lines saturated to white too).
    let lineAmt = ridge * (1.0 - exp(-m0 * edgeStrength * 2.2)) * (1.0 + 0.8 * outline);
    let lineMask = clamp(lineAmt * LINE_GAIN, 0.0, 1.0);

    // ── Idea 2: tone hatching on the blueprint side (dark = dense) ──
    // Technical drawings carry tone as hatching, not as flat fill: the DARKER the guided
    // luma, the more strokes and the heavier they are. Level 1 = 45° hatch (tone < ~0.8),
    // level 2 = cross-hatch (tone < ~0.55), level 3 = a second 45° set interleaved half a
    // pitch (tone < ~0.3). Stroke width grows with darkness. Reading the GUIDED luma keeps
    // the hatching calm (no per-pixel noise). Bright paper (tone > ~0.8) stays blank.
    let tone = dot(filteredColor, LUMA);
    let dark = 1.0 - clamp(tone, 0.0, 1.0);
    let pxy = uv * resolution;
    let phA = fract((pxy.x + pxy.y) / (HATCH_PX * 1.4142));
    let phB = fract((pxy.x - pxy.y) / (HATCH_PX * 1.4142));
    let phC = fract((pxy.x + pxy.y) / (HATCH_PX * 1.4142) + 0.5);
    let strokeW = mix(0.07, 0.17, dark);
    let sA = 1.0 - smoothstep(strokeW, strokeW + 0.07, abs(phA - 0.5));
    let sB = 1.0 - smoothstep(strokeW, strokeW + 0.07, abs(phB - 0.5));
    let sC = 1.0 - smoothstep(strokeW, strokeW + 0.07, abs(phC - 0.5));
    let lv1 = smoothstep(0.18, 0.30, dark);
    let lv2 = smoothstep(0.42, 0.54, dark);
    let lv3 = smoothstep(0.68, 0.80, dark);
    let hatch = clamp(sA * lv1 + sB * lv2 + sC * lv3, 0.0, 1.0) * (1.0 - lineMask) * HATCH_GAIN;

    // Tone-mapped layer = background + hatch. Background is set PRE-ACES so it lands on HEAD's
    // navy (0.05, 0.105, 0.40) after the tone-map.
    var blueprint = aces(max(vec3(0.054, 0.088, 0.27) + vec3(0.45, 0.70, 1.0) * (hatch * (0.14 + 0.10 * dark)), vec3<f32>(0.0)));

    // Grid Overlay — added AFTER the tone-map so a grid line at default opacity keeps HEAD's
    // (0.20, 0.25, 0.55) instead of being lifted by ACES.
    let gridSize = 40.0;
    let gridLineX = smoothstep(0.9, 0.95, sin(uv.x * gridSize * aspect * 3.14159));
    let gridLineY = smoothstep(0.9, 0.95, sin(uv.y * gridSize * 3.14159));
    let grid = max(gridLineX, gridLineY) * gridOpacity * 0.3;
    blueprint = blueprint + vec3(grid);

    // Pen lines last: blend to white by coverage (peak 1.0).
    blueprint = mix(blueprint, vec3<f32>(1.0), lineMask);

    // Revealed image uses guided-filtered color
    let finalColor = mix(blueprint, filteredColor, revealMask);

    // Alpha: confidence-modulated blueprint intensity
    let alpha = clamp(mix(0.85, 1.0, confidence * revealMask + (1.0 - revealMask) * 0.5), 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4(finalColor, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(filteredColor, confidence));
}
