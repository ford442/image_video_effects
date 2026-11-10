// ═══════════════════════════════════════════════════════════════
//  RGB Shift Brush - Feedback-based RGB displacement with spectral alpha
//  Category: artistic
//  Features: feedback, brush-dispersion, wavelength-dependent-alpha
//  Upgraded: 2026-10-04, 2026-11-09
//  Ideas: chromatic tail lag (slow long-wave mask in A.g); 7-tap prism fan on the WAVELENGTH_* bands; edge-oriented dispersion (stroke rim disperses along the mask normal, §12.2A direction-not-magnitude); Cauchy-spaced prism fan (700-400 nm taps at 1/lambda^2 + 1/lambda^4 offsets anchored on red, blue spreads ~2x red; fan gate opened to the rim/tail, §12.2F)
//  A packing: raw mask state — r = fast trail mask, g = slow tail mask, b = 0, a = 1
//
//  STYLIZED SPECTRAL MODEL:
//  - Dispersion shifts position and maps trail thickness to channel alpha
//  - Named wavelength bands provide a stable artistic color ordering
// ═══════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══════════════════════════════════════════════════════════════
//  SPECTRAL BAND CONSTANTS
// ═══════════════════════════════════════════════════════════════
const WAVELENGTH_RED:    f32 = 650.0;  // nm
const WAVELENGTH_GREEN:  f32 = 550.0;  // nm
const WAVELENGTH_BLUE:   f32 = 450.0;  // nm

// ═══════════════════════════════════════════════════════════════
//  WAVELENGTH-DEPENDENT ALPHA
// ═══════════════════════════════════════════════════════════════
fn calculateChannelAlpha(thickness: f32, wavelength: f32) -> f32 {
    let lambda_norm = (800.0 - wavelength) / 400.0;
    let absorption = mix(0.3, 1.0, lambda_norm);
    return exp(-thickness * absorption);
}

// Gaussian response of each display channel to a wavelength (nm), centred on the
// file's named bands, used to weight the prism-fan taps.
// (d*d, not pow(d, 2.0): d is negative below each band centre and pow() of a negative base is NaN-prone)
fn bandResponse(lambda: f32) -> vec3<f32> {
    let dr = (lambda - WAVELENGTH_RED) / 55.0;
    let dg = (lambda - WAVELENGTH_GREEN) / 50.0;
    let db = (lambda - WAVELENGTH_BLUE) / 45.0;
    return vec3<f32>(exp(-dr * dr), exp(-dg * dg), exp(-db * db));
}

// Cauchy dispersion: n(lambda) = A + B/lambda^2 + C/lambda^4. Offset from green (lambda_G): zero at green,
// negative on the red side, positive on the blue side, growing faster toward blue; the 1/lambda^4 term (second
// Cauchy coefficient) steepens the blue side so blue spreads clearly more than red.
fn cauchyOffset(lambda: f32) -> f32 {
    let s2 = (WAVELENGTH_GREEN / lambda) * (WAVELENGTH_GREEN / lambda);
    return (s2 - 1.0) + 0.5 * (s2 * s2 - 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    var mouse = u.zoom_config.yz;
    let held = step(0.5, u.zoom_config.w);
    let audio = plasmaBuffer[0].xyz;

    // Params
    let shiftAmount = u.zoom_params.x * 0.1;
    let brushSize = mix(0.01, 0.2, u.zoom_params.y);
    let decay = mix(0.9, 0.995, u.zoom_params.z);
    let hueShift = u.zoom_params.w;

    let spectralRunner = pow(max(0.0, sin((uv.x + uv.y * 0.31) * 52.0 - time * (15.0 + audio.y * 7.0))), 14.0);
    let ribbonRunner = pow(max(0.0, sin((uv.y - uv.x * 0.18) * 64.0 - time * (20.0 + audio.z * 8.0))), 18.0);
    let feedbackFlow = vec2<f32>(cos(time * 1.7), sin(time * 1.3)) * shiftAmount * 0.08 * (0.25 + spectralRunner);
    let historyCoord = clamp(vec2<i32>((uv - feedbackFlow) * resolution), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));

    // 1. Update Feedback Mask using exact prior-state texels.
    let prevState = textureLoad(dataTextureC, historyCoord, 0);
    let prevVal = prevState.r;

    // Calculate Brush Influence
    let aspect = resolution.x / resolution.y;
    let dVec = (uv - mouse) * vec2(aspect, 1.0);
    let dist = length(dVec);
    // Hover deposit scales with (1 - decay) so a parked cursor settles at a faint ~0.35 peak whatever the Decay slider
    // says (HEAD's fixed 0.12 reached 0.12/(1-decay) = 5 -> clamped to 1: an idle cursor painted a full-strength
    // disc). Held painting is unchanged (weight 1.0).
    let brush = smoothstep(brushSize, brushSize * 0.5, dist) * mix(0.35 * (1.0 - decay), 1.0, held);

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var rippleIndex: u32 = 0u; rippleIndex < rippleCount; rippleIndex = rippleIndex + 1u) {
        let ripple = u.ripples[rippleIndex];
        let rippleAge = max(time - ripple.z, 0.0);
        let front = abs(distance(uv, ripple.xy) - rippleAge * (0.22 + audio.x * 0.12));
        clickFront += exp(-front * 125.0) * exp(-rippleAge * 1.6);
    }

    // New mask value
    let newVal = clamp(prevVal * decay + brush + clickFront * 0.35 + ribbonRunner * audio.z * 0.025, 0.0, 1.0);

    // Idea 1 — chromatic tail lag: a second, slower "long-wave" mask outlives the fast one,
    // so the trail tail keeps only its blue displacement and resolves into a lingering fringe.
    let slowDecay = mix(decay, 1.0, 0.6);
    let newSlow = max(newVal, clamp(prevState.g * slowDecay, 0.0, 1.0));

    // Write to DataTextureA for next frame
    textureStore(dataTextureA, global_id.xy, vec4(newVal, newSlow, 0.0, 1.0));

    // 2. Render Effect
    let shiftGain = shiftAmount * (1.0 + audio.x * 0.35 + spectralRunner * 0.25);
    let shift = shiftGain * newVal;
    let shiftSlow = shiftGain * newSlow;

    // Shift direction based on time
    let angle = time * (2.0 + audio.y * 1.4) + ribbonRunner * 0.45;
    let dirT = vec2(cos(angle), sin(angle));

    // ── Idea 3: edge-oriented dispersion (§12.2A direction-not-magnitude) ──────────────────
    // The time-rotating direction ignores the stroke. A prism/lens disperses ALONG the surface
    // gradient and hardest at its EDGE, hardly at all in the flat interior. The previous-frame mask
    // (exact C.r, +-3 texels) gives the stroke normal n and an edge strength e (0 in the flat interior and
    // far from the stroke, 1 on the brush rim, partial along fading trails). The rotating shift is stretched
    // along n and squeezed along the rim tangent: M = I + e*(2.0 n n^T - 0.75 t t^T), i.e. x3 along the normal
    // and x0.25 along the tangent at the rim. n n^T and t t^T are sign-invariant, so the rotation stays
    // continuous (no R/B flip when dirT crosses the normal) and e = 0 is exactly HEAD. |dir| <= 3, UVs clamped.
    let cmax = vec2<i32>(resolution) - vec2<i32>(1);
    let gR = textureLoad(dataTextureC, clamp(historyCoord + vec2<i32>(3, 0), vec2<i32>(0), cmax), 0).r;
    let gL = textureLoad(dataTextureC, clamp(historyCoord - vec2<i32>(3, 0), vec2<i32>(0), cmax), 0).r;
    let gD = textureLoad(dataTextureC, clamp(historyCoord + vec2<i32>(0, 3), vec2<i32>(0), cmax), 0).r;
    let gU = textureLoad(dataTextureC, clamp(historyCoord - vec2<i32>(0, 3), vec2<i32>(0), cmax), 0).r;
    let gradPix = vec2<f32>(gR - gL, gD - gU) * (1.0 / 6.0);          // mask change per pixel
    let gradLen = length(gradPix);
    let nPix = gradPix / max(gradLen, 1e-6);
    let tPix = vec2<f32>(-nPix.y, nPix.x);
    // the brush ramp has max slope ~3/brushSize per uv-height; normalise so the rim reads ~1, and start
    // early so fading trail slopes disperse too (wide rim measure)
    let edge = smoothstep(0.04, 0.4, gradLen * resolution.y * brushSize * (1.0 / 3.0));
    let dIso = vec2<f32>(dirT.x * aspect, dirT.y);                    // work in square-pixel space
    let dEdge = dIso + edge * (2.0 * nPix * dot(nPix, dIso) - 0.75 * tPix * dot(tPix, dIso));
    let dir = vec2<f32>(dEdge.x / aspect, dEdge.y);

    let r_uv = clamp(uv + dir * shift, vec2<f32>(0.0), vec2<f32>(1.0));
    let b_uv = clamp(uv - dir * shiftSlow, vec2<f32>(0.0), vec2<f32>(1.0));

    var r = textureSampleLevel(readTexture, u_sampler, r_uv, 0.0).r;
    var g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    var b = textureSampleLevel(readTexture, u_sampler, b_uv, 0.0).b;

    // Idea 2 — prism fan: along the rim and fading tail the 3-tap split opens into seven taps across the
    // visible band (Idea 4 below sets their spacing), each weighted by bandResponse, so a
    // strong shift smears into a continuous spectrum instead of three hard ghosts.
    // Gate widened (HEAD: smoothstep(0.25, 0.9, newSlow) * smoothstep(0.004, 0.02, ..)): the fan now opens along the
    // whole rim and fading tail, where the stroke is still transparent enough to see it, not only in the dense
    // (strongly absorbed, nearly black) interior.
    let fanMix = smoothstep(0.05, 0.5, newSlow) * smoothstep(0.002, 0.012, shift + shiftSlow);
    if (fanMix > 0.001) {
        var acc = vec3<f32>(0.0);
        var wsum = vec3<f32>(0.0);
        let oR = cauchyOffset(WAVELENGTH_RED);
        for (var k: i32 = 0; k < 7; k = k + 1) {
            // ── Idea 4: Cauchy-spaced fan (§12.2F). Seven taps still, but now 700 -> 400 nm (50 nm apart: the
            // named red/blue bands +-50 nm) so each channel's Gaussian is covered on both sides (HEAD's 650 -> 450
            // fan cut the red and blue Gaussians off toward green). Tap offsets follow n(lambda) - n(green)
            // (1/lambda^2 + 1/lambda^4 terms) in units of the file's own shifts, anchored on RED: 650 nm lands at
            // +shift exactly as before, 550 nm at 0, and blue/violet follow the law relative to red -- 450 nm at
            // 2.1x and 400 nm at 4.1x of -shiftSlow, 700 nm at 1.3x of +shift -- so blue spreads ~2x red.
            // (Anchoring blue at exactly -shiftSlow as well was measured and is invisible: it only re-spaces
            // interior taps by ~5 %.)
            let lambda = WAVELENGTH_RED + 50.0 - 50.0 * f32(k);
            let w = bandResponse(lambda);
            let cOff = cauchyOffset(lambda);
            let tapShift = select(shift, shiftSlow, cOff > 0.0) * (cOff / oR);   // oR < 0: red side +, blue side -
            let tapUV = clamp(uv + dir * tapShift, vec2<f32>(0.0), vec2<f32>(1.0));
            acc += textureSampleLevel(readTexture, u_sampler, tapUV, 0.0).rgb * w;
            wsum += w;
        }
        let fan = acc / max(wsum, vec3<f32>(1e-4));
        r = mix(r, fan.r, fanMix);
        g = mix(g, fan.g, fanMix);
        b = mix(b, fan.b, fanMix);
    }

    // Optional Hue Shift on the trail
    if (hueShift > 0.0) {
        if (newVal > 0.1) {
           r = mix(r, 1.0 - r, hueShift * newVal);
           b = mix(b, 1.0 - b, hueShift * newVal);
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  WAVELENGTH-DEPENDENT ALPHA
    //  Thickness derived from shift amount and mask value
    // ═══════════════════════════════════════════════════════════════
    let dispersionThickness = shift * 10.0 + newVal * 2.0;
    
    let alphaR = calculateChannelAlpha(dispersionThickness, WAVELENGTH_RED);
    let alphaG = calculateChannelAlpha(dispersionThickness, WAVELENGTH_GREEN);
    let alphaB = calculateChannelAlpha(dispersionThickness, WAVELENGTH_BLUE);
    
    let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
    let finalAlpha = dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights);
    
    let finalColor = clamp(vec3<f32>(
        r * alphaR,
        g * alphaG,
        b * alphaB
    ) + vec3<f32>(0.18, 0.48, 1.0) * spectralRunner * audio.y * 0.08 +
        vec3<f32>(1.0, 0.22, 0.55) * clickFront * 0.08,
        vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4(finalColor, finalAlpha));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
