// ═══════════════════════════════════════════════════════════════════
//  Retro Phosphor HDR
//  Category: advanced-hybrid
//  Features: crt-phosphor, hdr-bloom, temporal-persistence, audio-reactive, upgraded-rgba
//  Complexity: High
//  Chunks From: retro_phosphor_dream.wgsl, alpha-hdr-bloom-chain.wgsl
//  Created: 2026-04-18
//  By: Agent CB-13 — Retro & Glitch Enhancer
//  Upgraded: 2026-11-09
//  Ideas: energy-conserving faceplate bloom (§12.2F); rolling hum bar (native CRT); per-pixel ring rotation dissolves the 16 bloom taps
//  A packing: raw HDR phosphor light after persistence (pre-grain/vignette/boost/bloom/flash), a = overexposure; C read as colour history
// ═══════════════════════════════════════════════════════════════════
//  Authentic CRT phosphor simulation with full HDR bloom chain.
//  Phosphor persistence, barrel distortion, and scanlines are enhanced
//  by HDR bloom with ACES tone mapping for dramatic glowing phosphors.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn barrelDistort(uv: vec2<f32>, strength: f32) -> vec2<f32> {
    let centered = uv - 0.5;
    let r2 = dot(centered, centered);
    let distortion = 1.0 + strength * r2;
    return centered * distortion + 0.5;
}

fn phosphorTriad(uv: vec2<f32>, triadSize: f32) -> vec3<f32> {
    let x = uv.x / triadSize;
    let triadX = fract(x);
    if (triadX < 0.33) { return vec3<f32>(1.0, 0.0, 0.0); }
    else if (triadX < 0.66) { return vec3<f32>(0.0, 1.0, 0.0); }
    else { return vec3<f32>(0.0, 0.0, 1.0); }
}

fn scanlines(uv: vec2<f32>, intensity: f32, time: f32) -> f32 {
    let scanline = sin(uv.y * 480.0 * PI + time * 0.1) * 0.5 + 0.5;
    return 1.0 - (scanline * intensity);
}

fn interlaceFlicker(uv: vec2<f32>, time: f32, intensity: f32) -> f32 {
    let field = floor(time * 30.0) % 2.0;
    let line = floor(uv.y * 240.0) % 2.0;
    let flicker = select(1.0, 0.85, line == field);
    return 1.0 - (1.0 - flicker) * intensity;
}

fn chromaticAberration(uv: vec2<f32>, strength: f32) -> vec3<f32> {
    let centered = uv - 0.5;
    let r = length(centered);
    let aberration = strength * r * r;
    // R3: normalize(0) is NaN at the exact centre pixel
    let radial = normalize(centered + vec2<f32>(1e-4));
    let rUV = uv + radial * aberration;
    let gUV = uv;
    let bUV = uv - radial * aberration;
    return vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
        textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g,
        textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
    );
}

// Soft-knee bright extract, hue-preserving: the fraction (0..1) of a colour that is bright
// enough to glow. The knee sits in DISPLAY range (R1) — the old `max(rgb) - 1.0` threshold
// can never fire on an LDR photo, so the HDR Bloom slider was dead. HDR input still works
// (fraction -> 1 - knee/max).
fn glowFraction(c: vec3<f32>) -> f32 {
    let m = max(c.r, max(c.g, c.b));
    let kneeT = 0.55;
    let kneeW = 0.2;
    let rq = clamp(m - kneeT + kneeW, 0.0, 2.0 * kneeW);
    let soft = rq * rq / (4.0 * kneeW);
    let over = max(soft, m - kneeT);
    return over / max(m, 1e-4);
}

// ACES tone mapping
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let coord = vec2<i32>(global_id.xy);

    let curvature = u.zoom_params.x * 0.3;
    let phosphorSize = 0.001 + u.zoom_params.y * 0.003;
    let scanlineIntensity = u.zoom_params.z * 0.5;
    let bloomIntensity = u.zoom_params.w * 2.0;

    // R2: HEAD read zoom_config.w (the MOUSE-DOWN flag) as "audio"; bass is plasmaBuffer[0].x
    let audioPulse = clamp(plasmaBuffer[0].x, 0.0, 1.0);

    // Barrel distortion
    let distortedUV = barrelDistort(uv, curvature);

    // Chromatic aberration
    var color = chromaticAberration(distortedUV, curvature * 0.5);
    // how much of this pixel's source light is bright enough to leave the core as halo
    let coreGlow = glowFraction(color);
    let srcPeak = max(color.r, max(color.g, color.b));

    // Phosphor triad
    let triad = phosphorTriad(uv, phosphorSize);
    color *= 0.7 + triad * 0.6;

    // Scanlines
    color *= scanlines(uv, scanlineIntensity, time);

    // Interlaced flicker
    color *= interlaceFlicker(uv, time, 0.2);

    // Temporal phosphor persistence. C is read as COLOUR history and A stores only the
    // persisted phosphor light — grain, vignette, HDR boost, flash and halo are display-side.
    // (HEAD stored them all, so a loud bass / held mouse compounded x = 0.95 * 1.5 * x.)
    let prevFrame = textureLoad(dataTextureC, coord, 0).rgb;
    color = max(color, prevFrame * (0.85 + audioPulse * 0.1));
    let phosphorState = color;

    // Film grain
    color *= hash(uv + time * 0.1) * 0.1 + 0.95;

    // Vignette
    let edgeDist = length(uv - 0.5) * 1.4;
    color *= 1.0 - edgeDist * edgeDist * 0.5;

    // HDR boost
    color = color * (1.0 + audioPulse * 0.5);

    // ── Idea 2: rolling hum bar (native CRT) ────────────────────────────
    // Power-supply hum beating against the field rate leaves ONE soft-edged dark band that
    // rolls slowly up the tube (0.13 Hz, one screen per ~7.7 s). Exactly one band is always
    // on screen (period = 1 screen), its core is -18 %, FWHM ~0.2 screen, and the rest of
    // the frame is lifted by 4 % so the mean is unchanged (mean of the profile = 0.18).
    // Display-side (after persistence) so the trail cannot fill the band back in, and the
    // bar is not stored in A.
    let humDist = abs(fract(uv.y + time * 0.13) - 0.5);
    let humBar = 1.0 - smoothstep(0.04, 0.14, humDist);
    let humMod = 1.0 - 0.22 * (humBar - 0.18);
    color *= humMod;

    // ── Ripple flash (unchanged look; display-side only) ────────────────
    var flashAdd = vec3<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 0.5 && rDist < 0.1) {
            let flash = smoothstep(0.1, 0.0, rDist) * max(0.0, 1.0 - age * 2.0);
            flashAdd += vec3<f32>(flash * 2.0, flash * 1.5, flash);
        }
    }

    // ═══ HDR BLOOM CHAIN ═══
    // ── Idea 1: energy-conserving faceplate bloom (§12.2F) ──────────────
    // Same 16-tap ring as before. Each tap now contributes its hue-preserving soft-knee
    // glow fraction, normalised by tap weight (halo magnitude follows how much bright
    // light is in the ring, not a binary on/off), and the bright core pays for what the
    // halo gains: energy moved, not invented.
    let bloomRadius = 0.05;
    let bloomSamples = 16;
    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;

    // Static per-pixel ring rotation (interleaved-gradient noise, no time term) so the 16
    // discrete taps dissolve into fine noise instead of 16 ghost blobs around a small
    // highlight. Same tap count; no frame-to-frame flicker.
    let ringRot = 6.283185307 * fract(52.9829189 * fract(dot(vec2<f32>(global_id.xy), vec2<f32>(0.06711056, 0.00583715))));

    for (var i = 0; i < bloomSamples; i = i + 1) {
        let angle = f32(i) * 6.283185307 / f32(bloomSamples) + ringRot;
        let radius = bloomRadius * (1.0 + f32(i % 4) * 0.5);
        let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
        let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
        let neighbor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
        let weight = exp(-f32(i % 4) * 0.5);
        bloom += neighbor * glowFraction(neighbor) * weight;
        totalWeight += weight;
    }

    // `spread` is the fraction of glowing light the faceplate scatters (HDR Bloom slider).
    // The halo gains spread * ringMean(glow) and the core loses spread * glow(core), so a
    // uniformly bright field nets to zero and only edges/highlights redistribute.
    // Smooth saturating curve (the old clamp(0.45*b, 0, 0.7) went flat above slider 0.78):
    // spread(b) = 0.75 * (1 - exp(-0.9163 b)) -> 0.45 at the saved default b = 1 (slider 0.5),
    // 0.57 / 0.61 / 0.63 at slider 0.78 / 0.9 / 1.0, always < 0.75 so the core keeps >= 25 %.
    let spread = 0.75 * (1.0 - exp(-0.9163 * bloomIntensity));
    // The faceplate scatters light the phosphors EMITTED, i.e. after scanline dimming and
    // vignette — attenuate the source-built halo by the same mean chain gain so the core
    // loss and halo gain stay in the same units.
    let chainGain = (1.0 - 0.5 * scanlineIntensity) * (1.0 - edgeDist * edgeDist * 0.5) * humMod;
    bloom = bloom / max(totalWeight, 1e-4) * spread * chainGain;

    let hdrColor = max(color * (1.0 - spread * coreGlow) + bloom + flashAdd, vec3<f32>(0.0));

    // Tone map (clamped >= 0 above: the catalog ACES fit maps negatives to bright)
    let ldrColor = toneMapACES(hdrColor);

    // R4: alpha = phosphor emission coverage — lit phosphor is opaque, dark glass slightly
    // transmissive (never below 0.88, so compositing is not hollowed out)
    let emission = clamp(max(srcPeak, max(bloom.r, max(bloom.g, bloom.b))), 0.0, 1.0);
    let alpha = mix(0.88, 1.0, emission);

    textureStore(writeTexture, coord, vec4<f32>(ldrColor, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(phosphorState, max(0.0, max(phosphorState.r, max(phosphorState.g, phosphorState.b)) - 1.0)));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
