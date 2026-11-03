// ═══════════════════════════════════════════════════════════════════
//  ascii-decode
//  Category: stylize
//  Features: mouse-driven, upgraded-rgba, depth-aware
//  Upgraded: 2026-11-01 (was 2026-03-22)
//  Ideas: falling column head; cell gutter; decode rim
//  A packing: ACES display RGBA (C holds a little matrix green)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn get_luminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn character(uv: vec2<f32>, char_index: i32) -> f32 {
    var center = abs(uv - 0.5);
    var dist = length(uv - 0.5);
    var val = 0.0;

    // 0: Empty
    if (char_index == 0) {
        val = 0.0;
    }
    // 1: Dot
    else if (char_index == 1) {
        val = step(dist, 0.1);
    }
    // 2: Plus
    else if (char_index == 2) {
        val = step(max(center.x, center.y), 0.4) * step(min(center.x, center.y), 0.08); // Cross
    }
    // 3: Slash
    else if (char_index == 3) {
        val = step(abs((uv.x - 0.5) - (uv.y - 0.5)), 0.1) * step(abs(uv.x - 0.5), 0.4);
    }
    // 4: X
    else if (char_index == 4) {
        let d1 = abs((uv.x - 0.5) - (uv.y - 0.5));
        let d2 = abs((uv.x - 0.5) + (uv.y - 0.5));
        val = step(min(d1, d2), 0.08) * step(abs(uv.x - 0.5), 0.4);
    }
    // 5: Box
    else if (char_index >= 5) {
        val = step(max(center.x, center.y), 0.35); // Box outline?
        if (char_index > 5) {
             val = step(max(center.x, center.y), 0.4); // Solid block
        }
    }
    return val;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let gridSizeParam = 5.0 + u.zoom_params.x * 30.0; // 5 to 35
    let decodeRadius = u.zoom_params.y * 0.5; // 0 to 0.5 screen width
    let matrixSpeed = u.zoom_params.z;
    let globalMix = u.zoom_params.w; // 0 to 1

    let aspect = resolution.x / resolution.y;

    // Calculate Grid
    let gridUV = uv * vec2<f32>(resolution.x / gridSizeParam, resolution.y / gridSizeParam);
    let cellUV = fract(gridUV);
    let cellID = floor(gridUV);

    // Sample texture at center of cell for color/luminance
    let sampleUV = (cellID + 0.5) / vec2<f32>(resolution.x / gridSizeParam, resolution.y / gridSizeParam);
    var texColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let lum = get_luminance(texColor);

    // Quantize luminance to char index (0-6)
    var charIdx = i32(lum * 6.99);

    // ── Idea 1: falling column head ──────────────────────────────────
    // The column hash still chooses which columns rain. The highlight is a
    // short run of cells falling down that column. Matrix Speed still sets
    // the rate. A little of last frame's green holds behind the head.
    let time = u.config.x * (1.0 + matrixSpeed * 5.0);
    let colHash = fract(sin(cellID.x * 12.9898) * 43758.5453);
    let columnOn = step(0.9, colHash);
    let rows = max(resolution.y / gridSizeParam, 1.0);
    let headRow = fract(colHash + time * 0.15) * rows;
    let rowDelta = abs(cellID.y - headRow);
    let rowDist = min(rowDelta, abs(rows - rowDelta));
    let head = smoothstep(2.4, 0.0, rowDist);
    if (columnOn > 0.5 && head > 0.35) {
        charIdx = (charIdx + 1) % 7;
        texColor = texColor * (1.0 + head * 0.5);
    }

    let shape = character(cellUV, charIdx);

    // ── Idea 2: cell gutter ──────────────────────────────────────────
    // A margin at the cell edge, so the seven shapes sit in a terminal cell.
    let cellEdge = min(min(cellUV.x, 1.0 - cellUV.x), min(cellUV.y, 1.0 - cellUV.y));
    let gutter = smoothstep(0.0, 0.07, cellEdge);

    var matrixColor = vec3<f32>(0.0, 1.0, 0.2) * shape * lum * gutter;
    matrixColor += vec3<f32>(0.55, 1.0, 0.72) * shape * gutter * head * columnOn;

    // Mouse Interaction
    var mousePos = u.zoom_config.yz;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    var dist = length(distVec);

    // Decode Mask (smoothstep for soft edge)
    // Inside the radius decodeMask -> 0 (photo). Outside -> 1 (matrix).
    let decodeMask = smoothstep(decodeRadius, decodeRadius + 0.1, dist);

    let originalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // ── Idea 3: decode rim ───────────────────────────────────────────
    // Where the mask is mid-range, glyph ink sits on the photo instead of
    // a linear dissolve. Decode Radius still places that edge.
    let rim = smoothstep(0.02, 0.22, decodeMask) * smoothstep(0.72, 0.28, decodeMask);
    let punched = mix(originalColor, matrixColor, shape * gutter);
    var finalColor = mix(originalColor, matrixColor, decodeMask);
    finalColor = mix(finalColor, punched, rim);
    finalColor = mix(originalColor, finalColor, globalMix);

    let coord = vec2<i32>(global_id.xy);
    let prev = textureLoad(dataTextureC, coord, 0).rgb;
    let matrixGreen = prev.g * (1.0 - prev.r) * decodeMask * globalMix;
    finalColor += vec3<f32>(0.0, 0.22, 0.05) * matrixGreen * (0.25 + head * 0.75);
    finalColor = acesToneMap(max(finalColor, vec3<f32>(0.0)));

    let depth = textureLoad(readDepthTexture, coord, 0).r;
    let luma = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(mix(0.55, 1.0, luma) * mix(0.75, 1.0, depth) + shape * decodeMask * globalMix * 0.2, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
