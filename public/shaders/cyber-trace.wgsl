// ═══════════════════════════════════════════════════════════════════
//  Cyber Trace — Batch 59
//  Spring brush, capped click blooms, exact C history, ACES composite,
//  semantic alpha, extraBuffer[133..138] at (0,0) only.
//  Upgraded: 2026-10-27
//  Ideas: velocity-oriented arc stamp; treble circuit sparks; paint-tangent arc (§12.2C); etched groove and via dashes
//  A packing: history RGB; A.a is brush coverage
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hue2rgb(p: f32, q: f32, t: f32) -> f32 {
    var tc = t;
    if (tc < 0.0) { tc = tc + 1.0; }
    if (tc > 1.0) { tc = tc - 1.0; }
    if (tc < 1.0 / 6.0) { return p + (q - p) * 6.0 * tc; }
    if (tc < 1.0 / 2.0) { return q; }
    if (tc < 2.0 / 3.0) { return p + (q - p) * (2.0 / 3.0 - tc) * 6.0; }
    return p;
}

fn hslToRgb(h: f32, s: f32, l: f32) -> vec3<f32> {
    if (s == 0.0) {
        return vec3<f32>(l);
    }
    var q: f32;
    if (l < 0.5) {
        q = l * (1.0 + s);
    } else {
        q = l + s - l * s;
    }
    let p = 2.0 * l - q;
    return vec3<f32>(hue2rgb(p, q, h + 1.0 / 3.0), hue2rgb(p, q, h), hue2rgb(p, q, h - 1.0 / 3.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let decaySpeed = u.zoom_params.x;
    let glowIntensity = u.zoom_params.y;
    let hueShift = u.zoom_params.z;
    let brushSize = u.zoom_params.w * select(1.0, 0.75, u.zoom_config.w > 0.5);
    let time = u.config.x;
    let aspect = res.x / res.y;
    let rawMouse = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // extraBuffer is cleared every frame, so the spring velocity was always
    // zero and the arc collapsed to a disc. The direction comes from the
    // trail already stored in C.
    let mousePos = rawMouse;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let toPixel = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(toPixel);

    // Idea 1: arc along the paint tangent (§12.2C). The gradient of the
    // stored trail points across the stroke; the capsule runs along it.
    let resI = vec2<i32>(max(i32(res.x) - 1, 0), max(i32(res.y) - 1, 0));
    let hL = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(-1, 0), vec2<i32>(0), resI), 0);
    let hR = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(1, 0), vec2<i32>(0), resI), 0);
    let hU = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(0, -1), vec2<i32>(0), resI), 0);
    let hD = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(0, 1), vec2<i32>(0), resI), 0);
    let paintGrad = vec2<f32>(luma(hR.rgb) - luma(hL.rgb), luma(hD.rgb) - luma(hU.rgb));
    let tangent = vec2<f32>(-paintGrad.y, paintGrad.x);
    let velMag = length(tangent);
    let arcDir = select(vec2<f32>(1.0, 0.0), tangent / max(velMag, 0.0001), velMag > 0.0001);
    let arcLen = clamp(velMag * 0.05, 0.0, brushSize * 2.5);
    let segVec = -arcDir * arcLen;
    let tSeg = clamp(dot(toPixel, segVec) / max(dot(segVec, segVec), 1e-6), 0.0, 1.0);
    let closest = segVec * tSeg;
    let capsuleDist = length(toPixel - closest);
    var brush = smoothstep(brushSize, brushSize * 0.5, capsuleDist) * select(0.5, 1.0, isMouseDown);

    // ── Idea 2: via dashes on the brush rim.
    let viaAngle = atan2(toPixel.y, toPixel.x);
    let viaDash = step(0.45, fract(viaAngle * 1.2732395));
    let viaRim = smoothstep(brushSize * 1.15, brushSize * 0.72, capsuleDist) * (1.0 - smoothstep(brushSize * 0.72, brushSize * 0.35, capsuleDist));
    brush = brush + viaDash * viaRim * 0.65;

    // Idea 2: treble circuit sparks — above a treble threshold, small ticks
    // branch perpendicular off the arc, hashed by a moving grid cell so they
    // flicker like circuit-board traces and decay with the rest of history.
    let sparkPerp = vec2<f32>(-arcDir.y, arcDir.x);
    let sparkCell = floor(uv * 180.0 + time * 2.0);
    let sparkHash = fract(sin(dot(sparkCell, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let sparkActive = step(0.982, sparkHash) * clamp((treble - 0.45) * 3.0, 0.0, 1.0);
    let sparkCenter = closest + sparkPerp * brushSize * (sparkHash - 0.5) * 4.0;
    let sparkDist = length(toPixel - sparkCenter);
    let sparkStamp = smoothstep(brushSize * 0.4, 0.0, sparkDist) * sparkActive * smoothstep(brushSize * 4.0, brushSize * 0.5, dist);
    brush = brush + sparkStamp;

    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age < 0.0 || age > 1.5) { continue; }
        let stampDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
        let stampRadius = brushSize * 1.5;
        brush += smoothstep(stampRadius, stampRadius * 0.5, stampDist) * (1.0 - clamp(age / 1.5, 0.0, 1.0));
    }

    let historyColor = textureLoad(dataTextureC, pixel, 0);
    let colorTick = time * 0.2 * (1.0 + mids * 0.8) + hueShift;
    let drawColor = hslToRgb(fract(colorTick), 1.0, 0.5);
    let newHistory = clamp(historyColor.rgb * decaySpeed + drawColor * brush, vec3<f32>(0.0), vec3<f32>(2.0));

    textureStore(dataTextureA, pixel, vec4<f32>(newHistory, clamp(brush, 0.0, 1.0)));

    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    // plasmaBuffer[1..] is never uploaded. The shimmer is a phase of the live mids.
    let bandShimmer = mids * (0.5 + 0.5 * sin(uv.x * 24.0 + time * 1.7));
    let audioGlow = glowIntensity * (1.0 + bass * 0.5) * (1.0 + bandShimmer) * select(1.0, 1.2, isMouseDown);

    // ── Idea 2 continued: the photo darkens under the trail.
    let groove = clamp(luma(newHistory) * 0.45, 0.0, 0.55);
    let rawComposite = inputColor * (1.0 - groove) + newHistory * audioGlow;
    var finalColor = acesToneMap(rawComposite * (0.92 + mids * 0.08));

    let trailStrength = clamp(luma(newHistory) * audioGlow * 0.5 + brush * 0.4, 0.0, 1.0);
    let alpha = clamp(0.35 + trailStrength * 0.55 + bass * 0.05, 0.0, 0.98);

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
