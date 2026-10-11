// ═══════════════════════════════════════════════════════════════════════════════
//  Chromatic Manifold - Color-as-dimension topology with wavelength-alpha
//  Category: artistic
//  Features: 4d-manifold, hue-topology, wavelength-dependent-alpha, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: hue level sets; visible colour debt (complementary ghost, repaid via persistence)
//  A packing: signed linear RGB (debt < 0) + Beer-Lambert alpha; C read as colour/debt; display = ACES(max(0,·)) + debt ghost
//
//  SCIENTIFIC MODEL:
//  - Manifold curvature affects dispersion and alpha per channel
//  - Beer-Lambert law: alpha = exp(-thickness * absorption)
//  - Red (650nm): lowest absorption, highest transmission
//  - Blue (450nm): highest absorption, lowest transmission
// ═══════════════════════════════════════════════════════════════════════════════

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

// Utility: rgb->hsv
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    var p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
    var q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
    var d = q.x - min(q.w, q.y);
    // HEAD added K.x (= 0) instead of q.z, which dropped the hue sector (hue stuck in 0..1/6).
    let h = abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10));
    return vec3<f32>(h, d, q.x);
}

// ─────────────────────────────────────────────────────────────────────────────
// ACES Tone Mapping
// ─────────────────────────────────────────────────────────────────────────────
fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let m1 = mat3x3<f32>(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777
    );
    let m2 = mat3x3<f32>(
        1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602
    );
    let v = m1 * color;
    let a = v * (v + 0.0245786) - 0.000090537;
    let b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return clamp(m2 * (a / b), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Weighted hue of a neighbour, unwrapped relative to the centre hue so the
// 0/1 seam does not read as a cliff in the gradient fit. Hue is undefined on
// grey pixels (JPEG noise makes it jump ±0.5), so the difference is gated by the
// lower saturation of the pair — otherwise grey regions get a random, capped warp.
fn unwrappedHueW(nHue: f32, nSat: f32, centreHue: f32, centreSat: f32, boost: f32) -> f32 {
    let dh = (fract(nHue - centreHue + 0.5) - 0.5) * smoothstep(0.05, 0.2, min(nSat, centreSat));
    return (centreHue + dh) * (1.0 + nSat * boost);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    var dims = u.config.zw;
    let gid = global_id.xy;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    var uv = vec2<f32>(f32(gid.x) / dims.x, f32(gid.y) / dims.y);

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

    var hsv = rgb2hsv(src.rgb);
    let hue = hsv.x;
    let sat = hsv.y;
    let val = hsv.z;
    let boost = u.zoom_params.x;
    let hueW0 = hue * (1.0 + sat * boost);

    // curvature influence from depth
    var curvature = 1.0 + u.zoom_params.y * depthVal * 5.0;
    // hue-axis weight of the 4D metric (HEAD shadowed `curvature` with this inside the loop)
    let hueCurv = depthVal * depthVal * 5.0 * u.zoom_params.w;

    // radius scale for HDR tears
    let maxRGB = max(max(src.r, src.g), src.b);
    var radiusScale = 1.0;
    if (maxRGB > 1.0) {
        radiusScale = min((maxRGB - 1.0) * 10.0, 4.0);
    }

    // Neighbor search — fixed 7×7 strided grid covering the HEAD radius
    // (HEAD scanned (2·ceil(0.02·r·width)+1)² taps: ~53² at 1280 px, unbounded on HDR).
    let searchRadius = 0.02 * radiusScale;
    let winPx = max(searchRadius * u.config.z, 1.0);
    let stride = max(i32(round(winPx / 3.0)), 1);
    let maxPix = vec2<i32>(i32(u.config.z) - 1, i32(u.config.w) - 1);
    var bestIdx : array<vec2<i32>, 4>;
    var bestDist : array<f32, 4>;
    var bestHueW : array<f32, 4>;
    for (var i : i32 = 0; i < 4; i = i + 1) { bestDist[i] = 1e20; bestIdx[i] = vec2<i32>(-1, -1); bestHueW[i] = hueW0; }

    for (var gy : i32 = -3; gy <= 3; gy = gy + 1) {
        for (var gx : i32 = -3; gx <= 3; gx = gx + 1) {
            let cand = vec2<i32>(i32(gid.x) + gx * stride, i32(gid.y) + gy * stride);
            if (cand.x < 0 || cand.y < 0 || cand.x > maxPix.x || cand.y > maxPix.y) { continue; }
            let nCol = textureLoad(readTexture, cand, 0).rgb;
            let nDepth = textureLoad(readDepthTexture, cand, 0).r;
            let nHsv = rgb2hsv(nCol);
            let nHueW = unwrappedHueW(nHsv.x, nHsv.y, hue, sat, boost);

            var nUV = vec2<f32>(f32(cand.x) / dims.x, f32(cand.y) / dims.y);
            let duv = nUV - uv;
            let ddepth = nDepth - depthVal;
            let dhue  = nHueW - hueW0;
            let weightedHue = dhue * hueCurv;
            let dist4 = dot(duv, duv) + ddepth * ddepth + weightedHue * weightedHue;

            var worstIndex : i32 = 0;
            var worstVal : f32 = bestDist[0];
            for (var b : i32 = 1; b < 4; b = b + 1) {
                if (bestDist[b] > worstVal) { worstVal = bestDist[b]; worstIndex = b; }
            }
            if (dist4 < worstVal) {
                bestDist[worstIndex] = dist4;
                bestIdx[worstIndex] = cand;
                bestHueW[worstIndex] = nHueW;
            }
        }
    }

    // Estimate gradient — least squares of the hue *difference* to the centre.
    // (HEAD regressed the absolute hue on offsets and tested det > 1e-6 in uv⁴
    // units, which never passes at texel spacing: grad was always 0, warp dead.)
    var sumXX : f32 = 0.0;
    var sumYY : f32 = 0.0;
    var sumXY : f32 = 0.0;
    var sumXH : f32 = 0.0;
    var sumYH : f32 = 0.0;
    for (var i : i32 = 0; i < 4; i = i + 1) {
        let bpos = bestIdx[i];
        if (bpos.x < 0) { continue; }
        let nUV = vec2<f32>(f32(bpos.x) / dims.x, f32(bpos.y) / dims.y);
        let nh = bestHueW[i] - hueW0;
        let d = nUV - uv;
        sumXX = sumXX + d.x * d.x;
        sumYY = sumYY + d.y * d.y;
        sumXY = sumXY + d.x * d.y;
        sumXH = sumXH + d.x * nh;
        sumYH = sumYH + d.y * nh;
    }
    var grad : vec2<f32> = vec2<f32>(0.0, 0.0);
    let det = sumXX * sumYY - sumXY * sumXY;
    if (det > 1e-4 * sumXX * sumYY && sumXX * sumYY > 0.0) {
        let invDet = 1.0 / det;
        let a = (sumYY * sumXH - sumXY * sumYH) * invDet;
        let b = (-sumXY * sumXH + sumXX * sumYH) * invDet;
        grad = vec2<f32>(a, b);
    }
    let gradLen = length(grad);

    // warp UV using hue gradient (bass adds ≤ +30%). The centred gradient is in
    // hue-per-uv, so the gain is rescaled and capped: hue cliffs cannot fling the read off-frame.
    let warpStrength = clamp(u.zoom_params.y, 0.0, 1.0) * (1.0 + 0.3 * bass);
    var warp = grad * (warpStrength * 0.002);
    let warpLen = length(warp);
    if (warpLen > 0.02) { warp = warp * (0.02 / warpLen); }
    let warpedUV = uv + warp;

    // sample previous frame feedback (exact load, clamped)
    let cDims = vec2<i32>(textureDimensions(dataTextureC));
    let cCoord = clamp(vec2<i32>(warpedUV * vec2<f32>(cDims)), vec2<i32>(0), cDims - vec2<i32>(1));
    var prevColor = textureLoad(dataTextureC, cCoord, 0);

    // color debt for shadows
    var outColor = src;
    if (val < 0.2) {
        outColor = -abs(src);
    }

    // HDR tears
    let tearThreshold = mix(1.2, 3.0, clamp(u.zoom_params.z, 0.0, 1.0));
    if (maxRGB > tearThreshold) {
        var smearDir = vec2<f32>(1.0, 0.0);
        if (gradLen > 1e-6) { smearDir = grad / gradLen; }
        let smear = smearDir * radiusScale * 0.02;
        let smearUV = uv + smear;
        let smearCol = textureSampleLevel(readTexture, u_sampler, smearUV, 0.0);
        outColor = mix(outColor, smearCol, 0.6);
        outColor = vec4<f32>(outColor.rgb + (maxRGB - 1.0) * 0.5, outColor.a);
    }

    // Combine with persistence (HEAD: mouseY·0.99 → fixed midpoint).
    // Idea 2 (repayment): debt carried in C (negative rgb) is paid back through this
    // mix once the pixel leaves shadow — the ghost fades back to the true colour.
    let persistence = 0.5;
    var combined = mix(outColor, prevColor, persistence);

    // ═══════════════════════════════════════════════════════════════════════════════
    //  WAVELENGTH-DEPENDENT ALPHA
    //  Thickness derived from manifold curvature and HDR
    // ═══════════════════════════════════════════════════════════════════════════════
    let manifoldThickness = curvature * 0.5 + (maxRGB - 1.0) * 0.5;
    let dispersionThickness = manifoldThickness;
    
    let alphaR = calculateChannelAlpha(dispersionThickness, WAVELENGTH_RED);
    let alphaG = calculateChannelAlpha(dispersionThickness, WAVELENGTH_GREEN);
    let alphaB = calculateChannelAlpha(dispersionThickness, WAVELENGTH_BLUE);
    
    let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
    let finalAlpha = dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights);
    
    let finalColor = vec3<f32>(
        combined.r * alphaR,
        combined.g * alphaG,
        combined.b * alphaB
    );

    // ── Display ──
    // Idea 2: Visible colour debt — negative C is drawn as the complementary,
    // inverted ghost of the colour that was borrowed (HEAD fed it to ACES, where
    // negatives turn bright).
    let credit = max(finalColor, vec3<f32>(0.0));
    let debt = max(-finalColor, vec3<f32>(0.0));
    let debtHi = max(max(debt.r, debt.g), debt.b);
    let debtLo = min(min(debt.r, debt.g), debt.b);
    let debtGhost = (vec3<f32>(debtHi + debtLo) - debt) * 1.6;
    var display = credit + debtGhost;

    // Idea 1: Hue level sets — iso-hue contours of the manifold (fract(hueW·N)),
    // AA width from the LSQ gradient, so the 4-D surface reads as a topographic
    // map draped on the photo. Grey pixels carry no hue → no contour.
    let bands = 8.0;
    let f = fract(hueW0 * bands);
    let toLine = min(f, 1.0 - f) / bands;               // hue distance to the nearest level
    let huePerPx = max(length(grad / dims), 1e-3);      // hue change per pixel
    let contour = (1.0 - smoothstep(0.6, 1.6, toLine / huePerPx)) * smoothstep(0.08, 0.3, sat);
    let contourTint = src.rgb / max(maxRGB, 1e-3) * 0.7 + 0.3;
    display = mix(display, contourTint * (0.55 + 0.45 * val), contour * (0.45 + 0.25 * bass));

    textureStore(dataTextureA, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(aces_tonemap(max(display, vec3<f32>(0.0))), finalAlpha));

    textureStore(writeDepthTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
