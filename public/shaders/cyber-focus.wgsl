// ═══════════════════════════════════════════════════════════════════
//  Cyber Focus
//  Category: interactive-mouse
//  Mouse-tracked focus aperture; everything outside it gets blocky glitch
//  offset, chromatic aberration, and box blur scaled by distance.
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-11-21
//  Ideas: block-DCT quantization (§12.2B) — 8-px macroblocks keep DC+3 AC luma coefficients and DC-only chroma, luma follows the codec while chroma is only lightly replaced so the aberration survives, Q grows with distance from the aperture, scan packets refresh it; luma-weighted defocus (bokeh pooling, energy-normalised)
//  A packing: display RGBA pass-through (no ACES: the in-focus pool must return the source pixel)
//  Rescues: texel-centre uv (HEAD sampled texel corners, so the "crisp" pool was a half-pixel blur)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// HEAD's 20×20 block-glitch gate, lifted out unchanged so the codec macroblock
// can evaluate the same offset at its own block centre.
fn glitchOffset(p: vec2<f32>, glitchIntensity: f32, time: f32, mids: f32, treble: f32, packet: f32) -> vec2<f32> {
    let blockId = floor(p * 20.0);
    let blockSeed = hash21(blockId);
    let noise = 0.5 + 0.5 * sin(time * (4.0 + mids * 3.0) + blockSeed * 6.28318);
    let direction = vec2<f32>(hash21(blockId), hash21(blockId + 1.0)) - 0.5;
    return select(vec2<f32>(0.0), direction * (0.06 + packet * 0.06 + treble * 0.02), noise < glitchIntensity * 0.2);
}


@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = (vec2<f32>(global_id.xy) + 0.5) / resolution; // texel centre (rescue)
    var mousePos = u.zoom_config.yz;
    let heldFocus = step(0.5, u.zoom_config.w);
    let aspectRatio = resolution.x / resolution.y;
    let time = u.config.x;

    // Mouse is 0-1. UV is 0-1.
    // Distance needs aspect ratio correction if we want circular radius.
    // However, if we don't correct, it matches the screen shape (oval).
    // Let's correct for circular radius.
    let distVec = (uv - mousePos) * vec2<f32>(aspectRatio, 1.0);
    let dist = length(distVec);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Bass pulses the focus aperture, mids drive glitch/aberration
    let radius = (u.zoom_params.x * 0.5 + 0.1) * (1.0 + bass * 0.35); // 0.1 to 0.6
    let blurStrength = u.zoom_params.y * 10.0;
    let glitchIntensity = u.zoom_params.z * (1.0 + mids * 0.5);
    let aberration = u.zoom_params.w * 0.05 * (1.0 + mids * 0.4);

    var clickClarity = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.8) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspectRatio, 1.0);
            clickClarity += smoothstep(0.025, 0.0, abs(length(delta) - age * 0.48)) * exp(-age * 1.5);
        }
    }

    // Smooth focus aperture plus fast scanner packets and click clarity fronts.
    let activeRadius = radius * (1.0 + heldFocus * 0.35);
    let baseFocusMask = smoothstep(activeRadius, activeRadius + 0.1, dist);
    let scanPacket = pow(max(0.0, sin(uv.y * 75.0 - time * 15.0)), 14.0) * baseFocusMask;
    let focusMask = clamp(baseFocusMask * (1.0 - clickClarity * 0.9) - scanPacket * 0.18, 0.0, 1.0);

    var finalColor = vec4<f32>(0.0);

    if (focusMask < 0.01) {
        // Inside focus - crisp
        finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    } else {
        // Outside focus - process

        // 1. Glitch Offset (Blocky)
        let offset = glitchOffset(uv, glitchIntensity, time, mids, treble, scanPacket);

        // 2. Chromatic Aberration + Blur
        // We will sample a few points and average them
        var r_acc = 0.0;
        var g_acc = 0.0;
        var b_acc = 0.0;
        var weight_acc = 0.0;

        let blurSize = blurStrength * focusMask / resolution;

        // Simple 3x3 box blur with offset
        for (var i = -1.0; i <= 1.0; i += 1.0) {
            for (var j = -1.0; j <= 1.0; j += 1.0) {
                let jitter = vec2<f32>(i, j);
                let sampleUV = clamp(uv + offset + jitter * blurSize, vec2<f32>(0.0), vec2<f32>(1.0));

                // Chromatic Aberration: R and B are offset
                let r = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(aberration * focusMask, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
                let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
                let b = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(aberration * focusMask, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

                // ── Idea 2: luma-weighted defocus (bokeh pooling) ──────────
                // Real defocus is radiance-weighted: highlights dominate their
                // neighbourhood. Weights are normalised below, so energy is
                // moved, not added; the uniform box is the w = 1 limit.
                let tapLuma = dot(vec3<f32>(r, g, b), vec3<f32>(0.299, 0.587, 0.114));
                let w = 1.0 + 3.0 * smoothstep(0.55, 1.0, tapLuma) * focusMask;
                r_acc += r * w;
                g_acc += g * w;
                b_acc += b * w;
                weight_acc += w;
            }
        }

        // Blend based on mask (soft edge for the focus area)
        let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

        // Defocused regions thin out — alpha falls off with the focus mask
        let defocusAlpha = original.a * (1.0 - focusMask * 0.35);
        finalColor = vec4<f32>(r_acc / weight_acc, g_acc / weight_acc, b_acc / weight_acc, defocusAlpha);

        // ── Idea 1: block-DCT quantization (§12.2B) ─────────────────
        // The glitch above is a corrupt block stream; a real one also bands
        // *inside* its blocks. Each 8-px macroblock (scaled with resolution)
        // keeps four luma coefficients (DC, H, V, diagonal — fitted to four
        // quadrant taps) quantized q = round(x / Q) · Q with Q growing with
        // frequency, and chroma at DC only (4:2:0-style block colour). Q rises
        // with distance from the aperture (bitrate starves) and per block;
        // scan packets are keyframe refreshes that drop Q along their band (the pixel's own offset and packet are reused, so no second glitch evaluation).
        let codecGate = smoothstep(0.0, 0.3, glitchIntensity);
        if (codecGate > 0.0) {
            let blockPx = 8.0 * max(1.0, floor(resolution.y / 540.0));
            let pxPos = vec2<f32>(global_id.xy);
            let blk = floor(pxPos / blockPx);
            let fb = (pxPos + 0.5) / blockPx - blk;
            let bCentrePx = (blk + 0.5) * blockPx;
            let bUV = bCentrePx / resolution;
            let bMask = smoothstep(activeRadius, activeRadius + 0.1, length((bUV - mousePos) * vec2<f32>(aspectRatio, 1.0)));

            let qo = blockPx * 0.25;
            let tA = textureSampleLevel(readTexture, u_sampler, clamp((bCentrePx + vec2<f32>(-qo, -qo)) / resolution + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
            let tB = textureSampleLevel(readTexture, u_sampler, clamp((bCentrePx + vec2<f32>( qo, -qo)) / resolution + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
            let tC = textureSampleLevel(readTexture, u_sampler, clamp((bCentrePx + vec2<f32>(-qo,  qo)) / resolution + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
            let tD = textureSampleLevel(readTexture, u_sampler, clamp((bCentrePx + vec2<f32>( qo,  qo)) / resolution + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
            let lw = vec3<f32>(0.299, 0.587, 0.114);
            let yA = dot(tA, lw); let yB = dot(tB, lw); let yC = dot(tC, lw); let yD = dot(tD, lw);

            let blockQ = mix(0.5, 2.5, hash21(blk + vec2<f32>(7.3, 1.7)));
            let qDC = (0.015 + 0.12 * glitchIntensity * bMask) * blockQ * (1.0 - 0.85 * scanPacket);
            let dcC = 0.25 * (yA + yB + yC + yD);
            let acH = 0.25 * (yB + yD - yA - yC);
            let acV = 0.25 * (yC + yD - yA - yB);
            let acD = 0.25 * (yA + yD - yB - yC);
            let qDCv = round(dcC / qDC) * qDC;
            let qH = round(acH / (3.0 * qDC)) * 3.0 * qDC;
            let qV = round(acV / (3.0 * qDC)) * 3.0 * qDC;
            let qD = round(acD / (5.0 * qDC)) * 5.0 * qDC;
            // cosine basis normalised to ±1 at the quadrant taps (f = 0.25 / 0.75):
            // -cos(π f)·√2 = √2·sin(π t / 2), t = 2f − 1, as an odd polynomial.
            let tx = 2.0 * fb.x - 1.0;
            let ty = 2.0 * fb.y - 1.0;
            let hx = 1.41421356 * tx * (1.5707963 - tx * tx * (0.6459641 - tx * tx * 0.0796926));
            let hy = 1.41421356 * ty * (1.5707963 - ty * ty * (0.6459641 - ty * ty * 0.0796926));
            let yRec = qDCv + qH * hx + qV * hy + qD * hx * hy;
            let chromaMean = 0.25 * ((tA - yA) + (tB - yB) + (tC - yC) + (tD - yD));
            let qC = 1.5 * qDC;
            let chromaQ = round(chromaMean / qC) * qC;
            // Luma follows the codec strongly, chroma only lightly: the R/B
            // fringe above lives in chroma, so the existing aberration survives.
            let blur = finalColor.rgb;
            let yBlur = dot(blur, lw);
            finalColor = vec4<f32>(
                max(blur + codecGate * (0.6 * vec3<f32>(yRec - yBlur) + 0.3 * (chromaQ - (blur - yBlur))), vec3<f32>(0.0)),
                finalColor.a
            );
        }

        finalColor = mix(original, finalColor, focusMask);
    }

    finalColor = vec4<f32>(
        clamp(finalColor.rgb + vec3<f32>(0.05, 0.35, 0.55) * scanPacket * (0.2 + treble * 0.3), vec3<f32>(0.0), vec3<f32>(4.0)),
        finalColor.a
    );

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalColor);

    // Pass-through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
