// ═══════════════════════════════════════════════════════════════════════════════
//  Chromatic Manifold - Color-as-dimension topology with wavelength-alpha
//  Category: artistic
//  Features: 4d-manifold, hue-topology, wavelength-dependent-alpha
//
//  SCIENTIFIC MODEL:
//  - Manifold curvature affects dispersion and alpha per channel
//  - Beer-Lambert law: alpha = exp(-thickness * absorption)
//  - Red (650nm): lowest absorption, highest transmission
//  - Blue (450nm): highest absorption, lowest transmission
// ═══════════════════════════════════════════════════════════════════════════════

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
    let h = abs((q.w - q.y) / (6.0 * d + 1e-10) + K.x);
    return vec3<f32>(h, d, q.x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    var dims = u.config.zw;
    let gid = global_id.xy;

    var uv = vec2<f32>(f32(gid.x) / dims.x, f32(gid.y) / dims.y);

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    var hsv = rgb2hsv(src.rgb);
    let hue = hsv.x;
    let sat = hsv.y;
    let val = hsv.z;

    // curvature influence from depth
    var curvature = 1.0 + u.zoom_params.y * depthVal * 5.0;

    // 4D point
    let point4 = vec4<f32>(uv.x, uv.y, depthVal, hue * sat * curvature);

    // radius scale for HDR tears
    let maxRGB = max(max(src.r, src.g), src.b);
    var radiusScale = 1.0;
    if (maxRGB > 1.0) {
        radiusScale = (maxRGB - 1.0) * 10.0;
    }

    // Neighbor search
    let searchRadius = 0.02 * radiusScale;
    let winSize = i32(ceil(searchRadius * u.config.z));
    var bestIdx : array<vec2<i32>, 4>;
    var bestDist : array<f32, 4>;
    for (var i : i32 = 0; i < 4; i = i + 1) { bestDist[i] = 1e20; bestIdx[i] = vec2<i32>(-1, -1); }

    for (var dy : i32 = -winSize; dy <= winSize; dy = dy + 1) {
        for (var dx : i32 = -winSize; dx <= winSize; dx = dx + 1) {
            let cand = vec2<i32>(i32(gid.x) + dx, i32(gid.y) + dy);
            if (cand.x < 0 || cand.y < 0 || cand.x >= i32(u.config.z) || cand.y >= i32(u.config.w)) { continue; }
            let nCol = textureLoad(readTexture, cand, 0).rgb;
            let nDepth = textureLoad(readDepthTexture, cand, 0).r;
            let nHsv = rgb2hsv(nCol);
            let nHue = nHsv.x;
            let nSat = nHsv.y;
            let nHueW = nHue * (1.0 + nSat * u.zoom_params.x);

            var nUV = vec2<f32>(vec2<f32>(f32(cand.x) / dims.x, f32(cand.y) / dims.y));
            let duv = nUV - uv;
            let ddepth = nDepth - depthVal;
            let dhue  = nHueW - hue * (1.0 + sat * u.zoom_params.x);
            var curvature = depthVal * depthVal * 5.0 * u.zoom_params.w;
            let weightedHue = dhue * curvature;
            let dist4 = dot(duv, duv) + ddepth * ddepth + weightedHue * weightedHue;

            var worstIndex : i32 = 0;
            var worstVal : f32 = bestDist[0];
            for (var b : i32 = 1; b < 4; b = b + 1) {
                if (bestDist[b] > worstVal) { worstVal = bestDist[b]; worstIndex = b; }
            }
            if (dist4 < worstVal) {
                bestDist[worstIndex] = dist4;
                bestIdx[worstIndex] = cand;
            }
        }
    }

    // Build neighbor list as 4D points
    var neighbors : array<vec4<f32>, 4>;
    for (var i : i32 = 0; i < 4; i = i + 1) {
        let bpos = bestIdx[i];
        if (bpos.x == -1) {
            neighbors[i] = point4;
        } else {
            let nCol2 = textureLoad(readTexture, bpos, 0).rgb;
            let nDepth2 = textureLoad(readDepthTexture, bpos, 0).r;
            let nHsv2 = rgb2hsv(nCol2);
            let nHue2 = nHsv2.x;
            let nSat2 = nHsv2.y;
            let nHueW2 = nHue2 * (1.0 + nSat2 * u.zoom_params.x);
            let nUV2 = vec2<f32>(f32(bpos.x) / dims.x, f32(bpos.y) / dims.y);
            neighbors[i] = vec4<f32>(nUV2.x, nUV2.y, nDepth2, nHueW2);
        }
    }

    // Estimate gradient
    var sumXX : f32 = 0.0;
    var sumYY : f32 = 0.0;
    var sumXY : f32 = 0.0;
    var sumXH : f32 = 0.0;
    var sumYH : f32 = 0.0;
    for (var i : i32 = 0; i < 4; i = i + 1) {
        var nUV = vec2<f32>(neighbors[i].x, neighbors[i].y);
        let nh = neighbors[i].w;
        var d = nUV - uv;
        sumXX = sumXX + d.x * d.x;
        sumYY = sumYY + d.y * d.y;
        sumXY = sumXY + d.x * d.y;
        sumXH = sumXH + d.x * nh;
        sumYH = sumYH + d.y * nh;
    }
    var grad : vec2<f32> = vec2<f32>(0.0, 0.0);
    let det = sumXX * sumYY - sumXY * sumXY;
    if (abs(det) > 1e-6) {
        let invDet = 1.0 / det;
        let a = (sumYY * sumXH - sumXY * sumYH) * invDet;
        var b = (-sumXY * sumXH + sumXX * sumYH) * invDet;
        grad = vec2<f32>(a, b);
    }

    // warp UV using hue gradient
    let warpStrength = clamp(u.zoom_params.y, 0.0, 1.0);
    let warpedUV = uv + grad * (warpStrength * 0.1);

    // sample previous frame feedback
    var prevColor = textureSampleLevel(dataTextureC, u_sampler, warpedUV, 0.0);

    // color debt for shadows
    var outColor = src;
    if (val < 0.2) {
        outColor = -abs(src);
    }

    // HDR tears
    let tearThreshold = mix(1.2, 3.0, clamp(u.zoom_config.x, 0.0, 1.0));
    if (maxRGB > tearThreshold) {
        let smear = normalize(grad + vec2<f32>(0.0001, 0.0)) * radiusScale * 0.02;
        let smearUV = uv + smear;
        let smearCol = textureSampleLevel(readTexture, u_sampler, smearUV, 0.0);
        outColor = mix(outColor, smearCol, 0.6);
        outColor = vec4<f32>(outColor.rgb + (maxRGB - 1.0) * 0.5, outColor.a);
    }

    // Combine with persistence
    let persistence = mix(0.0, 0.99, clamp(u.zoom_config.z, 0.0, 1.0));
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

    textureStore(writeTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(finalColor, finalAlpha));

    textureStore(writeDepthTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
