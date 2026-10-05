// ═══════════════════════════════════════════════════════════════════
//  Liquid Prism Cascade
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: three-stage refraction cascade; critical-angle (TIR) rim sparkle
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  Restored from b6ba3632 (9983b1eb had pasted an unrelated comic-ink
//  halftone over this file; the JSON params always described the prism).
//  Visual concept: Colors separate along curved planes like light through prisms,
//    creating a layered 3-D depth illusion where each channel drifts independently.
//  Mathematical approach: Per-channel UV warping with curved dispersion vectors
//    derived from local luminance gradient + depth curvature; ripple-modulated
//    prismatic offset; soft-light composite.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=DispersionStrength, y=CurvatureScale, z=PrismTwist, w=DepthWeight

// ─────────────────────────────────────────────────────────────────────────────
//  Luminance
// ─────────────────────────────────────────────────────────────────────────────
fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ─────────────────────────────────────────────────────────────────────────────
//  2-D hash for micro-noise
// ─────────────────────────────────────────────────────────────────────────────
fn hash2f(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(127.1, 311.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Smooth value noise (2-D)
// ─────────────────────────────────────────────────────────────────────────────
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2f(i + vec2<f32>(0.0, 0.0)), hash2f(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash2f(i + vec2<f32>(0.0, 1.0)), hash2f(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Prismatic dispersion offset for a given channel index (0=R, 1=G, 2=B)
//  Simulates Cauchy dispersion: shorter wavelengths bend more.
// ─────────────────────────────────────────────────────────────────────────────
fn prismOffset(channel: i32, grad: vec2<f32>, strength: f32, twist: f32, t: f32) -> vec2<f32> {
    // Wavelength weights: red bends least, blue most
    let wl = array<f32, 3>(0.6, 1.0, 1.5);
    let w = wl[channel];
    // Rotate gradient slightly per channel + time
    let angle = (f32(channel) - 1.0) * twist + t * 0.1;
    let cs = cos(angle);
    let sn = sin(angle);
    let rotGrad = vec2<f32>(cs * grad.x - sn * grad.y, sn * grad.x + cs * grad.y);
    return rotGrad * strength * w * 0.018;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Accumulate ripple displacement
// ─────────────────────────────────────────────────────────────────────────────
fn rippleDisp(uv: vec2<f32>, t: f32, rippleCount: u32) -> vec2<f32> {
    var disp = vec2<f32>(0.0);
    for (var i: u32 = 0u; i < rippleCount; i++) {
        let r = u.ripples[i];
        let age = t - r.z;
        if (age < 0.0 || age > 4.0) { continue; }
        let d = distance(uv, r.xy);
        let wave = sin(d * 40.0 - age * 6.0) * exp(-d * 5.0) * exp(-age * 1.2);
        let env = (1.0 - age / 4.0);
        if (d > 0.001) {
            disp += normalize(uv - r.xy) * wave * env * 0.012;
        }
    }
    return disp;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Fractional Brownian Motion (4 octaves)
// ─────────────────────────────────────────────────────────────────────────────
fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0; var a = 0.5; var pp = p;
    for (var i = 0; i < 4; i++) {
        v += a * vnoise(pp);
        pp = pp * 2.1 + vec2<f32>(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Spectral Cauchy dispersion coefficient for wavelength λ (nm, normalized)
//  Cauchy: n(λ) = A + B/λ²
// ─────────────────────────────────────────────────────────────────────────────
fn cauchyN(lambda: f32, A: f32, B: f32) -> f32 {
    return A + B / (lambda * lambda + 0.01);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Idea 2 helper: Snell exit from the liquid (index n → air). Returns
//  (transmitted angle θt, total-internal-reflection amount). asin domain is
//  guarded: past the critical angle sinT > 1 and the ray reflects instead.
// ─────────────────────────────────────────────────────────────────────────────
fn snellExit(n: f32, sinI: f32) -> vec2<f32> {
    let sinT = n * sinI;
    let thetaT = asin(clamp(sinT, 0.0, 1.0));
    let tir = smoothstep(0.95, 1.0, sinT);
    return vec2<f32>(thetaT, tir);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hue-preserving tone mapping
// ─────────────────────────────────────────────────────────────────────────────
fn toneMap(c: vec3<f32>) -> vec3<f32> {
    let lum = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let mapped = lum / (lum + 1.0);
    return c * (mapped / max(lum, 0.001));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Soft-light blend mode
// ─────────────────────────────────────────────────────────────────────────────
fn softLight(base: vec3<f32>, blend: vec3<f32>) -> vec3<f32> {
    return mix(
        2.0 * base * blend + base * base * (1.0 - 2.0 * blend),
        2.0 * base * (1.0 - blend) + sqrt(base) * (2.0 * blend - 1.0),
        step(vec3<f32>(0.5), blend)
    );
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn pickChannel(c: vec3<f32>, ch: i32) -> f32 {
    if (ch == 0) { return c.r; }
    if (ch == 1) { return c.g; }
    return c.b;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res   = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let uv    = vec2<f32>(gid.xy) / res;
    let t     = u.config.x;
    let tx    = 1.0 / res;

    // Audio: bass swells the dispersion (≤ +35%), treble feeds the shimmer
    let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // Parameters
    let dispStrength = (u.zoom_params.x * 2.0 + 0.3) * (1.0 + 0.35 * bass); // 0.3 – 2.3
    let curvScale    = u.zoom_params.y * 3.0 + 0.5;    // 0.5 – 3.5
    let prismTwist   = u.zoom_params.z * 3.14159;       // 0 – π
    let depthWeight  = u.zoom_params.w;                  // 0 – 1

    // ── Luminance gradient (finite differences) ───────────────────────────
    let srcC  = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let lumR  = luma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(tx.x, 0.0), 0.0).rgb);
    let lumL  = luma(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(tx.x, 0.0), 0.0).rgb);
    let lumU  = luma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, tx.y), 0.0).rgb);
    let lumD  = luma(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, tx.y), 0.0).rgb);
    let lumGrad = vec2<f32>(lumR - lumL, lumU - lumD);

    // ── Depth curvature ───────────────────────────────────────────────────
    let depth  = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(tx.x * 2.0, 0.0), 0.0).r;
    let depthL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(tx.x * 2.0, 0.0), 0.0).r;
    let depthU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, tx.y * 2.0), 0.0).r;
    let depthD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, tx.y * 2.0), 0.0).r;
    let depthCurv = vec2<f32>(depthR - depthL, depthU - depthD) * curvScale;

    // Combined gradient (luminance + depth curvature)
    let grad = lumGrad + depthCurv * depthWeight;

    // ── Slow curved warp via noise ─────────────────────────────────────────
    let noiseUV   = uv * 3.5 + vec2<f32>(t * 0.04, t * 0.03);
    let noiseBend = (vnoise(noiseUV) - 0.5) * 0.007;
    let bendVec   = vec2<f32>(noiseBend, noiseBend * 0.7);
    let bentGrad  = grad + bendVec;

    // ── Ripple displacement ───────────────────────────────────────────────
    let ripples = rippleDisp(uv, t, min(u32(u.config.y), 50u));

    // ── Idea 1: Cascade — per-channel prismatic sampling, three refractions ─
    // Stage 0 is HEAD's single refraction. Each later stage re-reads the
    // luminance gradient at the previously refracted (green-path) UV and
    // refracts every channel again with 0.6× attenuation, so the channels
    // separate further in stacked planes; the three stage samples are layered
    // (0.55 / 0.28 / 0.17) so each plane stays visible as its own fringe.
    let layerW = array<f32, 3>(0.55, 0.28, 0.17);
    var chUV = array<vec2<f32>, 3>(uv + ripples, uv + ripples, uv + ripples);
    var stageGrad = bentGrad;
    var att = 1.0;
    var rgb = vec3<f32>(0.0);
    for (var stage = 0; stage < 3; stage++) {
        var greenTap = vec3<f32>(0.0);
        for (var ch = 0; ch < 3; ch++) {
            let off = prismOffset(ch, stageGrad, dispStrength, prismTwist, t) * att;
            chUV[ch] = clamp(chUV[ch] + off, vec2<f32>(0.0), vec2<f32>(1.0));
            let col = textureSampleLevel(readTexture, u_sampler, chUV[ch], 0.0).rgb;
            if (ch == 0) { rgb.r += layerW[stage] * col.r; }
            else if (ch == 1) { rgb.g += layerW[stage] * col.g; greenTap = col; }
            else { rgb.b += layerW[stage] * col.b; }
        }
        if (stage < 2) {
            // re-read the gradient at the refracted UV (2-texel forward
            // differences ≈ HEAD's central-difference scale; the green tap is
            // the centre sample). Depth curvature + noise bend carry over.
            let p  = chUV[1];
            let lc = luma(greenTap);
            let lx = luma(textureSampleLevel(readTexture, u_sampler, clamp(p + vec2<f32>(2.0 * tx.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
            let ly = luma(textureSampleLevel(readTexture, u_sampler, clamp(p + vec2<f32>(0.0, 2.0 * tx.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb);
            stageGrad = vec2<f32>(lx - lc, ly - lc) + depthCurv * depthWeight + bendVec;
            att = att * 0.6;
        }
    }

    // ── Prismatic glow: add a faint additive halo in the dispersion direction
    let glowAmt = length(bentGrad) * 0.6;
    let glowR = textureSampleLevel(readTexture, u_sampler,
        clamp(uv + bentGrad * 0.03 + ripples, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let glowB = textureSampleLevel(readTexture, u_sampler,
        clamp(uv - bentGrad * 0.03 + ripples, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    var outColor = vec4<f32>(
        clamp(rgb.r + glowR * glowAmt * 0.15, 0.0, 1.0),
        clamp(rgb.g, 0.0, 1.0),
        clamp(rgb.b + glowB * glowAmt * 0.15, 0.0, 1.0),
        1.0
    );

    // ── Idea 2: Critical-angle rim — the bent gradient is the incidence at
    // the liquid surface. Each channel exits with its own Cauchy index (blue
    // bends most → reaches the critical angle first); Fresnel reflectance
    // climbs as θt grazes 90°, and past the critical angle the channel
    // reflects (TIR) instead of refracting: a bright glint along strong edges.
    let sinI = clamp(length(bentGrad) * dispStrength * 1.2, 0.0, 1.0);
    let nTIR = vec3<f32>(cauchyN(0.65, 1.40, 0.04), cauchyN(0.55, 1.40, 0.04), cauchyN(0.45, 1.40, 0.04));
    let reflUV = clamp(uv - bentGrad * 0.05 + ripples, vec2<f32>(0.0), vec2<f32>(1.0));
    let reflCol = textureSampleLevel(readTexture, u_sampler, reflUV, 0.0).rgb;
    let glint = 0.7 + 0.6 * vnoise(uv * res * 0.15 + vec2<f32>(t * 1.7, -t * 1.3));
    var tirAmt = vec3<f32>(0.0);
    for (var ch = 0; ch < 3; ch++) {
        let ex = snellExit(nTIR[ch], sinI);
        let fresnel = pow(1.0 - cos(ex.x), 5.0);           // 1 − cos ≥ 0
        let refl = clamp(max(ex.y, fresnel), 0.0, 1.0);
        let sparkle = pickChannel(reflCol, ch) * (1.0 + 1.2 * ex.y * glint) + 0.12 * ex.y * glint;
        tirAmt[ch] = refl;
        outColor[ch] = mix(outColor[ch], sparkle, refl * 0.85);
    }
    let tirAvg = (tirAmt.r + tirAmt.g + tirAmt.b) / 3.0;

    // ── FBM-modulated prismatic shimmer ───────────────────────────────────
    // FLOOR FIX: HEAD wrote shimmer*sin(..)*0.5+0.5, adding ~0.5 grey to every
    // channel (washed-out image). The 0.5 bias belongs inside the shimmer.
    let fbmVal  = fbm(uv * 6.0 + vec2<f32>(t * 0.02, -t * 0.015));
    let shimmer = fbmVal * 0.04 * dispStrength * (1.0 + treble);
    let shimmerColor = vec3<f32>(
        shimmer * (sin(t + 0.0) * 0.5 + 0.5),
        shimmer * (sin(t + 2.094) * 0.5 + 0.5),
        shimmer * (sin(t + 4.189) * 0.5 + 0.5)
    );

    // ── Cauchy dispersion enhancement ─────────────────────────────────────
    let nR = cauchyN(0.65, 1.45, 0.01);
    let nB = cauchyN(0.45, 1.45, 0.01);
    let cauchyDisp = (nB - nR) * length(bentGrad) * dispStrength * 0.02;
    let cauchyShift = vec2<f32>(cos(t * 0.1), sin(t * 0.1)) * cauchyDisp;
    let extraR = textureSampleLevel(readTexture, u_sampler,
        clamp(uv + cauchyShift + ripples, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let extraB = textureSampleLevel(readTexture, u_sampler,
        clamp(uv - cauchyShift + ripples, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    // ── Tone-mapped composite with shimmer ────────────────────────────────
    let prismFinal = toneMap(vec3<f32>(
        clamp(outColor.r * 0.85 + extraR * 0.15 + shimmerColor.r, 0.0, 1.0),
        clamp(outColor.g + shimmerColor.g, 0.0, 1.0),
        clamp(outColor.b * 0.85 + extraB * 0.15 + shimmerColor.b, 0.0, 1.0)
    ));
    let baseRGB = clamp(outColor.rgb, vec3<f32>(0.0), vec3<f32>(1.0));
    var finalRGB = softLight(baseRGB, prismFinal) * 0.6 + prismFinal * 0.4;

    // ── Edge vignette darkening for depth of field feel ───────────────────
    let edgeDist = length(uv - vec2<f32>(0.5));
    let vignette = 1.0 - smoothstep(0.35, 0.85, edgeDist) * 0.4;
    finalRGB = aces(max(finalRGB * vignette, vec3<f32>(0.0)));

    // Semantic alpha: source coverage, raised where the TIR glint lights up
    let alpha = clamp(srcC.a + tirAvg * 0.3 * (1.0 - srcC.a), 0.0, 1.0);
    let outPix = vec4<f32>(finalRGB, alpha);

    textureStore(writeTexture, gid.xy, outPix);
    textureStore(dataTextureA, gid.xy, outPix);
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 1.0));
}
