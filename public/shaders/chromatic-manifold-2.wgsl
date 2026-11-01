// ═══════════════════════════════════════════════════════════════════
//  Chromatic Manifold V2
//  Category: artistic
//  Features: mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-09, 2026-11-01
//  Ideas: laplacian smooth of curvature; C.a fold memory; curvature iso-lines; leaky curvature memory; memory-gated re-fold of history
//  A packing: A.rgb pre-ACES display color; A.a raw curvature memory
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

// ═══════════════════════════════════════════════════════════════════════════════
//  SPECTRAL PHYSICS CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════
const WAVELENGTH_RED:    f32 = 650.0;  // nm
const WAVELENGTH_GREEN:  f32 = 550.0;  // nm
const WAVELENGTH_BLUE:   f32 = 450.0;  // nm

// ═══════════════════════════════════════════════════════════════════════════════
//  WAVELENGTH-DEPENDENT ALPHA
// ═══════════════════════════════════════════════════════════════════════════════
fn calculateChannelAlpha(thickness: f32, wavelength: f32) -> f32 {
    let lambda_norm = (800.0 - wavelength) / 400.0;
    let absorption = mix(0.3, 1.0, lambda_norm);
    return exp(-thickness * absorption);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  RGB ↔ HSV conversion
// ═══════════════════════════════════════════════════════════════════════════════
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    var p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
    let q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
    var d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    var x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Möbius-like hue fold around a pivot
// ═══════════════════════════════════════════════════════════════════════════════
fn foldHue(h: f32, pivot: f32, strength: f32) -> f32 {
    let delta = h - pivot;
    let folded = pivot + sign(delta) * pow(abs(delta), strength);
    return fract(folded);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Wrap-around modulo for hue gradients
// ═══════════════════════════════════════════════════════════════════════════════
fn wrapMod(x: f32, y: f32) -> f32 {
    if (y == 0.0) { return x; }
    return x - y * floor(x / y);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  2-D hash for noise
// ═══════════════════════════════════════════════════════════════════════════════
fn hash2(p: vec2<f32>) -> f32 {
    var p2 = fract(p * vec2<f32>(123.456, 789.012));
    p2 = p2 + dot(p2, p2 + 45.678);
    return fract(p2.x * p2.y);
}

fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    var uv = vec2<f32>(gid.xy) / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;

    // Parameters
    // JSON order fold_strength / pivot_hue / sat_scale / depth_influence → zoom_params.xyzw.
    // HEAD read these from zoom_config (time / mouse / down) and the four non-slider values
    // from zoom_params; the latter now sit at their old midpoints.
    let foldStrength = u.zoom_params.x * 2.0 + 0.5;
    let pivotHue = u.zoom_params.y;
    let satScale = u.zoom_params.z * 0.5 + 0.75;
    let depthInfluence = u.zoom_params.w;
    let noiseAmount = 0.0015;
    let feedbackPersist = 0.95;
    let rippleAmp = 0.0075;
    let curvePower = 2.0;

    // Read source color & depth
    let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Compute local hue gradient (with wrap-around handling)
    let h = rgb2hsv(srcColor).x;
    let hR = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb).x;
    let hL = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).rgb).x;
    let hU = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb).x;
    let hD = rgb2hsv(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).rgb).x;

    // Wrap-around gradient
    let gradX = wrapMod(hR - hL + 1.5, 1.0) - 0.5;
    let gradY = wrapMod(hU - hD + 1.5, 1.0) - 0.5;
    let hueGrad = vec2<f32>(gradX, gradY);

    // Depth curvature, smoothed by one 5-tap laplacian (not a Ricci flow).
    let px = vec2<i32>(gid.xy);
    let resi = vec2<i32>(max(dims, vec2<f32>(1.0)));
    let curveHere = pow(max(depthVal, 0.0), curvePower) * depthInfluence;
    let depthL = textureLoad(readDepthTexture, clamp(px + vec2<i32>(-1, 0), vec2<i32>(0), resi - vec2<i32>(1)), 0).r;
    let depthR = textureLoad(readDepthTexture, clamp(px + vec2<i32>(1, 0), vec2<i32>(0), resi - vec2<i32>(1)), 0).r;
    let depthU = textureLoad(readDepthTexture, clamp(px + vec2<i32>(0, -1), vec2<i32>(0), resi - vec2<i32>(1)), 0).r;
    let depthD = textureLoad(readDepthTexture, clamp(px + vec2<i32>(0, 1), vec2<i32>(0), resi - vec2<i32>(1)), 0).r;
    let curveL = pow(max(depthL, 0.0), curvePower) * depthInfluence;
    let curveR = pow(max(depthR, 0.0), curvePower) * depthInfluence;
    let curveU = pow(max(depthU, 0.0), curvePower) * depthInfluence;
    let curveD = pow(max(depthD, 0.0), curvePower) * depthInfluence;
    let curvature = (curveHere + curveL + curveR + curveU + curveD) * 0.2;

    // C.a is yesterday's curvature. High memory folds this pixel harder.
    let histSize = vec2<i32>(textureDimensions(dataTextureC));
    let prev = textureLoad(dataTextureC, clamp(px, vec2<i32>(0), histSize - vec2<i32>(1)), 0);
    let foldMemory = clamp(prev.a, 0.0, 1.0);

    let dispBase = hueGrad * foldStrength * (1.0 + foldMemory * 0.85) * 0.05 * (1.0 + curvature);

    // Add temporal noise
    let noise = hash2(uv * 100.0 + time);
    let noiseDisp = vec2<f32>(
        sin(time + noise * 6.28318),
        cos(time + noise * 6.28318)
    ) * noiseAmount;

    var totalDisp = dispBase + noiseDisp;

    // Mouse-driven ripples
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[min(i, 49u)];
        let t = time - r.z;
        if (t > 0.0 && t < 3.0) {
            var dir = uv - r.xy;
            var d = length(dir);
            if (d > 0.0001) {
                let rippleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, r.xy, 0.0).r;
                let depthFactor = 1.0 - rippleDepth;
                let speed = mix(1.0, 2.0, depthFactor);
                let amp = rippleAmp * mix(0.5, 1.5, depthFactor);
                let wave = sin(d * 30.0 - t * speed);
                let falloff = 1.0 / (d * 20.0 + 1.0);
                let atten = 1.0 - smoothstep(0.0, 3.0, t);
                totalDisp = totalDisp + normalize(dir) * wave * amp * falloff * atten;
            }
        }
    }

    // Sample displaced UV for color
    let displacedUV = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));
    let displacedColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    let foldStrengthMem = foldStrength * (1.0 + foldMemory * 0.85);

    // Fold the hue (Möbius-like effect), harder where curvature was high last frame.
    var hsv = rgb2hsv(displacedColor);
    hsv.x = foldHue(hsv.x, pivotHue, foldStrengthMem);
    hsv.y = clamp(hsv.y * satScale, 0.0, 1.0);
    let foldedColor = hsv2rgb(hsv.x, hsv.y, hsv.z);

    // Idea 3: memory-gated re-fold — where yesterday's curvature was high the history is
    // folded about the same pivot again (gently), so creases nest where the manifold bends.
    // At foldMemory = 0 the strength is 1.0, which foldHue leaves untouched.
    var prevRgb = max(prev.rgb, vec3<f32>(0.0));
    var prevHsv = rgb2hsv(prevRgb);
    prevHsv.x = foldHue(prevHsv.x, pivotHue, mix(1.0, foldStrengthMem, 0.04 * foldMemory));
    prevRgb = hsv2rgb(prevHsv.x, prevHsv.y, prevHsv.z);
    let finalColor = mix(foldedColor, prevRgb, feedbackPersist);

    // ═══════════════════════════════════════════════════════════════════════════════
    //  WAVELENGTH-DEPENDENT ALPHA
    //  Thickness derived from fold strength and curvature
    // ═══════════════════════════════════════════════════════════════════════════════
    let foldThickness = foldStrength * 0.5 + curvature * 2.0 + length(totalDisp) * 10.0;
    let dispersionThickness = foldThickness;
    
    let alphaR = calculateChannelAlpha(dispersionThickness, WAVELENGTH_RED);
    let alphaG = calculateChannelAlpha(dispersionThickness, WAVELENGTH_GREEN);
    let alphaB = calculateChannelAlpha(dispersionThickness, WAVELENGTH_BLUE);
    
    let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
    let finalAlpha = dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights);
    
    let alphaModulatedColor = vec3<f32>(
        finalColor.r * alphaR,
        finalColor.g * alphaG,
        finalColor.b * alphaB
    );

    // Idea 1: curvature iso-lines — topographic contours of the same smoothed curvature
    // field the fold uses. AA width from the central difference of the curvature taps, so
    // lines stay ~1.5 px wide; flat depth has zero gradient and draws nothing.
    let curveGrad = length(vec2<f32>(curveR - curveL, curveD - curveU)) * 0.5;
    let isoLevel = curvature * 12.0;
    let isoFrac = fract(isoLevel);
    let isoDist = min(isoFrac, 1.0 - isoFrac);
    let isoWidth = max(curveGrad * 12.0, 1e-3);
    let isoLine = (1.0 - smoothstep(0.6, 1.6, isoDist / isoWidth)) * smoothstep(0.0003, 0.002, curveGrad);
    let displayColor = max(alphaModulatedColor, vec3<f32>(0.0)) * (1.0 - 0.4 * isoLine);

    // A.rgb is pre-ACES display color. A.a is raw curvature, not tone-mapped.
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(aces_tonemap(displayColor), finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(alphaModulatedColor, clamp(max(curvature, foldMemory * 0.94), 0.0, 1.0)));  // Idea 2: leaky memory
}
