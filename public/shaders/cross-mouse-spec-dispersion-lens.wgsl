// ═══════════════════════════════════════════════════════════════════
//  Crossover: Mouse + Spectral — Prismatic Lens
//  Category: interactive-mouse
//  Features: crossover, mouse-driven, spectral-rendering, audio-reactive
//  Crosses: mouse-wormhole-lens (2C) + spec-prismatic-dispersion (3C)
//  Complexity: High
//  Created: 2026-04-19
//  By: Agent 5C — Phase C Crossover Integration
//  Upgraded: 2026-08-02, 2026-11-09
//  Ideas: Cauchy R/G/B displacement around a fixed G; aspect-correct lens; click dispersion bursts + spectral ring;
//         treble sparkle on the fringes; bass rim flare;
//         continuous 6-wavelength spectral integration (Cauchy dispersion, §12.2F);
//         axis-regularised refraction (thin-lens gradient, no centre pinch)
//  A packing: display RGBA (no ACES: the photo passes through, glow/rim are additive); texel (0,0) = (glide.x, glide.y, 7 marker, fract(time)) cursor state (not display data)
// ═══════════════════════════════════════════════════════════════════
//
//  The mouse cursor becomes a prismatic lens that spectrally disperses
//  the input image. Moving the mouse changes the lens focal point;
//  clicking increases the dispersion intensity. The lens uses physical
//  refraction with Cauchy's equation for wavelength-dependent IOR.
//
//  Notes:
//   - The lens is aspect-corrected: both uv and the (glided) mouse position
//     are scaled by (aspect, 1.0) before the distance is measured, so the
//     lens stays circular on any canvas. The same corrected vector drives
//     the refraction normal so dispersion stays radial, and the rim
//     gaussian uses the corrected distance.
//   - The cursor glides toward the raw cursor; the glide state lives in A
//     texel (0,0) (Rescue R1) — extraBuffer[133..] is re-uploaded zeroed
//     every frame, so HEAD's extraBuffer spring never persisted.
//   - Treble twinkles the fringes: the shimmer of the red and blue ends
//     rides engine FFT bins (extraBuffer[5 + bin]); HEAD read
//     plasmaBuffer[6].x / [8].x, which the host never uploads.
//   - Click ripples fire decaying dispersion bursts plus a brief spectral
//     ring at the burst edge, scattering rainbows on every click.
//
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Rescue R3 (see main): uv displacement per unit of Cauchy IOR difference x slider amplitude.
const PRISM_GAIN: f32 = 80.0;

fn cauchyIOR(lambda: f32, n0: f32, B: f32) -> f32 {
    return n0 + B / (lambda * lambda);
}

// ── Rescue R1: cursor glide in A texel (0,0) ─────────────────────────
// extraBuffer[133..] is re-uploaded zeroed every frame, so the spring could never persist.
// State = A(0,0) = (glide.x, glide.y, GLIDE_MARK, fract(time)); every pixel reads the same C texel and
// integrates the same step, only pixel (0,0) stores it. First-order glide (a velocity cannot be stored
// f16-safely); at rest it snaps exactly onto the cursor.
const GLIDE_MARK: f32 = 7.0;
fn glideStep(st: vec4<f32>, raw: vec2<f32>, time: f32, rate: f32) -> vec2<f32> {
    // w can round up to exactly 1.0 in f16 (fract(time) > 0.9997): accept it.
    let ok = abs(st.z - GLIDE_MARK) < 0.01 && st.w >= 0.0 && st.w <= 1.0;
    let dt = clamp(fract(time - st.w), 0.001, 0.05);
    let g = st.xy + (raw - st.xy) * (1.0 - exp(-rate * dt));
    let snapped = select(g, raw, length(raw - g) < 0.003);   // exact at rest even through f16 rounding
    return select(raw, snapped, ok);
}

// ── Rescue R2: engine FFT bins (extraBuffer[5 + bin], 0..1) ──────────
// HEAD read plasmaBuffer[6].x / [8].x (never uploaded -> always 0).
fn fftBin(bin: u32) -> f32 {
    let idx = 5u + min(bin, 127u);
    return select(0.0, extraBuffer[min(idx, arrayLength(&extraBuffer) - 1u)], arrayLength(&extraBuffer) > idx);
}
// Mean of 4 adjacent bins starting at `lo` (a steadier voice than a single bin).
fn fftBand4(lo: u32) -> f32 {
    return (fftBin(lo) + fftBin(lo + 1u) + fftBin(lo + 2u) + fftBin(lo + 3u)) * 0.25;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

    let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
    let rawMouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    // Rescue R2: the two treble voices ride engine FFT bins ~10..13 and ~30..33.
    let trebleLo = fftBand4(10u);
    let trebleHi = fftBand4(30u);

    // Bass breathes the lens aperture; mids widen spectral dispersion
    let lensRadius = mix(0.05, 0.3, u.zoom_params.x) * (1.0 + bass * 0.4);
    let dispersionScale = mix(0.0, 0.03, u.zoom_params.y) * (1.0 + mids * 0.5);
    let lensStrength = mix(0.5, 2.0, u.zoom_params.z);
    let rotationSpeed = mix(-1.0, 1.0, u.zoom_params.w);

    // ── Rescue R1: the prism glides toward the raw cursor (rate 8 = HEAD omega) ──
    // See glideStep(): first-order glide in A texel (0,0), read back with an exact C load.
    let glideState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let mousePos = glideStep(glideState, rawMouse, time, 8.0);

    let clickBoost = select(1.0, 2.0, mouseDown);
    var localDispersion = dispersionScale * clickBoost;

    // Aspect-corrected space: the lens stays circular on any canvas.
    let aspect = res.x / max(res.y, 1.0);
    let aspectVec = vec2<f32>(aspect, 1.0);
    let uvC = uv * aspectVec;
    let mouseC = mousePos * aspectVec;
    let toMouse = uvC - mouseC;
    let mouseDist = length(toMouse);

    // Click spectrum flares: each live ripple fires a decaying dispersion
    // burst at its click point plus a brief spectral ring at the burst edge.
    var spectralRing = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleAge = time - ripple.z;
        if (rippleAge >= 0.0 && rippleAge < 1.2) {
            let rippleC = ripple.xy * aspectVec;
            let rippleDist = length(uvC - rippleC);
            let decay = exp(-rippleAge * 2.0);
            let burstMask = 1.0 - smoothstep(0.0, 0.25, rippleDist);
            localDispersion = localDispersion + decay * 1.5 * burstMask * dispersionScale;
            let ringD = (rippleDist / 0.25) - 1.0;   // d*d, not pow(d, 2.0): the base is negative inside the ring
            let ringEdge = exp(-ringD * ringD * 40.0);
            spectralRing = spectralRing + ringEdge * decay;
        }
    }

    // Lens profile: parabolic thickness
    let lensProfile = max(0.0, 1.0 - (mouseDist * mouseDist) / (lensRadius * lensRadius));
    let lensFactor = lensProfile * lensStrength;

    // Rotation over time
    let angle = time * rotationSpeed * 0.2 + lensProfile * 3.14159;
    let ca = cos(angle);
    let sa = sin(angle);
    let rotDir = vec2<f32>(toMouse.x * ca - toMouse.y * sa, toMouse.x * sa + toMouse.y * ca);

    // Wavelengths for RGB
    let lambdaR = 650.0;
    let lambdaG = 530.0;
    let lambdaB = 460.0;
    let n0 = 1.4;
    let B = 3000.0;

    let iorG = cauchyIOR(lambdaG, n0, B);

    // Refraction displacement (computed in aspect-corrected space, mapped
    // back to uv space for sampling so the split stays radial).
    let normal = rotDir / max(length(rotDir), 1.0e-5);
    let shimmerR = 1.0 + trebleLo * 0.3;
    let shimmerB = 1.0 + trebleHi * 0.3;

    // ── Idea 2: axis-regularised refraction (thin-lens gradient) ─────────
    // A thin lens refracts in proportion to its thickness GRADIENT, which is zero on
    // the optic axis. HEAD applied full strength down to r -> 0, where the normal is
    // undefined and every direction is displaced (a centre pinch). The amplitude now
    // rises smoothly from nothing on the axis to full in the annulus; the rotating
    // normal and the parabolic profile are unchanged.
    let axisReg = smoothstep(0.0, 0.3 * lensRadius, mouseDist);

    // ── Rescue R3: dispersion unit gain ──────────────────────────────────
    // (iorR - iorG) is ~3.6e-3, so HEAD's R/B offset was 4e-5 uv at the defaults and
    // at most ~4e-4 uv (a quarter of a pixel at 576 px) with every slider at maximum:
    // the prism showed no fringes. PRISM_GAIN converts the Cauchy IOR difference into
    // a visible uv displacement (slider ranges and roles unchanged).
    let ampBase = localDispersion * lensFactor * axisReg * PRISM_GAIN;

    // ── Idea 1: continuous spectral integration (Cauchy dispersion, §12.2F) ──
    // Three wavelengths split the image into three offset RGB copies; a real prism
    // integrates over wavelength. Six wavelengths, evenly spaced in 1/lambda^2 so the
    // taps are evenly spaced in Cauchy displacement: tap 0 is exactly HEAD's red
    // (650 nm), tap 5 exactly HEAD's blue (460 nm), the four between fill the gap.
    // Each tap has its own Cauchy IOR n(lambda) = n0 + B/lambda^2, displaced relative to
    // the green reference (530 nm, undisplaced). An RGB response basis (red and blue
    // lobes at the two ends, a narrower green lobe in the middle) is normalised to sum
    // to 1 per channel, so a flat or white image is unchanged and the fringes grade
    // continuously from red through green to blue.
    let invL2R = 1.0 / (lambdaR * lambdaR);
    let invL2B = 1.0 / (lambdaB * lambdaB);
    var specAcc = vec3<f32>(0.0);
    var specW = vec3<f32>(0.0);
    for (var k = 0; k < 6; k = k + 1) {
        let s = f32(k) / 5.0;                                    // 0 = red end, 1 = blue end
        let lam = inverseSqrt(mix(invL2R, invL2B, s));           // 650 .. 460 nm
        let shimmerK = mix(shimmerR, shimmerB, s);
        let dispC = normal * (cauchyIOR(lam, n0, B) - iorG) * ampBase * shimmerK;
        let tapRGB = textureSampleLevel(readTexture, u_sampler, uv - dispC / aspectVec, 0.0).rgb;
        let wk = vec3<f32>(exp(-4.0 * s * s),
                           exp(-10.0 * (s - 0.5) * (s - 0.5)),
                           exp(-4.0 * (1.0 - s) * (1.0 - s)));
        specAcc = specAcc + tapRGB * wk;
        specW = specW + wk;
    }

    var finalColor = specAcc / max(specW, vec3<f32>(1.0e-4));

    // Add chromatic aberration glow inside lens
    let glow = lensProfile * 0.15 * clickBoost * (1.0 + bass * 0.6);
    finalColor = finalColor + vec3<f32>(glow * 0.8, glow * 0.5, glow * 1.0);

    // Bass rings the lens rim with a caustic flare
    let rimD = (mouseDist / max(lensRadius, 0.001)) - 1.0;   // d*d, not pow(d, 2.0): the base is negative inside the lens
    let rim = exp(-rimD * rimD * 30.0) * bass;
    finalColor = finalColor + vec3<f32>(1.0, 0.7, 0.35) * rim * 0.6;

    // Click bursts scatter a brief spectral ring at the burst edge
    finalColor = finalColor + vec3<f32>(0.9, 0.4, 1.0) * spectralRing * 0.5;

    // Alpha represents lens intensity
    let alpha = clamp(mix(1.0, 0.9, lensProfile * 0.3) + rim * 0.3, 0.0, 1.0);

    let outColor = vec4<f32>(finalColor, alpha);
    textureStore(writeTexture, global_id.xy, outColor);
    // dataTextureA = display RGBA, except texel (0,0): cursor-glide state (Rescue R1).
    // The display pixel at (0,0) still goes to writeTexture above.
    var aOut = outColor;
    if (global_id.x == 0u && global_id.y == 0u) {
        aOut = vec4<f32>(mousePos, GLIDE_MARK, fract(time));
    }
    textureStore(dataTextureA, vec2<i32>(global_id.xy), aOut);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
