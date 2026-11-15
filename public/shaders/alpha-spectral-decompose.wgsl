// ═══════════════════════════════════════════════════════════════════
//  Alpha Spectral Decompose
//  Category: visual-effects
//  Features: spectral-visualization, audio-bands, mouse-scanner, depth-layers, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: oriented Gabor on the high residual; low-band inertia from C; band-matched audio
//  A packing: raw band luma (R low, G mid-low, B mid-high, A high); ACES on writeTexture
// ═══════════════════════════════════════════════════════════════════
//  RGBA channels stay the four bands. Bands can be negative (Gabor lobes).
//  Updated: 2026-05-31 — Grok (band reactivity + mouse scanner).

#include "_prelude.wgsl"

// Gabor-like oriented filter
fn gaborFilter(uv: vec2<f32>, angle: f32, frequency: f32, sigma: f32) -> f32 {
    let rotUV = vec2<f32>(
        uv.x * cos(angle) + uv.y * sin(angle),
        -uv.x * sin(angle) + uv.y * cos(angle)
    );
    let gauss = exp(-dot(rotUV, rotUV) / (2.0 * sigma * sigma));
    let wave = cos(rotUV.x * frequency * 6.283185307);
    return gauss * wave;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let ps = 1.0 / res;

    // === DECOMPOSE INTO 4 FREQUENCY BANDS ===
    // Sample neighborhood for multi-scale analysis
    let centerSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let centerLuma = dot(centerSample.rgb, vec3<f32>(0.299, 0.587, 0.114));
    var bandLow = vec3<f32>(0.0);
    var bandMidLow = vec3<f32>(0.0);
    var bandMidHigh = vec3<f32>(0.0);
    var bandHigh = vec3<f32>(0.0);
    var gaborAcc = 0.0;
    var gaborW = 0.0;

    let sampleCount = 8;
    for (var i = 0; i < sampleCount; i = i + 1) {
        let angle = f32(i) * 6.283185307 / f32(sampleCount);
        for (var r = 1; r <= 3; r = r + 1) {
            let radius = f32(r) * 2.0 * ps.x;
            let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
            let sampleUV = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
            let sampleColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
            let luma = dot(sampleColor, vec3<f32>(0.299, 0.587, 0.114));

            // Weight by distance (approximating Gaussian at different scales)
            let dist = f32(r);
            let wLow = exp(-dist * dist / 8.0);       // Large scale
            let wMidLow = exp(-dist * dist / 3.0);    // Medium scale
            let wMidHigh = exp(-dist * dist / 1.0);   // Small scale
            let wHigh = exp(-dist * dist / 0.3);      // Fine scale

            bandLow += sampleColor * wLow;
            bandMidLow += sampleColor * wMidLow;
            bandMidHigh += sampleColor * wMidHigh;
            bandHigh += sampleColor * wHigh;

            // ── Idea 1: oriented Gabor on the high residual ────────
            let gSigned = gaborFilter(offset, angle, 0.55 / max(ps.x, 0.0001), 2.4 * max(ps.x, 0.0001));
            gaborAcc += (luma - centerLuma) * gSigned;
            gaborW += abs(gSigned);
        }
    }

    // Normalize
    bandLow /= f32(sampleCount * 3);
    bandMidLow /= f32(sampleCount * 3);
    bandMidHigh /= f32(sampleCount * 3);
    bandHigh /= f32(sampleCount * 3);

    // Difference-of-Gaussians style: extract bands
    let lowLuma = dot(bandLow, vec3<f32>(0.299, 0.587, 0.114));
    let midLowLuma = dot(bandMidLow, vec3<f32>(0.299, 0.587, 0.114));
    let midHighLuma = dot(bandMidHigh, vec3<f32>(0.299, 0.587, 0.114));
    let highLuma = dot(bandHigh, vec3<f32>(0.299, 0.587, 0.114));

    let gaborHigh = gaborAcc / max(gaborW, 0.001);
    let bandG = midLowLuma - lowLuma * 0.5;
    let bandB = midHighLuma - midLowLuma * 0.5;
    let bandA = mix(highLuma - midHighLuma * 0.5, gaborHigh, 0.7);

    // ── Idea 2: low-band inertia ───────────────────────────────────
    // Lows chase the previous band. The other three stay instant.
    let cDims = vec2<i32>(textureDimensions(dataTextureC));
    let cCoord = clamp(coord, vec2<i32>(0), cDims - vec2<i32>(1));
    let prevBands = textureLoad(dataTextureC, cCoord, 0);
    let prevEnergy = abs(prevBands.r) + abs(prevBands.g) + abs(prevBands.b) + abs(prevBands.a);
    let lag = 0.42 * smoothstep(0.0, 0.02, prevEnergy);
    let bandR = mix(lowLuma, prevBands.r, lag);

    // Store decomposition. Raw bands — not display, not tone-mapped.
    textureStore(dataTextureA, coord, vec4<f32>(bandR, bandG, bandB, bandA));

    // === RECOMPOSITION WITH PARAM GAINS ===
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    // ── Idea 3: band-matched audio ─────────────────────────────────
    // Each slider stays that band's gain. The matching audio band scales it.
    let gainLow = u.zoom_params.x * 3.0 * (1.0 + bass * 0.35);
    let gainMidLow = u.zoom_params.y * 3.0 * (1.0 + mids * 0.28);
    let gainMidHigh = u.zoom_params.z * 3.0 * (1.0 + mids * 0.28);
    let gainHigh = u.zoom_params.w * 3.0 * (1.0 + treble * 0.35);

    var recomposed = vec3<f32>(0.0);
    // Each band contributes a tinted version
    recomposed += vec3<f32>(1.0, 0.8, 0.6) * bandR * gainLow;
    recomposed += vec3<f32>(0.6, 1.0, 0.7) * bandG * gainMidLow;
    recomposed += vec3<f32>(0.5, 0.7, 1.0) * bandB * gainMidHigh;
    recomposed += vec3<f32>(1.0, 1.0, 1.0) * bandA * gainHigh;

    // Add back some original color to preserve recognizability
    recomposed = mix(recomposed, centerSample.rgb, 0.2);
    recomposed = max(recomposed, vec3<f32>(0.0));

    // === MOUSE INTERACTION ===
    // Mouse radial frequency boost
    let mousePos = u.zoom_config.yz;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.3, 0.0, mouseDist) * u.zoom_config.w;
    recomposed += vec3<f32>(max(bandA, 0.0) * mouseInfluence * 2.0);

    // === RIPPLE PULSE ===
    let time = u.config.x;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 0.8 && rDist < 0.15) {
            let pulse = smoothstep(0.15, 0.0, rDist) * max(0.0, 1.0 - age);
            recomposed += max(bandHigh, vec3<f32>(0.0)) * pulse * 0.85;
        }
    }

    // Total spectral energy for alpha
    let spectralEnergy = abs(bandR) + abs(bandG) + abs(bandB) + abs(bandA);
    let alpha = clamp(spectralEnergy * 0.45 + centerSample.a * 0.2, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(aces(max(recomposed, vec3<f32>(0.0))), alpha));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
