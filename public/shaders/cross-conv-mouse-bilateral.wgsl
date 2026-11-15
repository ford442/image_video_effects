// ═══════════════════════════════════════════════════════════════════
//  Bilateral Paint
//  Category: image
//  Features: crossover, mouse-driven, advanced-convolution, audio-reactive, click-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-16, 2026-11-15
//  Ideas: range coring; wet edge on the brush; persistent drying paint canvas in C (§12.2C); joint chroma & depth range weight
//  A packing: linear painted RGB + brush coverage alpha (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════
//
//  The mouse acts as a brush that paints bilateral-filter smoothness.
//  Near the cursor, the bilateral filter preserves edges while smoothing
//  noise; far from the cursor, the effect decays to the original image.
//  Clicking increases the spatial kernel radius for stronger smoothing.
//
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn sampleColor(uv: vec2<f32>) -> vec3<f32> {
    return textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
}

fn gaussSpatial(dist2: f32, sigma: f32) -> f32 {
    return exp(-dist2 / (2.0 * sigma * sigma));
}

fn gaussRange(diff: f32, sigma: f32) -> f32 {
    return exp(-(diff * diff) / (2.0 * sigma * sigma));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
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
    let treble = plasmaBuffer[0].z;
    let coord = vec2<i32>(global_id.xy);

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

    // ── Idea 3: persistent drying paint canvas in C (§12.2C) ─────────────
    let prevCanvas = textureLoad(dataTextureC, coord, 0);
    let drying = mix(0.955, 0.992, u.zoom_params.z);
    let driedCoverage = select(0.0, prevCanvas.a * drying, prevCanvas.a * drying >= 0.005);

    let centerSample = textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let centerCol = centerSample.rgb;
    let centerDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    if (localStrength < 0.01) {
        // Outside live brush: either completely dry passthrough or drying stroke from C
        let dryBlend = mix(centerCol, prevCanvas.rgb, clamp(driedCoverage, 0.0, 1.0));
        let storedLinear = select(max(centerCol, vec3<f32>(0.0)), prevCanvas.rgb, driedCoverage > 0.0);
        textureStore(dataTextureA, coord, vec4<f32>(storedLinear, driedCoverage));
        textureStore(writeTexture, global_id.xy, vec4<f32>(aces(max(dryBlend, vec3<f32>(0.0))), driedCoverage));
        textureStore(writeDepthTexture, global_id.xy, vec4<f32>(centerDepth, 0.0, 0.0, 0.0));
        return;
    }
    
    let centerLuma = dot(centerCol, vec3<f32>(0.299, 0.587, 0.114));
    let centerChroma = centerCol - vec3<f32>(centerLuma);
    
    var sumColor = vec3<f32>(0.0);
    var sumWeight = 0.0;
    
    let sigmaS = mix(1.5, 4.0, clamp(localStrength, 0.0, 1.0)) * pixel.x;
    let sigmaR = edgePreserve;
    
    for (var y: i32 = -3; y <= 3; y = y + 1) {
        for (var x: i32 = -3; x <= 3; x = x + 1) {
            let offset = vec2<f32>(f32(x), f32(y)) * pixel;
            let sUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            let sCol = sampleColor(sUV);
            let sLuma = dot(sCol, vec3<f32>(0.299, 0.587, 0.114));
            let sDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sUV, 0.0).r;
            
            let spatialDist2 = dot(offset, offset);
            let rangeDiff = abs(sLuma - centerLuma);
            // ── Idea 4: joint chroma-opponent & depth-silhouette range weight ──
            let chromaDiff = length((sCol - vec3<f32>(sLuma)) - centerChroma) * 0.85;
            let depthDiff = abs(sDepth - centerDepth) * 2.1;
            let jointDiff = sqrt(rangeDiff * rangeDiff + chromaDiff * chromaDiff + depthDiff * depthDiff);

            // Idea 1 — range coring: gaps smaller than the core are sensor noise.
            let core = 0.012 + edgePreserve * 0.04;
            let cored = max(jointDiff - core, 0.0);
            
            let w = gaussSpatial(spatialDist2, sigmaS) * gaussRange(cored, sigmaR);
            sumColor = sumColor + sCol * w;
            sumWeight = sumWeight + w;
        }
    }
    
    let filtered = sumColor / max(sumWeight, 0.0001);
    let freshCoverage = clamp(localStrength, 0.0, 1.0);
    var strokeLinear = mix(centerCol, filtered, freshCoverage);

    // Bass + subtle treble lift the smoothed region so the brush reads as a wet sheen
    let sheen = freshCoverage * (bass + treble * 0.25);
    strokeLinear = clamp(strokeLinear + vec3<f32>(0.4, 0.55, 0.8) * (sheen + clickFront * 0.4) * 0.25, vec3<f32>(0.0), vec3<f32>(4.0));

    // Idea 2 — wet edge where brush coverage falls off.
    let wet = smoothstep(0.12, 0.32, brushFalloff) * (1.0 - smoothstep(0.48, 0.78, brushFalloff));
    strokeLinear = strokeLinear * (1.0 - wet * 0.22);

    // Merge fresh stroke into drying paint canvas in linear space
    let canvasCoverage = max(driedCoverage, freshCoverage);
    let strokeMix = clamp(freshCoverage / max(canvasCoverage, 0.001), 0.0, 1.0);
    let storedRGB = mix(prevCanvas.rgb, strokeLinear, strokeMix);
    let displayLinear = mix(centerCol, storedRGB, canvasCoverage);

    // Alpha carries active + drying paint coverage
    let alpha = clamp(canvasCoverage * (0.85 + centerSample.a * 0.15), 0.0, 1.0);
    textureStore(dataTextureA, coord, vec4<f32>(storedRGB, canvasCoverage));
    textureStore(writeTexture, global_id.xy, vec4<f32>(aces(max(displayLinear, vec3<f32>(0.0))), alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(centerDepth, 0.0, 0.0, 0.0));
}
