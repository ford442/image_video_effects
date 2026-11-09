// ═══════════════════════════════════════════════════════════════════
//  Chroma Lens Iridescence
//  Category: advanced-hybrid
//  Features: chroma-lens, thin-film-interference, depth-aware,
//            mouse-driven, audio-reactive, exact-feedback, temporal-state,
//            upgraded-rgba, semantic-alpha
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: Cauchy dispersion (§12.2F: R/B fringe from n(λ)=A+B/λ², blue wider than red, G stays on the lens curve); meniscus film wedge (§12.2F thin-film phase: film pools toward the bevel → concentric fringes at the lens-cap angle); internal-reflection ghost (§12.2F lens-flare ghost: faint inverted copy of the highlights mirrored through the lens centre). Rescued: lens centre lived in the zeroed scratch buffer (racy, parked at the corner in the app) → sprung centre in two A texels (orbit when idle, follows the cursor while held); iridescence was invisible (film angle was screen-centred, weight ≤ 0.4 %); click impulse derived from the newest ripple; white-noise film thickness → smooth value noise. Review fixes: lens velocity clamped to ±3 (a teleporting cursor flung the sprung lens off-screen); the ghost uses a soft knee (0.35..0.85) instead of a hard 0.55 cut that made it invisible on ordinary photos.
//  A packing: ACES display RGBA (HEAD). Texels (0,0) = (lens centre.xy, lens velocity.xy) and (1,0) = (fract(lastTime), 0, 0, 0.7371 sentinel) are STATE, not pixels (top-left corner, invisible); C reads of those texels are masked.
// ═══════════════════════════════════════════════════════════════════
//  Chromatic lens magnification fused with physical thin-film
//  optical iridescence. The lens body exhibits true wavelength-
//  dependent interference, radial chromatic aberration, and Fresnel
//  bevel reflections driven by pointer spring dynamics and audio.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Magnification, y=ChromaticDispersion, z=LensRadius, w=Iridescence

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const SENT: f32 = 0.7371;

// Cauchy n(λ)=A+B/λ² at 650/550/450 nm: deviations of R and B from G, normalised so that
// mean(|devR|,|devB|) = 1 — HEAD's symmetric ±aberration anchors. 1/λ² = 2.3669, 3.3058, 4.9383.
const CAUCHY_DEV: vec3<f32> = vec3<f32>(-0.7303, 0.0, 1.2697);
// mean of wavelengthToRGB over the 8 film taps 390..690 nm step 40 (white reference of thinFilmColor)
const FILM_WHITE: vec3<f32> = vec3<f32>(0.4663, 0.3984, 0.2564);

fn acesToneMap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Smooth value noise (HEAD used hash12 of a continuous uv = per-pixel white noise that re-randomised each frame).
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    let a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
    let g = 1.0 - abs(t - 0.45) * 2.5;
    let b = 1.0 - smoothstep(0.0, 0.45, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
    let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
    let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
    let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;
    var color = vec3<f32>(0.0);
    var sampleCount = 0.0;
    for (var lambda = 390.0; lambda <= 690.0; lambda = lambda + 40.0) {
        let phase = opd / lambda;
        let interference = cos(phase * TAU) * 0.5 + 0.5;
        color = color + wavelengthToRGB(lambda) * interference;
        sampleCount = sampleCount + 1.0;
    }
    // The raw spectral average peaks near 0.4 luma with a warm bias (dark mud-coloured fringes, so the film
    // only ever greyed the lens). Divide by the film's own white reference (the same 8 taps with I=1) so
    // "constructive at every wavelength" = white and the fringes carry real saturation.
    return color / max(sampleCount, 1.0) / FILM_WHITE;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let time = u.config.x;
    let isMouseDown = u.zoom_config.w > 0.5;
    let mouseUV = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let isStateTexel = (pixel.y == 0 && pixel.x < 2);

    // ── Sprung lens centre, persisted in two A texels ───────────────
    // HEAD kept this spring in extraBuffer[133..138], which is re-uploaded zeroed every frame and was
    // written by one thread while the others read it (racy: the lens sat at ~(0,0) in the app).
    // Texel (0,0) = (pos.xy, vel.xy), texel (1,0) = (fract(lastTime), 0, 0, SENT). Every thread
    // integrates the same step from the stored state; the sentinel guards the first frame / inherited C.
    // HEAD semantics kept: the lens wanders on its Lissajous orbit and follows the cursor while the button is held.
    let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
    let stateOk = abs(st1.w - SENT) < 0.001;
    let orbitPos = vec2<f32>(0.5 + 0.22 * cos(time * 0.75), 0.5 + 0.2 * sin(time * 0.9));
    let lensTarget = select(orbitPos, mouseUV, isMouseDown);
    var lensPos = select(lensTarget, st0.xy, stateOk);
    var lensVel = select(vec2<f32>(0.0), st0.zw, stateOk);
    let springDt = select(0.016, clamp(fract(time - st1.x), 0.001, 0.05), stateOk);
    let omega = 14.0;
    lensVel = lensVel + ((lensTarget - lensPos) * (omega * omega) - lensVel * omega) * springDt;   // zeta = 0.5
    lensVel = clamp(lensVel, vec2<f32>(-3.0), vec2<f32>(3.0));   // a teleporting cursor can't fling the lens off-screen
    lensPos = lensPos + lensVel * springDt;
    // f16 rest-snap (A is rgba16float on most tiers): settle exactly once near and slow. Only for the held
    // (static) target — the orbiting target moves 0.003/frame, which would pin the lens rigidly to it.
    let settled = isMouseDown && all(abs(lensTarget - lensPos) < vec2<f32>(0.004)) && length(lensVel) < 0.06;
    lensPos = select(lensPos, lensTarget, settled);
    lensVel = select(lensVel, vec2<f32>(0.0), settled);
    let smoothMouse = lensPos;

    let uv = (vec2<f32>(pixel) + 0.5) / res;
    let aspect = res.x / res.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Sliders
    let mag = mix(-0.4, 1.4, u.zoom_params.x) * (1.0 + bass * 0.3);
    let aberration = mix(0.006, 0.055, u.zoom_params.y) * (1.0 + treble * 0.4);
    let radius = mix(0.16, 0.65, u.zoom_params.z);
    let filmThicknessBase = mix(200.0, 780.0, u.zoom_params.z);
    let iridStrength = mix(0.3, 1.6, u.zoom_params.w);
    let blurEdges = mix(0.015, 0.08, u.zoom_params.w);
    let filmIOR = 1.45;

    let dVec = (uv - smoothMouse) * aspectVec;
    let dist = length(dVec);
    let holdEffect = smoothstep(0.4, 0.0, dist) * select(0.3, 1.0, isMouseDown);

    // Capped click ripple fronts. clickImpulse (HEAD: dead extraBuffer[138], 0.94/frame ≈ e^-3.7t)
    // is now taken from the newest ripple's age.
    var rippleDistortion = 0.0;
    var clickImpulse = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let rAge = time - r.z;
        if (r.z > 0.0 && rAge > 0.0 && rAge < 2.5) {
            let toRip = (uv - r.xy) * aspectVec;
            let rDist = length(toRip);
            let env = smoothstep(2.5, 0.0, rAge);
            let wave = sin(rDist * 36.0 - rAge * 11.0) * exp(-rDist * 6.5) * env;
            rippleDistortion = rippleDistortion + wave * 0.35;
            clickImpulse = max(clickImpulse, exp(-rAge * 3.7));
        }
    }
    rippleDistortion = rippleDistortion + sin(dist * 30.0 - time * 8.0) * exp(-dist * 7.0) * clickImpulse * 0.5;

    var finalUV_R = uv;
    var finalUV_G = uv;
    var finalUV_B = uv;

    let lensMask = 1.0 - smoothstep(radius, radius + blurEdges, dist);
    let ndist = clamp(dist / max(radius, 0.001), 0.0, 1.0);

    // Spherical / aspherical lens magnification & radial dispersion
    if (dist < radius + blurEdges) {
        let lensCurve = 1.0 - (1.0 - ndist * ndist) * mag;
        let abbStrength = aberration * ndist + rippleDistortion * 0.01;

        // ── Idea 1: Cauchy dispersion (§12.2F) ──────────────────────
        // n(λ)=A+B/λ²: blue sits ~1.27 fringe-units from green, red ~0.73 (HEAD: ±1 each). Same mean fringe
        // width as HEAD, but the real asymmetry; G stays on the lens curve.
        let factorR = lensCurve + abbStrength * CAUCHY_DEV.x;
        let factorG = lensCurve;
        let factorB = lensCurve + abbStrength * CAUCHY_DEV.z;

        let delta = uv - smoothMouse;
        finalUV_R = clamp(smoothMouse + delta * factorR, vec2<f32>(0.0), vec2<f32>(1.0));
        finalUV_G = clamp(smoothMouse + delta * factorG, vec2<f32>(0.0), vec2<f32>(1.0));
        finalUV_B = clamp(smoothMouse + delta * factorB, vec2<f32>(0.0), vec2<f32>(1.0));
    }

    let colR = textureSampleLevel(readTexture, u_sampler, finalUV_R, 0.0).r;
    let colG = textureSampleLevel(readTexture, u_sampler, finalUV_G, 0.0).g;
    let colB = textureSampleLevel(readTexture, u_sampler, finalUV_B, 0.0).b;
    var color = vec3<f32>(colR, colG, colB);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV_G, 0.0).r;
    let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));

    // Thin-film iridescence overlay inside lens area
    var filmW = 0.0;
    var filmTint = vec3<f32>(1.0);
    if (lensMask > 0.0) {
        // Viewing angle of the LENS cap, not of the screen centre (HEAD used |uv−0.5|, so
        // fresnel·0.65 ≤ 0.004 and the film was invisible).
        let cosLens = sqrt(max(1.0 - ndist * ndist, 0.02));
        let noiseVal = valueNoise(uv * aspectVec * 6.0 + vec2<f32>(time * 0.1, 0.0)) * 0.6
                     + valueNoise(uv * aspectVec * 13.0 - vec2<f32>(0.0, time * 0.15)) * 0.4;
        // ── Idea 2: meniscus film wedge (§12.2F thin-film phase) ────
        // Coating pools toward the bevel: thickness grows with ndist², so the fringes run as concentric
        // rings around the lens at the lens-cap angle.
        let wedge = 1.0 + 0.55 * ndist * ndist;
        var thickness = filmThicknessBase * (0.65 + depth * 0.55 + noiseVal * 0.35 + holdEffect * 0.3 + bass * 0.2) * wedge;
        thickness = thickness + rippleDistortion * 150.0;

        let filmN = thinFilmColor(thickness, cosLens, filmIOR);
        let iridescent = filmN * iridStrength;
        // the bevel's bright reflection is the film's reflection: tint it with the same fringe colour
        filmTint = mix(vec3<f32>(1.0), filmN, 0.35 + 0.25 * u.zoom_params.w);
        let fresnel = pow(1.0 - cosLens, 2.5);
        filmW = clamp(0.16 + 0.84 * fresnel, 0.0, 1.0) * 0.65;
        let lensColor = mix(color, iridescent, filmW);
        color = mix(color, lensColor, lensMask);

        // ── Idea 3: internal-reflection ghost (§12.2F lens-flare ghost) ──
        // A glass lens re-reflects bright highlights between its surfaces: a faint, inverted, shrunken,
        // warm copy mirrored through the lens centre, strongest in the middle and gone by the bevel.
        let ghostUV = clamp(smoothMouse - (uv - smoothMouse) * 0.55, vec2<f32>(0.0), vec2<f32>(1.0));
        let gs = textureSampleLevel(readTexture, u_sampler, ghostUV, 0.0).rgb;
        let gLuma = dot(gs, vec3<f32>(0.2126, 0.7152, 0.0722));
        // Soft knee (0.35..0.85) instead of a hard 0.55 cut: on the synthetic photo the old ghost was nearly
        // invisible (removing it changed max 0.042, 0.5% of pixels >0.02); now max 0.126, 7.1% >0.02, lens not lifted.
        let ghost = smoothstep(0.35, 0.85, gLuma) * pow(1.0 - ndist, 1.2) * lensMask;
        color = color + gs * vec3<f32>(1.0, 0.82, 0.62) * ghost * 0.32;
    }

    // Glass bevel rim highlight
    let rimMask = smoothstep(radius - 0.025, radius, dist) * (1.0 - smoothstep(radius, radius + blurEdges, dist));
    let rimColor = mix(vec3<f32>(1.0), vec3<f32>(0.5, 0.8, 1.0), treble);
    color = color + rimColor * filmTint * rimMask * 0.45 * (1.0 + treble);

    // Exact temporal feedback from dataTextureC (state texels are not colour)
    let prevRaw = textureLoad(dataTextureC, pixel, 0).rgb;
    let prev = select(prevRaw, color, isStateTexel);
    color = mix(color, prev, 0.1 + mids * 0.06);

    let tonemapped = acesToneMap(max(color, vec3<f32>(0.0)) * (1.0 + treble * 0.1));
    let alpha = clamp(luma * 0.5 + lensMask * 0.3 + rimMask * 0.25 + holdEffect * 0.15 + clickImpulse * 0.15 + filmW * lensMask * 0.1, 0.2, 0.98);
    let outputRGBA = vec4<f32>(tonemapped, alpha);

    // State texels carry the sprung lens centre instead of pixels (writeTexture is unaffected).
    var aOut = outputRGBA;
    if (pixel.y == 0 && pixel.x == 0) { aOut = vec4<f32>(lensPos, lensVel); }
    if (pixel.y == 0 && pixel.x == 1) { aOut = vec4<f32>(fract(time), 0.0, 0.0, SENT); }

    textureStore(writeTexture, pixel, outputRGBA);
    textureStore(dataTextureA, pixel, aOut);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
