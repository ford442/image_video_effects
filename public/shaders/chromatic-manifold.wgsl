// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

// Using the renderer's Uniforms layout (see AGENTS.md)
struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=tearIntensity, y=voidThreshold, z=temporalDecay, w=neighborRadius
    zoom_params: vec4<f32>,  // x=manifoldScale, y=curvatureStr, z=hueWeight, w=feedbackStr
    ripples: array<vec4<f32>, 50>,
};

// Utility: rgb->hsv
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    var p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
    var q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let h = abs((q.w - q.y) / (6.0 * d + 1e-10) + K.x);
    return vec3<f32>(h, d, q.x);
}

// Helper: compute a simple 4D neighbor set by sampling neighbors on the screen (approximate)
fn findNearestNeighborsApprox(point: vec4<f32>, texDims: vec2<f32>, k: u32) -> array<vec4<f32>, 4> {
    var neighbors: array<vec4<f32>, 4>;
    // We'll sample a 3x3 neighborhood around the point's uv in screen space to approximate close points
    let uv = vec2<f32>(point.x, point.y);
    let stepSize = 1.0 / texDims;
    var nIndex: u32 = 0u;
    for (var yOff: i32 = -1; yOff <= 1; yOff = yOff + 1) {
        for (var xOff: i32 = -1; xOff <= 1; xOff = xOff + 1) {
            if (nIndex >= k) { break; }
            let sampleUV = uv + vec2<f32>(f32(xOff), f32(yOff)) * stepSize;
            if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) { continue; }
            let dims = vec2<i32>(i32(texDims.x), i32(texDims.y));
            let px = vec2<i32>(i32(sampleUV.x * texDims.x), i32(sampleUV.y * texDims.y));
            let color = textureLoad(readTexture, px, 0).rgb;
            let depth = textureLoad(readDepthTexture, px, 0).r;
            let hsv = rgb2hsv(color);
            // make 4d point: u,v,depth,hue
            neighbors[nIndex] = vec4<f32>(sampleUV.x, sampleUV.y, depth, hsv.x);
            nIndex = nIndex + 1u;
        }
        if (nIndex >= k) { break; }
    }
    // If we have fewer neighbors, fill with the original point
    for (var i = nIndex; i < 4u; i = i + 1u) {
        neighbors[i] = point;
    }
    return neighbors;
}

fn computeTangentFrame(neighbors: array<vec4<f32>, 4>) -> array<vec4<f32>, 4> {
    let base = neighbors[0];
    let dx = neighbors[1] - base;
    let dy = neighbors[2] - base;
    let dh = neighbors[3] - base;
    return array<vec4<f32>, 4>(base, dx, dy, dh);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimsI = textureDimensions(readTexture);
    let dims = vec2<f32>(f32(dimsI.x), f32(dimsI.y));
    let gid = global_id.xy;
    if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) { return; }

    let uv = vec2<f32>(f32(gid.x) / dims.x, f32(gid.y) / dims.y);

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let hsv = rgb2hsv(src.rgb);
    let hue = hsv.x;
    let sat = hsv.y;
    let val = hsv.z;

    // curvature influence from depth
    let curvature = 1.0 + u.zoom_params.y * depthVal * 5.0;

    // 4D point
    let point4 = vec4<f32>(uv.x, uv.y, depthVal, hue * sat * curvature);

    // radius scale for HDR tears
    let maxRGB = max(max(src.r, src.g), src.b);
    var radiusScale = 1.0;
    if (maxRGB > 1.0) {
        radiusScale = (maxRGB - 1.0) * 10.0;
    }

    // Neighbor search: scan the window defined by the searchRadius and keep 4 nearest
    let searchRadius = 0.02 * radiusScale;
    let winSize = i32(ceil(searchRadius * u.config.z)); // searchRadius * imageWidth (approx)
    var bestIdx : array<vec2<i32>, 4>;
    var bestDist : array<f32, 4>;
    for (var i : i32 = 0; i < 4; i = i + 1) { bestDist[i] = 1e20; bestIdx[i] = vec2<i32>(-1, -1); }

    // perform scan
    for (var dy : i32 = -winSize; dy <= winSize; dy = dy + 1) {
        for (var dx : i32 = -winSize; dx <= winSize; dx = dx + 1) {
            let cand = vec2<i32>(i32(gid.x) + dx, i32(gid.y) + dy);
            if (cand.x < 0 || cand.y < 0 || cand.x >= i32(u.config.z) || cand.y >= i32(u.config.w)) { continue; }
            let nCol = textureLoad(readTexture, cand, 0).rgb;
            let nDepth = textureLoad(readDepthTexture, cand, 0).r;
            // neighbor hue
            let nHsv = rgb2hsv(nCol);
            let nHue = nHsv.x;
            let nSat = nHsv.y;
            let nHueW = nHue * (1.0 + nSat * u.zoom_params.x);

            let nUV = vec2<f32>(vec2<f32>(f32(cand.x) / dims.x, f32(cand.y) / dims.y));
            let duv = nUV - uv;
            let ddepth = nDepth - depthVal;
            let dhue  = nHueW - hue * (1.0 + sat * u.zoom_params.x);
            // curvature weighting
            let curvature = depthVal * depthVal * 5.0 * u.zoom_params.w; // param4 as curvature strength
            let weightedHue = dhue * curvature;
            let dist4 = dot(duv, duv) + ddepth * ddepth + weightedHue * weightedHue;

            // insert candidate into best-4 if better than worst
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
            neighbors[i] = point4; // fallback
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

    // Estimate gradient by fitting plane hue = a*x + b*y + c
    var sumXX : f32 = 0.0;
    var sumYY : f32 = 0.0;
    var sumXY : f32 = 0.0;
    var sumXH : f32 = 0.0;
    var sumYH : f32 = 0.0;
    for (var i : i32 = 0; i < 4; i = i + 1) {
        let nUV = vec2<f32>(neighbors[i].x, neighbors[i].y);
        let nh = neighbors[i].w;
        let d = nUV - uv;
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
        let b = (-sumXY * sumXH + sumXX * sumYH) * invDet;
        grad = vec2<f32>(a, b);
    }

    // warp UV using hue gradient and warpStrength (zoom_params.y)
    let warpStrength = clamp(u.zoom_params.y, 0.0, 1.0);
    let warpedUV = uv + grad * (warpStrength * 0.1);

    // sample previous frame feedback from dataTextureC
    var prevColor = textureSampleLevel(dataTextureC, u_sampler, warpedUV, 0.0);

    // color debt for shadows
    var outColor = src;
    if (val < 0.2) {
        outColor = -abs(src); // subtractive color debt
    }

    // HDR tears: if maxRGB>1 and threshold exceed, smear color along tangent
    let tearThreshold = mix(1.2, 3.0, clamp(u.zoom_config.x, 0.0, 1.0));
    if (maxRGB > tearThreshold) {
        // smear along gradient direction
        let smear = normalize(grad + vec2<f32>(0.0001, 0.0)) * radiusScale * 0.02;
        let smearUV = uv + smear;
        let smearCol = textureSampleLevel(readTexture, u_sampler, smearUV, 0.0);
        outColor = mix(outColor, smearCol, 0.6);
        // add localized HDR bloom
        outColor = vec4<f32>(outColor.rgb + (maxRGB - 1.0) * 0.5, outColor.a);
    }

    // Combine with persistence (feedback): 90% previous frame
    let persistence = mix(0.0, 0.99, clamp(u.zoom_config.z, 0.0, 1.0));
    let combined = mix(outColor, prevColor, persistence);

    // Clamp a bit, but allow negatives
    // Write to output (rgba32float)
    textureStore(writeTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(combined.rgb, 1.0));

    // pass depth unchanged
    textureStore(writeDepthTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
