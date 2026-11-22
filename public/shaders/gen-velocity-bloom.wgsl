// ═══════════════════════════════════════════════════════════════════
//  Velocity Bloom - Velocity-sensitive bloom that intensifies on motion
//  Category: lighting-effects
//  Features: temporal, velocity-based, multi-octave bloom, optical-flow
//            streaks, curl-noise advection, diffusion feedback, audio pump
//  Created: 2026-03-22
//  By: Agent 4A
//  Upgraded: 2026-08-05 — Algorithmist b35 (Lucas-Kanade-style flow
//            direction, motion-aligned anamorphic streaks, curl-noise
//            advected trails, Gray-Scott-hint diffusion feedback, audio
//            pump + guarded FFT shimmer, click pulse, generated relief
//            depth, bounds guard), 2026-11-19, 2026-11-22
//  Ideas: Doppler streak fringe; cooling afterglow; signed-motion flare & wake (arriving light flares the feed, departing light leaves a longer trail); energy-conserving composite (the base gives up what the bloom spreads, 12.2F)
//  A packing: rgb = accumulated bloom trail (raw HDR, never tone-mapped), a = previous source luma; ACES only on writeTexture
//  Rescue 2026-11-22: the click pulse kept its energy in extraBuffer[133..134], which the engine zeroes every frame (held-only, no decay, racy single writer); it is now stateless, from u.ripples
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;
const IDEA_1: f32 = 1.0;
const IDEA_2: f32 = 1.0;

fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// Display tone map for the bloom light (the A trail stays raw HDR).
fn aces(x: vec3<f32>) -> vec3<f32> {
    let c = max(x, vec3<f32>(0.0));
    return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── 2D value noise + curl (divergence-free flow field) ─────────────
fn hash21(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(0.1031, 0.1030));
    q += dot(q, q.yx + vec2<f32>(33.33));
    return fract((q.x + q.y) * q.x);
}

fn vnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// Curl of a 2-octave noise potential: incompressible swirl, temporally
// coherent because time only scrolls the potential smoothly.
fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
    let e = 0.35;
    let q = p + vec2<f32>(t * 0.13, -t * 0.09);
    let nT = vnoise2(q + vec2<f32>(0.0, e)) + 0.5 * vnoise2(q * 2.3 + vec2<f32>(0.0, e * 2.3));
    let nB = vnoise2(q - vec2<f32>(0.0, e)) + 0.5 * vnoise2(q * 2.3 - vec2<f32>(0.0, e * 2.3));
    let nR = vnoise2(q + vec2<f32>(e, 0.0)) + 0.5 * vnoise2(q * 2.3 + vec2<f32>(e * 2.3, 0.0));
    let nL = vnoise2(q - vec2<f32>(e, 0.0)) + 0.5 * vnoise2(q * 2.3 - vec2<f32>(e * 2.3, 0.0));
    return vec2<f32>(nT - nB, nL - nR) / (2.0 * e);
}

// ── Velocity magnitude (original soul, kept) + flow direction ──────
// Returns vec4(velocityMagnitude, flowDir.xy, signedLumaDelta). Flow direction fuses the
// luminance-gradient normal (brightness-constancy motion cue) with the
// ambient curl field so streaks are anisotropic even on still frames.
fn velocityField(uv: vec2<f32>, pixel: vec2<f32>, coord: vec2<i32>, t: f32) -> vec4<f32> {
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    // ── Rescue 1: C.rgb is last frame's accumulated BLOOM, not the source, so
    // HEAD saw "motion" everywhere. Previous source luma now lives in C.a. ──
    let prevLuma = textureLoad(dataTextureC, coord, 0).a;
    // Idea 3 source: the sign HEAD threw away with abs() (+ = light arriving, - = leaving).
    let signedDelta = luma(current) - prevLuma;
    let lumaDiff = abs(signedDelta) * 1.7;

    let right = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let left = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let up = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixel.y), 0.0).rgb;
    let down = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixel.y), 0.0).rgb;

    let gx = luma(right) - luma(left);
    let gy = luma(up) - luma(down);
    let gradient = length(vec2<f32>(gx, gy));

    let velocity = lumaDiff + gradient * 0.5;

    // Motion is perpendicular to the luminance gradient; curl adds swirl.
    let gradDir = vec2<f32>(-gy, gx);
    let curl = curlNoise(uv * 6.0, t);
    var flow = gradDir * 0.5 + curl * (0.4 + velocity * 0.6);
    let fl = length(flow);
    flow = select(flow / max(fl, 0.0001), vec2<f32>(1.0, 0.0), fl < 0.0001);
    return vec4<f32>(velocity, flow, signedDelta);
}

// ── Multi-octave bloom sampling (original structure, kept) ─────────
fn multiOctaveBloom(uv: vec2<f32>, baseRadius: f32, velocity: f32) -> vec3<f32> {
    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;

    let octaves = 4;
    for (var o: i32 = 0; o < octaves; o++) {
        let fo = f32(o);
        let radius = baseRadius * (1.0 + fo * 0.5) * (1.0 + velocity);
        let weight = 1.0 / (1.0 + fo * 0.5);

        let directions = 8;
        for (var i: i32 = 0; i < directions; i++) {
            let angle = f32(i) * TAU / f32(directions);
            let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
            bloom += textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb * weight;
        }

        totalWeight += weight * f32(directions);
    }

    return bloom / totalWeight;
}

// ── Motion-aligned anamorphic bloom ────────────────────────────────
// Streak axis follows the flow direction instead of a fixed horizontal,
// so fast motion smears along its own path like a true motion bloom.
fn anamorphicBloom(uv: vec2<f32>, radius: f32, velocity: f32, flowDir: vec2<f32>) -> vec3<f32> {
    var bloom = vec3<f32>(0.0);
    let samples = 16;
    let stretch = 1.0 + velocity * 2.0;
    // ── Idea 1: Doppler streak fringe (native) ── red rides the leading half of
    // the streak, blue the trailing half; the split widens with velocity.
    let lead = clamp(velocity * 1.5, 0.0, 0.85) * IDEA_1;

    for (var i: i32 = 0; i < samples; i++) {
        let s = (f32(i) / f32(samples - 1) - 0.5) * 2.0;
        let offset = flowDir * s * radius * stretch;
        let smp = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
        let w = vec3<f32>(mix(1.0, 2.0 * step(0.0, s), lead), 1.0, mix(1.0, 2.0 * step(s, 0.0), lead));
        bloom += smp * w;
    }

    return bloom / f32(samples);
}

// ── Velocity-based color tint (branchless smooth gradient) ─────────
fn velocityColor(velocity: f32) -> vec3<f32> {
    let c0 = vec3<f32>(1.0, 1.0, 1.0);
    let c1 = vec3<f32>(0.8, 0.9, 1.0);
    let c2 = vec3<f32>(0.4, 0.7, 1.0);
    let c3 = vec3<f32>(0.9, 0.4, 0.8);
    var tint = mix(c0, c1, smoothstep(0.0, 0.3, velocity));
    tint = mix(tint, c2, smoothstep(0.3, 0.6, velocity));
    tint = mix(tint, c3, smoothstep(0.6, 1.0, velocity));
    return tint;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    // Resolution bounds guard — mandatory
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixel = 1.0 / resolution;
    let t = u.config.x;

    let nExtra = arrayLength(&extraBuffer);
    let aspect = vec2<f32>(resolution.x / resolution.y, 1.0);

    // ── Rescue: stateless click pulse. HEAD kept its energy in extraBuffer[133..134],
    // which writeExtraBuffer zeroes every frame (held-only, never decayed, racy).
    // Clicks already live in u.ripples (uv, absolute startTime): a finite burst at
    // the click that decays like HEAD's 0.93/frame (~4.4/s), plus a soft held glow.
    var pulseCol = 0.0;
    let nRip = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri: u32 = 0u; ri < nRip; ri++) {
        let rp = u.ripples[ri];
        let age = t - rp.z;
        let live = select(0.0, 1.0, age >= 0.0 && age < 1.6);
        let dR = length((uv - rp.xy) * aspect);
        let e = live * exp(-age * 4.4);
        pulseCol += e * exp(-dR * dR * 18.0);
    }
    let held = select(0.0, 0.35, u.zoom_config.w > 0.5);
    let dM = length((uv - u.zoom_config.yz) * aspect);
    pulseCol += held * exp(-dM * dM * 18.0);

    // ── Audio: plasma bands + guarded low FFT bins (1–8 range) ──────
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    var fftLow = 0.0;
    if (nExtra > 13u) {
        fftLow = (extraBuffer[6] + extraBuffer[7] + extraBuffer[8]) / 3.0;
    }

    // ── Parameters - safe randomization (updatedParams order) ───────
    let threshold = mix(0.0, 0.3, u.zoom_params.x);
    let bloomIntensity = mix(0.3, 2.0, u.zoom_params.y) * (1.0 + bass * 0.5);
    let bloomRadius = mix(0.01, 0.05, u.zoom_params.z) * (1.0 + mids * 0.25);
    let decay = mix(0.7, 0.99, u.zoom_params.w);

    // ── Base color ──────────────────────────────────────────────────
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let baseLuma = luma(baseColor);

    // ── Velocity + flow direction ───────────────────────────────────
    let vf = velocityField(uv, pixel, coord, t);
    let velocity = vf.x;
    let flowDir = vf.yz;
    // ── Idea 3: signed-motion flare & wake ──────────────────────────────
    // HEAD took abs() of the luma change. Its sign says which way the light went:
    // arriving light (luma rising vs C.a) flares the bloom feed; departing light
    // is not forgotten, the luma that left is deposited into the trail, so it
    // decays/advects/diffuses with it. Zero on a perfectly still source, like
    // HEAD's lumaDiff.
    let arrive = smoothstep(0.02, 0.2, vf.w);
    let departed = max(-vf.w, 0.0);

    let velocityMask = smoothstep(threshold, threshold + 0.2, velocity);

    // ── Blooms ──────────────────────────────────────────────────────
    let bloom = multiOctaveBloom(uv, bloomRadius, velocity);
    let anamorphic = anamorphicBloom(uv, bloomRadius * 2.0, velocity, flowDir);

    var finalBloom = mix(bloom, anamorphic, velocityMask * 0.5);

    let tint = velocityColor(velocity);
    finalBloom = finalBloom * tint;

    // Treble / FFT-driven micro-shimmer sparkle (multi-scale detail)
    let shimmer = vnoise2(uv * resolution * 0.5 + vec2<f32>(t * 7.0, -t * 5.0));
    finalBloom += finalBloom * shimmer * treble * 0.6 * (1.0 + fftLow);

    // ── Feedback: curl-advected, diffused decay (Gray-Scott hint) ───
    // Advect the previous bloom along the flow field for organic trails.
    let advect = flowDir * bloomRadius * (0.5 + velocity) * 2.0;
    let prevCoord = vec2<i32>(vec2<f32>(coord) - advect * resolution);
    let prevCenter = textureLoad(dataTextureC, clamp(prevCoord, vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1)), 0).rgb;

    // 4-tap Laplacian of the feedback field → diffusion term
    let ipx = vec2<i32>(1, 0);
    let ipy = vec2<i32>(0, 1);
    let minC = vec2<i32>(0);
    let maxC = vec2<i32>(resolution) - vec2<i32>(1);
    let nR = textureLoad(dataTextureC, clamp(prevCoord + ipx, minC, maxC), 0).rgb;
    let nL = textureLoad(dataTextureC, clamp(prevCoord - ipx, minC, maxC), 0).rgb;
    let nU = textureLoad(dataTextureC, clamp(prevCoord + ipy, minC, maxC), 0).rgb;
    let nD = textureLoad(dataTextureC, clamp(prevCoord - ipy, minC, maxC), 0).rgb;
    let laplacian = (nR + nL + nU + nD) * 0.25 - prevCenter;

    // Reaction–diffusion-flavoured accumulation: diffuse, decay, then
    // feed from the thresholded bright-pass of the new frame.
    let diffused = prevCenter + laplacian * 0.6;
    // ── Idea 2: Cooling afterglow (native) ── carried trail energy shifts toward
    // velocityColor's cold end each frame: fresh bloom white, old trails blue.
    let cool = mix(vec3<f32>(1.0), vec3<f32>(0.9, 0.96, 1.05), IDEA_2);
    let decayedBloom = diffused * decay * cool;
    let feed = max(finalBloom * bloomIntensity - vec3<f32>(threshold * 0.5), vec3<f32>(0.0)) * (1.0 + arrive) + tint * (departed * 1.4);
    let accumulatedBloom = max(feed, decayedBloom * 0.9);

    // ── Composite: base + bloom (original blend scheme, kept) ──────
    // ── Idea 4: energy-conserving composite (12.2F) ──
    // The scattered light came from the source: the base gives up a fraction of
    // what the bloom carries before the blend, so glow does not double exposure.
    let take = clamp(luma(accumulatedBloom) * 0.28, 0.0, 0.45);
    let srcColor = baseColor * (1.0 - take);
    // The photo is already display-referred; the glow is the HDR light. ACES maps the
    // light into display range so the screen blend can no longer exceed 1 (HEAD clipped).
    let glowDisp = aces(accumulatedBloom);
    let screenBlend = 1.0 - (1.0 - srcColor) * (1.0 - glowDisp);
    let addBlend = srcColor + glowDisp * velocityMask;

    var finalColor = mix(screenBlend, addBlend, velocityMask * 0.5);
    finalColor = finalColor * (1.0 + velocity * 0.3);

    // Click pulse: finite, spatially local white-aether burst at each click
    // (stateless, from u.ripples; a soft glow follows the held cursor).
    finalColor += vec3<f32>(0.9, 0.95, 1.0) * pulseCol * 0.8;

    // ── Outputs ─────────────────────────────────────────────────────
    textureStore(dataTextureA, coord, vec4<f32>(accumulatedBloom, baseLuma));

    let alpha = clamp(mix(0.8, 1.0, velocityMask) + clamp(pulseCol, 0.0, 1.0) * 0.1, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0)), alpha));

    // Generated relief depth: bloom mass rises toward the viewer
    let bloomLuma = luma(accumulatedBloom);
    let depth = clamp(baseLuma * 0.25 + bloomLuma * 0.75, 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
