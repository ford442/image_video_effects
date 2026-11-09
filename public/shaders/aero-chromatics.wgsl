// ═══════════════════════════════════════════════════════════════════
//  Aero Chromatics
//  Category: simulation
//  Features: mouse-driven, depth-aware, audio-reactive
//  Complexity: Medium
//  Chunks From: aero-chromatics
//  Created: 2026-05-31
//  By: Copilot CLI (tactical swarm)
//  Upgraded: 2026-11-09
//  Ideas: edge-tangent flow (smoke slides along object silhouettes instead of through them);
//         spiral outflow (the pointer wind gains a swirl so repulsion curls into arms)
//  A packing: raw smoke colour trail + alpha (no ACES: the trail is its own history);
//             texel (0,0) = (windSource.xy, 7, fract(time)) wind-source glide state, masked on read
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Aero Chromatics
// P1: Wind Speed / Force
// P2: Decay Rate (Tail length)
// P3: Chromatic Split (Aberration amount)
// P4: Source Mix (How much new video is injected vs history)

// Rescue R1 — the sprung wind source used to live in extraBuffer[133..137]. The host re-uploads
// extraBuffer every frame (zero beyond the FFT bins), so that state never persisted and the
// "spring" was the raw cursor with a same-dispatch write race. The eased source now lives in
// texel (0,0) of A, read back through an exact C load: every pixel computes the same glide,
// only (0,0) stores it, and that one texel is masked out of the smoke history.

// History reads are exact textureLoad with a manual bilinear (no filtering sampler on feedback).
// The sample position convention is HEAD's on purpose: uv = pixel / res (no +0.5) means every
// frame averages a texel with its up-left neighbour, which is where the smoke's diffusion comes from.
fn historyTexel(c: vec2<i32>, hi: vec2<i32>) -> vec4<f32> {
    let cc = clamp(c, vec2<i32>(0), hi);
    let isState = f32(cc.x == 0 && cc.y == 0);
    return textureLoad(dataTextureC, cc, 0) * (1.0 - isState);
}

fn historyBilinear(uvp: vec2<f32>, res: vec2<f32>) -> vec4<f32> {
    let p = clamp(uvp, vec2<f32>(0.0), vec2<f32>(1.0)) * res - vec2<f32>(0.5);
    let i0 = vec2<i32>(floor(p));
    let f = p - floor(p);
    let hi = vec2<i32>(res) - vec2<i32>(1);
    let a = historyTexel(i0, hi);
    let b = historyTexel(i0 + vec2<i32>(1, 0), hi);
    let c = historyTexel(i0 + vec2<i32>(0, 1), hi);
    let d = historyTexel(i0 + vec2<i32>(1, 1), hi);
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let rawMouse = u.zoom_config.yz;

    // Wind source: first-order glide chasing the raw cursor (rate 8 ~ HEAD's critically damped
    // spring), state carried in A(0,0) = (x, y, 7, fract(time)).
    let glideState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let hasGlide = abs(glideState.z - 7.0) < 0.01;
    let frameT = fract(time);
    let glideDt = clamp(frameT - glideState.w + select(0.0, 1.0, frameT < glideState.w), 0.0, 0.1);
    let glideK = 1.0 - exp(-8.0 * glideDt);
    let windSource = select(rawMouse, glideState.xy + (rawMouse - glideState.xy) * glideK, hasGlide);

    // Audio — rescue R2: HEAD read plasmaBuffer[1..8], which is not audio. Bass/mids/treble live in [0].
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    var windStrength = mix(0.5, 5.0, u.zoom_params.x);
    let decay = mix(0.8, 0.995, u.zoom_params.y);
    let chromaSplit = u.zoom_params.z * 0.02; // Small offset
    let sourceMix = mix(0.01, 0.2, u.zoom_params.w);

    // Bass gusts: the wind rides the low end, so drops push the smoke
    windStrength = windStrength * (1.0 + bass * 0.6);

    // Light = smoke = fast. Dark = heavy = slow.
    let currentFrame = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(currentFrame.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Wind blows AWAY from the source.
    let dVec = uv - windSource;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
    let mouseInfluence = smoothstep(0.5, 0.0, dist);

    // Base drift (upwards slightly like smoke) + mouse wind
    let baseWind = vec2<f32>(0.0, -0.001);
    let dVecAspect = dVec * vec2<f32>(aspect, 1.0);
    let mouseDirAspect = dVecAspect / max(dist, 0.0001);
    let mouseDir = mouseDirAspect / vec2<f32>(aspect, 1.0);
    let mouseWind = mouseDir * 0.01 * mouseInfluence * windStrength;

    // ── Idea 2: spiral outflow ───────────────────────────────────────
    // A fan or blower does not push purely radially: the stream leaves with swirl, so the
    // repulsion curls into spiral arms. Same falloff, same Wind Force scaling, 40 % of the
    // radial push; the perpendicular is taken in aspect-corrected space so arms stay round.
    let swirlAspect = vec2<f32>(-mouseDirAspect.y, mouseDirAspect.x);
    let swirlWind = (swirlAspect / vec2<f32>(aspect, 1.0)) * 0.01 * mouseInfluence * windStrength * 0.4;

    // Final velocity for this pixel. If luma is high, it moves more.
    var velocity = (baseWind + mouseWind + swirlWind) * (luma * 2.0);

    // Click gust bursts: each live ripple adds a decaying radial gust from
    // its click point, so clicks blow puffs of smoke (~1.5s lifetime).
    // config.y = ripple COUNT.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleAge = u.config.x - ripple.z;
        if (rippleAge >= 0.0 && rippleAge < 1.5) {
            let rVec = uv - ripple.xy;
            let rVecAspect = vec2<f32>(rVec.x * aspect, rVec.y);
            let distR = length(rVecAspect);
            let dirR = (rVecAspect / max(distR, 0.0001)) / vec2<f32>(aspect, 1.0);
            let gustFalloff = smoothstep(0.35, 0.0, distR);
            velocity = velocity + dirR * 0.02 * exp(-rippleAge * 2.0) * gustFalloff;
        }
    }

    // ── Idea 1: edge-tangent flow ────────────────────────────────────
    // Smoke cannot cross a dark, heavy object — it slides along its outline. The luma gradient
    // of the live frame (4 taps, 2 px apart) is the edge normal; the velocity component along
    // it is removed in proportion to edge strength. Done in pixel space, then converted back.
    let tap = 2.0 / resolution;
    let lumaW = vec3<f32>(0.299, 0.587, 0.114);
    let lumaR = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(tap.x, 0.0), 0.0).rgb, lumaW);
    let lumaL = dot(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(tap.x, 0.0), 0.0).rgb, lumaW);
    let lumaD = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, tap.y), 0.0).rgb, lumaW);
    let lumaU = dot(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, tap.y), 0.0).rgb, lumaW);
    let lumaGrad = vec2<f32>(lumaR - lumaL, lumaD - lumaU) * 0.5;
    let gradMag = length(lumaGrad);
    let edgeNormal = lumaGrad / max(gradMag, 0.0001);
    let edgeStrength = smoothstep(0.015, 0.12, gradMag);
    let velPix = velocity * resolution;
    velocity = (velPix - edgeNormal * dot(velPix, edgeNormal) * edgeStrength * 0.85) / resolution;

    // Per-band flutter: 8 horizontal bands each wobble their velocity perpendicular component,
    // so the trail flickers across the spectrum. Rescue R2: bands now follow the real audio —
    // low bands ride bass, middle bands mids, high bands treble — with alternating sign.
    let band = min(u32(uv.y * 8.0), 7u);
    let bandT = f32(band) / 7.0;
    let bandAudio = mix(mix(bass, mids, smoothstep(0.0, 0.5, bandT)), treble, smoothstep(0.5, 1.0, bandT));
    let flutter = bandAudio * select(-1.0, 1.0, (band & 1u) == 0u) * 0.003;
    let flowLen = max(length(velocity), 0.00001);
    let perpDir = vec2<f32>(-velocity.y, velocity.x) / flowLen;
    velocity = velocity + perpDir * flutter;

    // To simulate advection, we sample FROM (uv - velocity): the smoke at uv came from there.
    // Chromatic Advection: Sample R, G, B from slightly different locations
    let offsetR = velocity * (1.0 + chromaSplit);
    let offsetG = velocity;
    let offsetB = velocity * (1.0 - chromaSplit);

    let prevR = historyBilinear(uv - offsetR, resolution).r;
    let prevG = historyBilinear(uv - offsetG, resolution).g;
    let prevB = historyBilinear(uv - offsetB, resolution).b;
    let historyColor = vec3<f32>(prevR, prevG, prevB);

    // Mix new source. Bright = inject more source (smoke generation); dark = less (transparent).
    let injectAmount = sourceMix * luma;

    var finalColor = mix(historyColor * decay, currentFrame.rgb, injectAmount);
    finalColor = max(vec3<f32>(0.0), finalColor);

    // Sample depth for alpha calculation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Calculate luminance-based alpha
    let lumaFinal = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = mix(0.7, 1.0, lumaFinal);
    let finalAlpha = mix(alpha * 0.8, alpha, depth);

    // Store to history (A) and Display (Write). Texel (0,0) of A carries the wind-source glide.
    let isStateTexel = global_id.x == 0u && global_id.y == 0u;
    let trail = vec4<f32>(finalColor, finalAlpha);
    let aOut = select(trail, vec4<f32>(windSource, 7.0, frameT), isStateTexel);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), aOut);
    textureStore(writeTexture, vec2<i32>(global_id.xy), trail);

    // Pass depth
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
