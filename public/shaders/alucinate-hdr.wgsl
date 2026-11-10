// ═══════════════════════════════════════════════════════════════════
//  alucinate-hdr
//  Category: advanced-hybrid
//  Features: ai-vj-conductor, music-reactive-glyphs, living-spectrogram, hdr-atmosphere, meta-visualizer, upgraded-rgba
//  Complexity: Medium-High
//  Chunks From: alucinate.wgsl, alpha-hdr-bloom-chain.wgsl + new glyph/spectrogram system
//  Created: 2026-04-18
//  Updated: 2026-05-31
//  By: Grok (AI VJ conductor's baton + living spectrogram upgrade)
//  Upgraded: 2026-11-09
//  Ideas: segmented LED-ladder spectrum bars with a red clip zone (native spectrum meter); beat-locked warp (bass breathes warp amplitude, treble opens the RGB split)
//  A packing: raw HDR (pre-tonemap, incl. bloom) in A, a = overexposure — unread by this shader (no history); final display premultiplied
// ═══════════════════════════════════════════════════════════════════
//  When Alucinate (AI VJ) mode is active, this acts as a visual "conductor's
//  baton" — elegant, minimal music-reactive glyphs and spectrogram elements
//  that represent the current vibe stack. The psychedelic warp + HDR bloom
//  provides a rich atmospheric underlayer.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Soft-knee bright extract, hue-preserving: the fraction (0..1) of a colour bright enough to
// bloom. HEAD thresholded at `max(rgb) - 1.0`, which an LDR source never exceeds, so the
// Atmosphere Bloom / Bloom Intensity sliders did nothing; the knee now sits in display range
// (and still behaves on HDR input: fraction -> 1 - knee/max).
fn glowFraction(c: vec3<f32>) -> f32 {
    let m = max(c.r, max(c.g, c.b));
    let kneeT = 0.55;
    let kneeW = 0.2;
    let rq = clamp(m - kneeT + kneeW, 0.0, 2.0 * kneeW);
    let soft = rq * rq / (4.0 * kneeW);
    let over = max(soft, m - kneeT);
    return over / max(m, 1e-4);
}

// ═══ Living Spectrogram / Conductor Glyphs (AI VJ meta layer) ═══
fn vibeGlyphs(uv: vec2<f32>, bass: f32, mids: f32, treble: f32, mouse: vec2<f32>, mouseDown: f32) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    let centerY = 0.5;
    let conductor = smoothstep(0.25, 0.0, distance(uv, mouse)) * (0.6 + mouseDown * 0.8);

    // ladder geometry (shared by the 6 bars; symmetric about the centre line)
    let segH = 0.024;
    let yy = abs(uv.y - centerY);
    let segPos = yy / segH;
    let segFrac = fract(segPos);
    let segCenter = (floor(segPos) + 0.5) * segH;
    let segMask = smoothstep(0.0, 0.14, segFrac) * smoothstep(1.0, 0.86, segFrac);

    // 6 elegant vertical bands (stylized frequency response)
    for (var i = 0; i < 6; i++) {
        let fi = f32(i);
        let bandX = 0.18 + fi * 0.13;
        let distX = abs(uv.x - bandX);
        let width = 0.018 + conductor * 0.012;

        // Heights driven by different plasma bands with musical feel
        let h = select(bass, mids, i > 1);
        let hh = select(h, treble, i > 3);
        let height = 0.08 + hh * (0.28 + fi * 0.015);

        // ── Idea 1: segmented LED-ladder bars with a red clip zone ─────────
        // A spectrum meter is a ladder of lit segments with hairline gaps, and its top
        // segments go red when the band clips. Bar position, width, gradient and height law
        // are unchanged; the old smooth falloff survives as a faint under-glow.
        let xProfile = smoothstep(width, 0.0, distX);
        let lit = 1.0 - smoothstep(height - 0.25 * segH, height + 0.25 * segH, segCenter);
        let inBar = xProfile * (lit * segMask + 0.10 * smoothstep(height, 0.0, yy));

        // Elegant gold-to-cyan gradient per band, stronger on conductor
        var bandCol = mix(vec3<f32>(0.95, 0.75, 0.35), vec3<f32>(0.3, 0.85, 0.95), fi / 5.5);
        let clipZone = smoothstep(0.70, 0.88, hh) * smoothstep(height - 2.2 * segH, height - 1.2 * segH, segCenter);
        bandCol = mix(bandCol, vec3<f32>(1.0, 0.22, 0.18), clipZone);
        col += bandCol * inBar * (0.7 + conductor * 1.2);
    }

    // Subtle horizontal "beat line" that pulses with bass
    let beatLine = smoothstep(0.012, 0.0, abs(uv.y - centerY)) * bass * 1.4;
    col += vec3<f32>(0.6, 0.9, 1.0) * beatLine;

    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.5;

    // audio (plasmaBuffer[0].xyz only) — hoisted so the atmosphere warp can follow the music too
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse_uv = u.zoom_config.yz;
    let mouse_active = u.zoom_config.w > 0.0;
    let dist_to_mouse = distance(uv, mouse_uv);
    let mouse_effect = smoothstep(0.3, 0.0, dist_to_mouse) * f32(mouse_active);

    // ═══ Alucinate Warp ═══
    let warp_freq = mix(4.0, 10.0, mouse_effect);
    // ── Idea 2: beat-locked warp ───────────────────────────────────────
    // The atmosphere used to ignore the music its own glyphs display. Bass now breathes the
    // warp amplitude; treble (below) opens the RGB split. Mouse behaviour is unchanged.
    let warp_amp = mix(0.02, 0.1, mouse_effect) * (1.0 + clamp(bass, 0.0, 1.0));
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let radius = distance(uv, vec2<f32>(0.5));
    let warp_offset_x = sin(uv.y * warp_freq - time) * cos(radius * 10.0 + time) * warp_amp;
    let warp_offset_y = cos(uv.x * warp_freq + time) * sin(radius * 10.0 - time) * warp_amp;
    let warped_uv = uv + vec2<f32>(warp_offset_x, warp_offset_y);

    let shift_amount = mix(0.005, 0.02, mouse_effect) * sin(time * 2.0) * (1.0 + 0.5 * clamp(treble, 0.0, 1.0));
    let r = textureSampleLevel(readTexture, u_sampler, warped_uv + vec2<f32>(shift_amount, shift_amount), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, warped_uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, warped_uv - vec2<f32>(shift_amount, shift_amount), 0.0).b;
    var warpedColor = vec3<f32>(r, g, b);

    // ═══ HDR Bloom Chain ═══
    let bloomRadius = mix(0.01, 0.08, u.zoom_params.x);
    let bloomIntensity = u.zoom_params.y * 2.0;
    let bloomSamples = 16;

    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;

    // Static per-pixel ring rotation (interleaved-gradient noise, no time term): the 16
    // discrete taps dissolve into fine noise instead of 16 ghost blobs around a small
    // highlight. Same tap count; no frame-to-frame flicker.
    let ringRot = 6.283185307 * fract(52.9829189 * fract(dot(vec2<f32>(gid.xy), vec2<f32>(0.06711056, 0.00583715))));

    for (var i = 0; i < bloomSamples; i = i + 1) {
        let a = f32(i) * 6.283185307 / f32(bloomSamples) + ringRot;
        let rad = bloomRadius * (1.0 + f32(i % 4) * 0.5);
        let offset = vec2<f32>(cos(a), sin(a)) * rad;
        let sampleUV = clamp(warped_uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
        let neighbor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let weight = exp(-f32(i % 4) * 0.5);
        bloom += neighbor * glowFraction(neighbor) * weight;
        totalWeight += weight;
    }

    // ring mean of the hue-preserving glow (halo follows how much bright light is around)
    bloom = bloom / max(totalWeight, 1e-4) * (bloomIntensity * 0.8);

    // Mouse bloom boost
    let mouseGlow = smoothstep(0.2, 0.0, dist_to_mouse) * u.zoom_config.w * 2.0;
    bloom += vec3<f32>(mouseGlow * 0.5, mouseGlow * 0.3, mouseGlow * 0.1);

    // Ripple flash
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time * 2.0 - ripple.z;
        if (age < 0.5 && rDist < 0.1) {
            let flash = smoothstep(0.1, 0.0, rDist) * max(0.0, 1.0 - age * 2.0);
            bloom += vec3<f32>(flash * 2.0, flash * 1.5, flash);
        }
    }

    // clamp >= 0 before ACES (the catalog fit maps negative input to bright)
    let hdrColor = max(warpedColor + bloom, vec3<f32>(0.0));
    let toneMapExp = mix(0.5, 2.0, u.zoom_params.z);
    let ldrColor = toneMapACES(hdrColor * toneMapExp);

    // === AI VJ CONDUCTOR LAYER (the high-signal meta upgrade) ===
    let mouseDown = u.zoom_config.w;

    let glyphs = vibeGlyphs(uv, bass, mids, treble, mouse_uv, mouseDown);

    // Blend the atmospheric HDR warp/bloom underneath elegant glyphs
    let atmosphere = ldrColor * (0.65 + mouse_effect * 0.25);
    // R2: Glyph Prominence (zoom_params.w) was never read; the gain was the constant 0.85.
    // 0.85 * (p / 0.7) reproduces HEAD exactly at the saved default p = 0.7.
    let glyphGain = 0.85 * (u.zoom_params.w / 0.7);
    let finalColor = atmosphere + glyphs * (glyphGain + mouseDown * 0.4);

    // Meaningful alpha: higher when glyphs are prominent or during strong musical moments
    let glyphStrength = length(glyphs);
    let musicalEnergy = bass * 0.3 + mids * 0.4 + treble * 0.5;
    let alpha = clamp(0.55 + glyphStrength * 0.9 + musicalEnergy * 0.6 + mouseDown * 0.25, 0.0, 1.15);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let finalAlpha = mix(alpha * 0.75, alpha, depth);

    // Premultiplied for clean layering over the actual AI VJ output
    let a = clamp(finalAlpha, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(finalColor * a, a));

    // Store HDR for downstream use if needed
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, max(0.0, max(hdrColor.r, max(hdrColor.g, hdrColor.b)) - 1.0)));

    let depthOut = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
