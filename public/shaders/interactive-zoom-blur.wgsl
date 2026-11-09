// ═══════════════════════════════════════════════════════════════════
//  Interactive Zoom Blur
//  Category: distortion
//  Features: mouse-centered, chromatic-aberration, dithered-sampling, audio-reactive,
//            temporal-blur-trail, chromatic-radial-streaks, depth-blur-attenuation,
//            cursor-glide-epicenter, click-zoom-shockwaves, per-ring-fft-voices
//  Complexity: Medium
//  Upgraded: 2026-08-02, 2026-09-21, 2026-11-09
//  Ideas: depth-occluded streak taps; radial trail advection (history streams outward); whip-pan zoom burst (each tap's ray centre slides along the cursor lag, streaks curve while the pointer moves); linear-light accumulation (taps summed as c², sqrt'd, so highlights streak instead of averaging away)
//  A packing: display RGBA; texel (0,0) = (glide.x, glide.y, 7 marker, fract(time)) epicentre glide state (masked wherever C is read as colour)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

// ── Rescue R1: epicentre glide in A texel (0,0) ──────────────────────
// extraBuffer[133..] is re-uploaded zeroed every frame, so HEAD's critically-damped spring never persisted (its init
// flag read 0 each frame: the epicentre was the raw cursor and springVel was always 0). State = A(0,0) =
// (glide.x, glide.y, GLIDE_MARK, fract(time)); every pixel reads the same C texel and integrates the same step, only
// pixel (0,0) stores it. First-order glide (a velocity cannot be stored f16-safely), rate 10 = HEAD omega; the lag
// vector (raw - glide) is the velocity proxy (glide velocity = rate * lag).
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

fn hash11(p: f32) -> f32 {
    return fract(sin(p * 12.9898) * 43758.5453);
}

fn bayer(x: i32, y: i32) -> f32 {
    let matrix = array<f32, 16>(
        0.0, 0.5, 0.125, 0.625,
        0.75, 0.25, 0.875, 0.375,
        0.1875, 0.6875, 0.0625, 0.5625,
        0.9375, 0.4375, 0.8125, 0.3125
    );
    return matrix[(y % 4) * 4 + (x % 4)];
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Epicentre glide (Rescue R1) ─────────────────────────────────
    // The raw mouse is the target; the epicentre glides toward it so the tunnel does not snap. At rest glide == raw
    // exactly (snapped), so lag == 0 and the picture is HEAD's radial burst.
    let rawMouse = u.zoom_config.yz;
    let isCorner = global_id.x == 0u && global_id.y == 0u;
    let center = glideStep(textureLoad(dataTextureC, vec2<i32>(0, 0), 0), rawMouse, time, 10.0);
    let lagRaw = rawMouse - center;
    let lagLen = length(lagRaw);
    // Cursor lag (velocity proxy), magnitude clamped to 0.25 uv so a far jump cannot throw the streaks across the frame.
    let lag = lagRaw * min(1.0, 0.25 / max(lagLen, 1e-5));

    // Lag feeds a motion bonus: fast flicks smear harder (glide speed = rate * lag, bonus capped at +50 %).
    // HEAD's springSpeed * 4.0 was tuned for a velocity that was always 0; here the bonus ramps over a normal flick
    // speed range (saturates at 0.5 uv/s) instead of switching on for any drift.
    let springSpeed = lagLen * 10.0;
    var strength = u.zoom_params.x * (1.0 + bass * 0.25);
    strength *= 1.0 + min(springSpeed, 0.5);
    let chromatic = u.zoom_params.y;
    let sampleCount = u.zoom_params.z;
    let depthAttenuation = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let dir = uv - center;
    let dist = length(dir);
    let dirNorm = normalize(dir + vec2<f32>(1e-4));

    // Depth-scaled blur attenuation: deeper pixels blur less
    var attenuatedStrength = strength * (1.0 - depth * depthAttenuation);

    // ── Click zoom shockwaves ───────────────────────────────────────
    // Each live ripple detonates a secondary decaying radial blur pulse
    // centered at its click point (aspect-corrected ~0.3 radius, ~1.2s fade).
    let aspect = resolution.x / max(resolution.y, 1.0);
    let rippleTotal = min(u32(u.config.y), 50u);
    for (var r: u32 = 0u; r < rippleTotal; r = r + 1u) {
        let ripple = u.ripples[r];
        let rippleAge = time - ripple.z;
        if (rippleAge >= 0.0 && rippleAge <= 1.2) {
            let toRipple = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let rippleDist = length(toRipple);
            let pulse = exp(-rippleAge * 2.0) * smoothstep(0.3, 0.0, rippleDist);
            attenuatedStrength += pulse * 0.6;
        }
    }

    let samples = i32(sampleCount * 30.0 + 5.0);
    let dither = bayer(i32(global_id.x), i32(global_id.y)) / f32(samples);

    // Chromatic radial streak separation
    let rSpread = chromatic * 0.008 * (1.0 + treble * 0.3);
    let gSpread = chromatic * 0.008;
    let bSpread = chromatic * 0.008 * (1.0 - bass * 0.2);

    // Rescue R2: HEAD read plasmaBuffer[1..8] per tap (never uploaded -> always 0). The 8 ring voices now read the
    // engine FFT bins {0,1,2,4,7,11,19,32}, fetched once per pixel instead of once per tap. Zero audio => HEAD.
    var voiceBins = array<u32, 8>(0u, 1u, 2u, 4u, 7u, 11u, 19u, 32u);
    var ringVoice = array<f32, 8>(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    for (var k: u32 = 0u; k < 8u; k = k + 1u) {
        ringVoice[k] = fftBin(voiceBins[k]) * 0.15;
    }

    var wSum = 0.0;
    var rAcc = 0.0;
    var gAcc = 0.0;
    var bAcc = 0.0;

    for (var i: i32 = 0; i < samples; i = i + 1) {
        let t = (f32(i) + dither) / f32(samples);
        // Per-ring FFT voice: each tap's weight shimmers with a spectrum
        // bin selected from the fractional radius along the blur ray.
        let tapWeight = 1.0 + ringVoice[min(u32(t * 8.0), 7u)];
        let rT = t + rSpread * t;
        let gT = t;
        let bT = t - bSpread * t;
        // ── Idea 3: whip-pan zoom burst ──
        // A zoom burst shot while panning curves its streaks. Each tap's ray centre slides along the cursor lag:
        // centre_t = centre + lag * (0.8 t), so the tap lands at HEAD's position minus 0.8 * S * t^2 * lag (a curved,
        // quadratic path: the streak bends into a spiral). Exactly HEAD's radial streak when lag == 0 (cursor at rest).
        let ctr = center + lag * (0.8 * t);
        let dirT = uv - ctr;
        // Idea 1 — depth-occluded streaks. A tap that lands on a surface nearer than this
        // pixel (depth: near = 1) is foreground smearing over background; reject it so
        // foreground edges stay crisp against the zoom smear behind them.
        let gTapUV = clamp(ctr + dirT * (1.0 + gT * attenuatedStrength), vec2<f32>(0.0), vec2<f32>(1.0));
        let tapDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, gTapUV, 0.0).r;
        let occl = mix(1.0, 1.0 - smoothstep(0.04, 0.14, tapDepth - depth), 0.92);
        let wTap = tapWeight * occl;
        wSum += wTap;
        // ── Idea 4: linear-light accumulation ──
        // Exposure integrates light, not display values: taps are summed as c^2 (gamma-2 ~ linear light) and the
        // normalised sum is sqrt'd below, so a bright source streaks across the ray instead of averaging away.
        let sr = textureSampleLevel(readTexture, u_sampler, clamp(ctr + dirT * (1.0 + rT * attenuatedStrength), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
        let sg = textureSampleLevel(readTexture, u_sampler, gTapUV, 0.0).g;
        let sb = textureSampleLevel(readTexture, u_sampler, clamp(ctr + dirT * (1.0 + bT * attenuatedStrength), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
        rAcc += sr * sr * wTap;
        gAcc += sg * sg * wTap;
        bAcc += sb * sb * wTap;
    }
    // With no occlusion and no audio wSum == samples, so this is HEAD's 1/samples (in the squared domain); the weights
    // are normalised out so audio shapes the streak without brightening it. The floor guards a fully occluded ray.
    let invW = 1.0 / max(wSum, 1.0);
    var color = sqrt(max(vec3<f32>(rAcc, gAcc, bAcc) * invW, vec3<f32>(0.0)));

    // Temporal blur trail persistence
    // Idea 2 — radial trail advection. History is read one step inward along the zoom ray,
    // so each frame the trail moves outward from the epicentre, continuing the zoom motion
    // instead of sitting as a static ghost. Exact load (C is rgba32float).
    // Rescue R3: C(0,0) is the glide state, never colour. Advected coords land on it for pixels beside the corner
    // (cursor near the top-left), so that texel reads as the current colour instead.
    let advect = 1.0 - 0.03 * (0.5 + min(attenuatedStrength, 2.0));
    let prevUV = clamp(center + dir * advect, vec2<f32>(0.0), vec2<f32>(1.0));
    let prevCoord = clamp(vec2<i32>(prevUV * resolution), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
    let prev = select(textureLoad(dataTextureC, prevCoord, 0).rgb, color, prevCoord.x == 0 && prevCoord.y == 0);
    let trail = mix(color, prev * 0.88, 0.05 + mids * 0.02);
    color = mix(color, trail, 0.3);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let effectBlend = smoothstep(0.0, 1.0, dist * attenuatedStrength);
    color = mix(baseColor.rgb, color, effectBlend);

    let alpha = mix(baseColor.a, 1.0, effectBlend * 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    // A: display RGBA, except texel (0,0) = glide state (R1). writeTexture keeps the real pixel there.
    textureStore(dataTextureA, vec2<i32>(global_id.xy), select(vec4<f32>(color, alpha), vec4<f32>(center, GLIDE_MARK, fract(time)), isCorner));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0, 0, 1));
}
