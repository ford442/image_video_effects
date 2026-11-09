// ═══════════════════════════════════════════════════════════════════
//  Heat Haze Mirage — Batch 60
//  Category: image
//  Inferior mirage from a refractive-index gradient: ray curvature
//  follows dn/dy through the hot layer; past critical gradient a
//  vertically mirrored sample folds in (false water / doubled horizon).
//  Depth preserves scene geometry (no heat-column clobber). ACES +
//  semantic alpha. Heat source at the cursor glides (A texel (0,0)).
//
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: vertical atmospheric dispersion at the fold (Cauchy dispersion, §12.2 F); scintillation from the displacement-field divergence; exposure-integrated shimmer (C haze history now shown in dense haze)
//  A packing: dataTextureA stores temporal haze accumulation RGBA (pre-ACES HDR col.rgb + source a), resurfaced via
//  dataTextureC next frame; texel (0,0) = (glide.x, glide.y, 7 marker, fract(time)) heat-source glide state (masked
//  wherever C is read as colour). B writes diagnostics (heatDisp.xy, heatFactor, bass). Depth = scene + mirage relief.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=HeatIntensity, y=RiseSpeed, z=WavyScale, w=ChromaShift

// extraBuffer (this shader): read-only. [0..4] reserved, [5..132] engine FFT (per-band shimmer reads [5 + bin]).
// Persistent state lives in A texel (0,0), not extraBuffer[133..] (that is re-uploaded zeroed every frame).

// ── Rescue R1: heat-source glide in A texel (0,0) ────────────────────
// HEAD integrated ONE 1/60 spring step from a zeroed extraBuffer every frame, so the "spring" was the raw cursor.
// State = A(0,0) = (glide.x, glide.y, GLIDE_MARK, fract(time)); every pixel reads the same C texel and integrates
// the same step, only pixel (0,0) stores it. First-order glide (a velocity cannot be stored f16-safely), rate 3 = HEAD omega.
const GLIDE_MARK: f32 = 7.0;
fn glideStep(st: vec4<f32>, raw: vec2<f32>, time: f32, rate: f32) -> vec2<f32> {
    let ok = abs(st.z - GLIDE_MARK) < 0.01 && st.w >= 0.0 && st.w <= 1.0;
    let dt = clamp(fract(time - st.w), 0.001, 0.05);
    let g = st.xy + (raw - st.xy) * (1.0 - exp(-rate * dt));
    let snapped = select(g, raw, length(raw - g) < 0.003);   // exact at rest even through f16 rounding
    return select(raw, snapped, ok);
}

// ── Rescue R2: engine FFT bin (extraBuffer[5 + bin], 0..1, read-only). plasmaBuffer[1..] is never uploaded. ──
fn fftBin(i: u32) -> f32 {
    let idx = 5u + i;
    if (idx >= arrayLength(&extraBuffer)) { return 0.0; }
    return extraBuffer[idx];
}

// ── Idea 1 helper: Cauchy dispersion relative to green ───────────────
// Deflection of a ray in air is proportional to (n(λ) − 1) = B/λ² (Cauchy, A = 1), so a channel at λ is bent
// (λg/λ)² times the green deflection. At 650 / 550 / 450 nm: (−0.284, 0, +0.494) relative to green.
fn cauchyRel() -> vec3<f32> {
    let q = 0.550 / vec3<f32>(0.650, 0.550, 0.450);
    return q * q - vec3<f32>(1.0);
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i),                       hash(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    ) * 2.0 - 1.0;
}

fn fbm2(p: vec2<f32>) -> vec2<f32> {
    let n1 = vnoise(p);
    let n2 = vnoise(p + vec2<f32>(5.2, 1.3));
    return vec2<f32>(n1, n2);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims  = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv     = vec2<f32>(gid.xy) / dims;
    let coord  = vec2<i32>(gid.xy);
    let time   = u.config.x;
    let aspect = dims.x / dims.y;

    // Audio: real FFT bands live in plasmaBuffer[0] (x=bass, y=mid, z=treble)
    let bass   = plasmaBuffer[0].x;
    let mid    = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let heatIntensity = mix(0.0, 0.025, u.zoom_params.x) * (1.0 + bass * 2.0);
    let riseSpeed     = mix(0.1, 1.5,   u.zoom_params.y);
    let wavyScale     = mix(2.0, 12.0,  u.zoom_params.z);
    let chromaShift   = mix(0.0, 0.008, u.zoom_params.w) * (1.0 + treble * 0.5);

    // ── Heat source at the cursor (Rescue R1: glide, rate 3 = HEAD omega) ──
    let rawMouse = u.zoom_config.yz;
    let held     = u.zoom_config.w > 0.5;
    let isCorner = gid.x == 0u && gid.y == 0u;
    let heatPos  = glideStep(textureLoad(dataTextureC, vec2<i32>(0, 0), 0), rawMouse, time, 3.0);

    // Thermal sway
    let sway      = fbm2(vec2<f32>(time * 0.7, time * 0.53)) * 0.015;

    // Heat column stronger at bottom; held press widens + intensifies gradient
    let heatBase  = smoothstep(1.0, 0.0, uv.y) * 0.5 + 0.5;
    let mDist     = length((uv - (heatPos + sway)) * vec2<f32>(aspect, 1.0));
    let holdRadius = select(0.25, 0.34, held);
    let holdGain   = select(1.0, 1.55 + bass * 0.35, held);
    let mouseHeat = smoothstep(holdRadius, 0.0, mDist) * select(0.0, holdGain, held);

    var heatFactor = heatBase + mouseHeat;

    // ── Click heat bursts (≤50) ───────────────────────────────────
    var clickHeat = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp  = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 3.0) {
            let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            clickHeat = max(clickHeat, exp(-age * 1.5) * smoothstep(0.2, 0.0, rDist));
        }
    }
    heatFactor = min(heatFactor + clickHeat, 2.5);

    // ── Per-band FFT shimmer ──────────────────────────────────────
    // Rescue R2: HEAD read plasmaBuffer[1..8] (never uploaded -> always 0). Eight vertical bands now read the engine
    // FFT bins {0,1,2,4,7,11,19,32} (low bins carry the energy). Zero audio => HEAD's idle look.
    let band      = u32(clamp(uv.y * 8.0, 0.0, 7.999));
    var bandBins  = array<u32, 8>(0u, 1u, 2u, 4u, 7u, 11u, 19u, 32u);
    let bandBoost = fftBin(bandBins[band]) * 0.35;

    // Rising displacement field
    let risingUV  = vec2<f32>(uv.x * wavyScale, uv.y * wavyScale - time * riseSpeed);
    let nField    = fbm2(risingUV);
    let disp      = nField * heatIntensity * heatFactor * (1.0 + bandBoost);

    // ── Refractive-index gradient ray bending ─────────────────────
    // Held press intensifies dn/dy so the inversion fold arrives sooner.
    let gradScale = select(25.0, 34.0, held);
    let heatAbove = smoothstep(1.0, 0.0, uv.y + 0.04) * 0.5 + 0.5 + mouseHeat;
    let dn_dy     = (heatAbove - heatBase - mouseHeat) * gradScale;
    let pathLen   = smoothstep(0.9, 0.0, uv.y);
    let bend      = -dn_dy * pathLen * pathLen * heatIntensity * 0.42;

    let heatDisp  = vec2<f32>(disp.x, disp.y * 0.3 + bend);

    // Caustic runners — bright amber streaks racing through the hot layer
    let causticPhase = uv.x * 48.0 + uv.y * 14.0 - time * 7.5;
    let caustic = pow(max(0.0, sin(causticPhase + disp.x * 18.0)), 18.0)
                * heatFactor * smoothstep(0.75, 0.0, uv.y);
    let causticWarp = vec2<f32>(caustic * 0.004 * (1.0 + treble), -caustic * 0.002);
    let totalDisp = heatDisp + causticWarp;

    // ── Idea 1: vertical atmospheric dispersion (Cauchy) ──────────────
    // Atmospheric refraction is dispersive and acts along the density gradient, i.e. VERTICALLY: blue is bent more than
    // green, red less (cauchyRel: R -28 %, B +49 % of the green deflection). Scaled by |bend|, the ray curvature that
    // also drives the fold, so the fringe is a thin coloured edge in the strongly bent layer and nowhere else. A positive
    // offset moves the sampled row down, i.e. the blue image up and the red image down. Capped so a bass/held burst
    // stays a fringe, not a wash (cap 0.005 -> max blue offset 0.015 uv).
    let dispY = cauchyRel() * min(abs(bend), 0.005) * 6.0;

    // Chromatic shift across the mirage
    let rUV = clamp(uv + totalDisp + vec2<f32>(chromaShift, dispY.x), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + totalDisp,                                   vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + totalDisp + vec2<f32>(-chromaShift, dispY.z), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let a = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).a;

    // ── Stronger inversion-layer false-water fold ─────────────────
    let criticalGrad = select(0.55, 0.42, held);
    let tirMix = smoothstep(criticalGrad, criticalGrad + 0.42, abs(bend) * 48.0)
               * smoothstep(0.58, 0.0, uv.y);
    let mirrorUV = clamp(vec2<f32>(gUV.x, 2.0 * uv.y - gUV.y + bend * 2.4),
                         vec2<f32>(0.0), vec2<f32>(1.0));
    // Idea 1 (cont.): the mirrored image is the same rays reflected, so each channel's row offset flips sign
    // (mirror row = 2y - sampled row): the fold edge carries the fringe too.
    let mR = textureSampleLevel(readTexture, u_sampler, clamp(mirrorUV - vec2<f32>(0.0, dispY.x), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let mG = textureSampleLevel(readTexture, u_sampler, mirrorUV, 0.0).g;
    let mB = textureSampleLevel(readTexture, u_sampler, clamp(mirrorUV - vec2<f32>(0.0, dispY.z), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let mirrored = vec3<f32>(mR, mG, mB);

    let seen = mix(vec3<f32>(r, g, b), mirrored, tirMix * 0.88);

    // ── Idea 2: scintillation ─────────────────────────────────────────
    // Heat shimmer also makes bright points twinkle: the intensity counterpart of the image dancing. Where the
    // displacement field d converges (div d < 0) the rays focus and a highlight brightens, where it diverges it dims:
    // gain = 1 / (1 + S * div d), with div d taken from the SAME fbm field (risingUV) that displaces the picture, so the
    // twinkle is locked to the shimmer. d = (disp.x, 0.3 * disp.y), d(noise)/d(uv) = wavyScale. Highlights only
    // (luma 0.65..0.95), gain bounded to 0.75..1.3 and tied to the shimmer amplitude (zero at Heat Intensity = 0).
    let shimmerAmp = heatIntensity * heatFactor * (1.0 + bandBoost);
    let dNx  = (vnoise(risingUV + vec2<f32>(0.15, 0.0)) - nField.x) / 0.15;
    let dNy  = (vnoise(risingUV + vec2<f32>(5.2, 1.45)) - nField.y) / 0.15;
    // Photosensitivity taper: the twinkle rate is the shimmer rate (riseSpeed * wavyScale cycles/s, ~4 at the defaults);
    // above ~8 cycles/s the amplitude is pulled down (floor 40 %) so extreme sliders cannot strobe a highlight.
    let tame = clamp(8.0 / max(riseSpeed * wavyScale, 0.001), 0.4, 1.0);
    let divD = (dNx + 0.3 * dNy) * wavyScale * shimmerAmp * tame;
    let scintGain = clamp(1.0 / (1.0 + clamp(1.5 * divD, -0.4, 1.0)), 0.75, 1.3);
    let hlMask = smoothstep(0.65, 0.95, dot(seen, vec3<f32>(0.2126, 0.7152, 0.0722)));
    let seenS = seen * mix(1.0, scintGain, hlMask);

    // Warm amber atmospheric tint (not neon cyan)
    let warmTint   = vec3<f32>(1.06, 1.01, 0.94) * (1.0 + heatFactor * 0.12);
    var col        = seenS * warmTint;

    // Heat shimmer glow + caustic highlights
    let glowMask   = heatFactor * heatIntensity * 55.0;
    col += vec3<f32>(0.07, 0.035, 0.01) * glowMask * (1.0 + mid);
    col += vec3<f32>(1.0, 0.55, 0.18) * caustic * 0.22 * (1.0 + bandBoost);

    // Temporal accumulate haze state — exact textureLoad on C
    // Rescue R3: C(0,0) is the glide state (marker 7.0), never colour; an empty C (first frame, alpha 0) carries no
    // history either. Both fall back to the current value, so no 7.0 and no dark first-frame ramp reaches the picture.
    let prevRaw  = textureLoad(dataTextureC, coord, 0);
    let prev     = select(vec4<f32>(col, a), prevRaw, !isCorner && prevRaw.a > 0.001);
    let hazeAcc  = mix(vec4<f32>(col, a), prev, 0.85);

    // Semantic alpha: haze density + mirage fold + caustic
    let hazeDensity = clamp((heatFactor - 0.5) * 0.85 + tirMix * 0.7 + caustic * 0.25, 0.0, 1.0);

    // ── Idea 3: exposure-integrated shimmer ───────────────────────────
    // HEAD wrote the 0.85 EMA of the pre-ACES colour to A and never showed it. An exposure integrates shimmer, so the
    // accumulated haze now enters the picture, only in dense haze (clean regions and video input are not ghosted),
    // and BEFORE the tone map (A stays HDR, never ACES-ed). Negatives are clamped away.
    col = mix(col, max(hazeAcc.rgb, vec3<f32>(0.0)), 0.3 * hazeDensity);

    col = acesFilm(col);

    let outAlpha = clamp(mix(a, 1.0, hazeDensity * 0.75), 0.0, 1.0);
    let outColor = vec4<f32>(col, outAlpha);
    textureStore(writeTexture, coord, outColor);

    // Depth: scene geometry preserved, pushed by mirage relief
    let sceneDepth = textureLoad(readDepthTexture, coord, 0).r;
    let reliefDepth = clamp(sceneDepth - heatFactor * 0.04 - tirMix * 0.07 - caustic * 0.02, 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(reliefDepth, 0.0, 0.0, 1.0));
    // A: pre-ACES haze accumulation, except texel (0,0) = glide state (R1). writeTexture keeps the real pixel there.
    textureStore(dataTextureA, coord, select(hazeAcc, vec4<f32>(heatPos, GLIDE_MARK, fract(time)), isCorner));
    textureStore(dataTextureB, coord, vec4<f32>(totalDisp, heatFactor, bass));
}
