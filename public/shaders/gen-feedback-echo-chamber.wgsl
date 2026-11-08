// ═══════════════════════════════════════════════════════════════════
//  Gen Feedback Echo Chamber
//  Category: feedback/temporal
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-11, 2026-11-08
//  Ideas: harmonic echo ladder at integer 2x spacing taps; standing-wave nodal interference from echo-count phase field; early wall reflections; comb-filter notches; frequency-dependent echo decay (highs die first, red carries the tail); second-order image-source corner reflections
//  Rescues 2026-11-08 (not ideas): ACES-on-ACES feedback compounding (A now raw) + double decay removed; bass envelope moved from dead extraBuffer[133] to A.a; treble sparkle was a uniform veil, now sparse
//  A packing: A.rgb = raw pre-ACES accumulated trail (convex mix, unity gain), A.a = smoothed bass envelope; ACES only on writeTexture (was ACES display RGBA)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i: i32 = 0; i < oct; i++) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Idea 5: per-echo absorption (R, G, B) — highs die first in a real room, so the n-th echo keeps exp(-n*k) per channel (k = 0 / 0.5 / 1.2 for R / G / B).
const ECHO_ABSORB: vec3<f32> = vec3<f32>(0.0, 0.5, 1.2);

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn gravityWell(pos: vec2<f32>, wellPos: vec2<f32>, strength: f32) -> vec2<f32> {
    let d = wellPos - pos;
    let dist2 = dot(d, d) + 0.0001;
    return d * (strength / dist2);
}

fn psychedelicPalette(t: f32) -> vec3<f32> {
    let hue = fract(t);
    let sat = clamp(0.72 + 0.28 * sin(TAU * (t * 0.137 + 0.19)), 0.45, 1.0);
    let val = 1.0 + 0.18 * sin(TAU * (t * 0.071 + 0.43));
    let rgb = clamp(abs(fract(vec3<f32>(hue) + vec3<f32>(0.0, 0.6666667, 0.3333333)) * 6.0 - vec3<f32>(3.0)) - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
    let smoothRgb = rgb * rgb * (vec3<f32>(3.0) - 2.0 * rgb);
    return mix(vec3<f32>(val), smoothRgb * val, sat);
}

// Manual reconstruction uses only exact texel loads from the feedback ring.
fn loadHistoryExact(uv: vec2<f32>) -> vec4<f32> {
    let dims = vec2<i32>(textureDimensions(dataTextureC));
    let hi = dims - vec2<i32>(1);
    let p = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * vec2<f32>(dims) - vec2<f32>(0.5);
    let base = vec2<i32>(floor(p));
    let f = fract(p);
    let c00 = textureLoad(dataTextureC, clamp(base, vec2<i32>(0), hi), 0);
    let c10 = textureLoad(dataTextureC, clamp(base + vec2<i32>(1, 0), vec2<i32>(0), hi), 0);
    let c01 = textureLoad(dataTextureC, clamp(base + vec2<i32>(0, 1), vec2<i32>(0), hi), 0);
    let c11 = textureLoad(dataTextureC, clamp(base + vec2<i32>(1), vec2<i32>(0), hi), 0);
    return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let audio = plasmaBuffer[0];
    let bassRaw = audio.x;
    let mids = audio.y;
    let treble = audio.z;
    // RESCUE 2026-11-08: the envelope used to live in extraBuffer[133], which the app re-zeroes every frame (so bass was
    // always 0.8*raw). Every pixel now replays the same recurrence from its own C.a.
    let prev = textureLoad(dataTextureC, pixel, 0);
    let prevEnv = clamp(prev.a, 0.0, 2.0);
    let bass = bass_env(prevEnv, bassRaw, 0.8, 0.15);

    let echoCount = i32(round(mix(2.0, 8.0, clamp(u.zoom_params.x, 0.0, 1.0))));
    let decayRate = mix(0.55, 0.94, clamp(u.zoom_params.y, 0.0, 1.0));
    let echoSpacing = mix(0.002, 0.06, clamp(u.zoom_params.z, 0.0, 1.0));
    let colorShift = u.zoom_params.w;

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let video = textureSampleLevel(readTexture, u_sampler, uv01, 0.0);

    // Luma-keyed spawn from bright video regions
    let lumaVid = luma(video.rgb);
    let spawnMask = smoothstep(0.45, 0.85, lumaVid) * (0.25 + treble * 0.75);

    // Mouse gravity well + fBM domain-warped drift
    let gWell = gravityWell(uv01, mouse, 0.015 + mouseDown * 0.055);
    var warpedUV = uv01 + gWell * (0.02 + echoSpacing * 2.0);

    // Distance-aware LOD: fewer octaves in the periphery
    let focusDist = length(uv01 - vec2<f32>(0.5));
    let lodOct = i32(clamp(3.0 - focusDist * 2.0, 1.0, 3.0));

    // Cached fBM: one noise field drives both drift and palette
    let driftTime = time * 0.2;
    let noiseBase = warpedUV * 8.0;
    let driftA = fbm(noiseBase + vec2<f32>(driftTime, 0.0), lodOct);
    let driftB = fbm(noiseBase + vec2<f32>(5.2 - driftTime * 0.85, 1.3), lodOct);
    let drift = vec2<f32>(driftA, driftB);
    warpedUV += drift * (0.015 + mids * 0.02);

    // Echo displacement from feedback
    let wobble = vec2<f32>(
        sin(time * 0.5 * (1.0 + mids * 0.3) + warpedUV.y * 6.0) * echoSpacing * (1.0 + bass * 0.3),
        cos(time * 0.35 * (1.0 + mids * 0.3) + warpedUV.x * 6.0) * echoSpacing * (1.0 + bass * 0.2)
    );
    var echoAccum = vec3<f32>(0.0);
    var totalWeight = vec3<f32>(0.0);
    var echoWeight = 1.0;
    for (var echoIndex = 1; echoIndex <= 8; echoIndex++) {
        if (echoIndex > echoCount) { break; }
        echoWeight *= decayRate;
        let fi = f32(echoIndex);
        let echoUV = fract(warpedUV + wobble * fi + vec2<f32>(driftB - 0.5, driftA - 0.5) * echoSpacing * fi);
        // ── Idea 5: frequency-dependent decay — per-channel weight and per-channel normalisation (energy-neutral):
        // blue is carried by the near echoes only, red by the whole tail, so trails go warm and blue fringes the lead.
        let echoW3 = echoWeight * exp(-fi * ECHO_ABSORB);
        echoAccum += loadHistoryExact(echoUV).rgb * echoW3;
        totalWeight += echoW3;
    }

    // Harmonic echo ladder at integer 2x spacing taps (musical delay)
    var harmonicWeight = 0.0;
    for (var harmonic = 1; harmonic <= 4; harmonic++) {
        let hi = f32(harmonic);
        let ladderSpacing = echoSpacing * hi * 2.0;
        let ladderUV = fract(warpedUV + wobble * hi * 2.0 + vec2<f32>(ladderSpacing, ladderSpacing * 0.5));
        let hw = decayRate * pow(0.62, hi);
        echoAccum += loadHistoryExact(ladderUV).rgb * hw;
        harmonicWeight += hw;
    }
    totalWeight += vec3<f32>(harmonicWeight);

    // Early wall reflections — one mirror tap off each frame edge, dimmer than the delay ladder.
    let wallGain = decayRate * 0.28 * (0.7 + bass * 0.4);
    let mirrorL = fract(vec2<f32>(-warpedUV.x, warpedUV.y) + vec2<f32>(echoSpacing, 0.0) + wobble);
    let mirrorR = fract(vec2<f32>(2.0 - warpedUV.x, warpedUV.y) - vec2<f32>(echoSpacing, 0.0) + wobble);
    let mirrorT = fract(vec2<f32>(warpedUV.x, -warpedUV.y) + vec2<f32>(0.0, echoSpacing) + wobble);
    let mirrorB = fract(vec2<f32>(warpedUV.x, 2.0 - warpedUV.y) - vec2<f32>(0.0, echoSpacing) + wobble);
    echoAccum += loadHistoryExact(mirrorL).rgb * wallGain;
    echoAccum += loadHistoryExact(mirrorR).rgb * wallGain;
    echoAccum += loadHistoryExact(mirrorT).rgb * wallGain * 0.85;
    echoAccum += loadHistoryExact(mirrorB).rgb * wallGain * 0.85;
    totalWeight += vec3<f32>(wallGain * 3.7);

    // ── Idea 6: second-order image sources — the corner images (both axes mirrored), one more bounce off the walls
    // above. Each corner image is seen off two walls at once, so it is weighted 2x one (deliberately quiet) wall tap.
    let cornerGain = wallGain * 2.0;
    let sp = vec2<f32>(echoSpacing);
    let cornerLT = fract(vec2<f32>(-warpedUV.x, -warpedUV.y) + sp + wobble);
    let cornerRT = fract(vec2<f32>(2.0 - warpedUV.x, -warpedUV.y) + vec2<f32>(-echoSpacing, echoSpacing) + wobble);
    let cornerLB = fract(vec2<f32>(-warpedUV.x, 2.0 - warpedUV.y) + vec2<f32>(echoSpacing, -echoSpacing) + wobble);
    let cornerRB = fract(vec2<f32>(2.0 - warpedUV.x, 2.0 - warpedUV.y) - sp + wobble);
    echoAccum += (loadHistoryExact(cornerLT).rgb + loadHistoryExact(cornerRT).rgb
                + loadHistoryExact(cornerLB).rgb + loadHistoryExact(cornerRB).rgb) * cornerGain;
    totalWeight += vec3<f32>(cornerGain * 4.0);

    let echo = echoAccum / max(totalWeight, vec3<f32>(0.0001));

    // Psychedelic generative color (reuses cached drift noise)
    let paletteT = time * 0.08 + driftA * 0.7 + driftB * 0.3 + bass * 0.5 + colorShift;
    let genColor = psychedelicPalette(paletteT) * (0.8 + mids * 0.35);

    // Standing-wave nodal interference from echo-count phase field
    let nodePhase = f32(echoCount) * 0.5;
    let standingWave = sin(warpedUV.x * nodePhase * TAU + time * 0.42) * sin(warpedUV.y * nodePhase * TAU * 0.72 - time * 0.31);
    let nodalMask = pow(abs(standingWave), 2.8);

    // Depth-aware blend: effect breathes in background, foreground stays crisp
    let fog = 1.0 - exp(-depth * (2.0 + decayRate * 3.0));
    var blended = mix(echo, genColor, 0.25 + spawnMask * 0.4 + bass * 0.15);
    blended = mix(blended, echo * (1.0 - nodalMask * 0.35), nodalMask * 0.28);
    var color = mix(blended, video.rgb, 0.15 + fog * 0.35);
    color += genColor * nodalMask * 0.1 * (1.0 + bass * 0.25);

    // Comb-filter notches — dark bands whose spacing follows the echo-spacing slider.
    let combFreq = TAU / max(echoSpacing * 40.0, 0.08);
    let comb = 0.5 + 0.5 * cos(warpedUV.x * combFreq + time * (0.4 + mids * 0.6));
    let notch = 1.0 - smoothstep(0.08, 0.28, comb);
    color = color * (1.0 - notch * 0.42 * (0.35 + treble * 0.4));

    // Click shockwave burst
    let clickDist = length(uv01 - mouse);
    let shockwave = mouseDown * exp(-clickDist * clickDist * 350.0) * sin(clickDist * 55.0 - time * 10.0);
    color += vec3<f32>(1.0, 0.75, 0.35) * shockwave * (1.0 + bass * 2.0);
    let rippleCount = min(i32(u.config.y), 50);
    for (var ri = 0; ri < rippleCount; ri++) {
        let event = u.ripples[ri];
        let age = time - event.z;
        if (age > 0.0 && age < 2.5) {
            let radius = age * (0.25 + echoSpacing * 2.0);
            let ring = exp(-abs(distance(uv01, event.xy) - radius) * 100.0) * exp(-age * 1.7) * event.w;
            color += psychedelicPalette(colorShift + age * 0.2) * ring * (0.5 + bass);
        }
    }

    // Treble sparkle
    // RESCUE 2026-11-08: was `hash * treble * 1.5` on every pixel — a uniform white veil that whitened the whole frame as
    // treble rose (meanL 0.49 -> 0.86 from silence to loud). Now sparse points, like the name says.
    color += smoothstep(0.93, 1.0, hash21(uv01 * 200.0 + time * 3.0)) * treble * 3.0;

    // Temporal accumulation with stable branchless feedback
    // RESCUE 2026-11-08: A is now the raw trail. HEAD stored the ACES result, re-ACES'd it every frame and also multiplied
    // by decayRate on top of the mix (steady-state gain 0.13-0.28 of the input, pumped back up by the compounding) —
    // a flat grey wash. Plain convex mix: unity gain, stable because `color` is itself a convex blend of echo/palette/video.
    let accMix = 0.08 + (1.0 - decayRate) * 0.2;
    let accColor = clamp(mix(prev.rgb, color, accMix), vec3<f32>(0.0), vec3<f32>(8.0));

    // Chromatic aberration + tone map
    let delta = uv01 - vec2<f32>(0.5);
    let lenSq = max(dot(delta, delta), 0.000001);
    let dir = delta * (1.0 / sqrt(lenSq));
    let caStr = 0.0025 * (1.0 + bass) + depth * 0.0015;
    let shift = dir * caStr;
    color = max(vec3<f32>(accColor.r + shift.x, accColor.g, accColor.b - shift.y * 0.5), vec3<f32>(0.0));
    color = acesToneMap(color * (1.1 + bass * 0.25));

    // Semantic alpha: interaction intensity + trail density
    let alpha = clamp(luma(color) + spawnMask * 0.35 + abs(shockwave) * 0.5, 0.1, 0.95);
    let output = vec4<f32>(color, alpha);

    textureStore(dataTextureA, pixel, vec4<f32>(accColor, bass));
    textureStore(writeTexture, pixel, output);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
