// ═══════════════════════════════════════════════════════════════════
//  Temporal RGB Smear — Interactivist Upgrade
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, temporal, depth-aware,
//            curl-noise, domain-warp, aces-tone-map, semantic-alpha,
//            alpha-layered, luminance-key, edge-preserve, accumulative,
//            mouse-velocity-spring, treble-sparkle-grain, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-08
//  Ideas: highlight-led comet streaks; curved streamline smear taps;
//         bass ghost-hold (decay surges on kicks)
//  A packing: rgb = clamped pre-ACES history, a = layered alpha;
//             texel (0,0) = spring pos.xy/vel.xy, texel (1,0) = (time, init)
//
//  Interactivist upgrade notes:
//   - Mouse velocity tracked with a spring-damper in extraBuffer; the
//     smear direction leans into fast mouse motion and settles smoothly.
//   - Feedback history is clamped pre-write (Feedback Clamp slider) so
//     the temporal loop can never blow up (luma-echo-warp lesson).
//   - Treble-reactive sparkle grain (plasmaBuffer[0].z) adds fine
//     animated film grain over the whole frame.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=SmearLength, y=SmearDecay, z=ChromaticSplit, w=Turbulence

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;


// ── Hash & noise ──────────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
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

// ── Divergence-free velocity field ────────────────────────────────
fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.001;
    let nx = fbm(p + vec2<f32>(0.0, eps), 3) - fbm(p - vec2<f32>(0.0, eps), 3);
    let ny = fbm(p + vec2<f32>(eps, 0.0), 3) - fbm(p - vec2<f32>(eps, 0.0), 3);
    return vec2<f32>(nx, -ny) / (2.0 * eps);
}

// ── Domain-warped organic drift ───────────────────────────────────
fn warpedDrift(uv: vec2<f32>, time: f32, strength: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(uv + vec2<f32>(0.0, time * 0.11), 3),
                      fbm(uv + vec2<f32>(5.2, 1.3) - time * 0.08, 3));
    let r = vec2<f32>(fbm(uv * 1.3 + q * 2.0 + vec2<f32>(1.7, 9.2), 2),
                      fbm(uv * 1.1 - q.yx * 2.0 + vec2<f32>(8.1, 2.8), 2));
    return (q + r * 0.5) * strength;
}

// ── Quasi-random Halton jitter ────────────────────────────────────
fn halton(i: u32, base: u32) -> f32 {
    var f = 1.0;
    var r = 0.0;
    var idx = i;
    loop {
        if (idx == 0u) { break; }
        f = f / f32(base);
        r = r + f * f32(idx % base);
        idx = idx / base;
    }
    return r;
}

// ── Color utilities ───────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ── Treble-reactive sparkle grain ─────────────────────────────────
// Fine animated grain; two decorrelated hashes per pixel per frame so
// highlights and shadows shimmer independently. Intensity follows treble.
fn sparkleGrain(pixel: vec2<i32>, time: f32, treble: f32, amount: f32) -> f32 {
    let cell = vec2<f32>(pixel);
    let t0 = floor(time * 24.0);
    let t1 = t0 + 1.0;
    let tFrac = fract(time * 24.0);
    let g0 = hash21(cell * 0.7131 + vec2<f32>(t0 * 17.17, t0 * 9.31));
    let g1 = hash21(cell * 0.7131 + vec2<f32>(t1 * 17.17, t1 * 9.31));
    let grain = mix(g0, g1, tFrac) - 0.5;
    let shimmer = 0.35 + 0.65 * clamp(treble, 0.0, 2.0) * 0.5;
    return grain * amount * shimmer;
}

// ── Advanced alpha compositing ────────────────────────────────────
fn compositeAlpha(color: vec3<f32>, depth: f32, motion: f32,
                  displ: f32, split: f32, historyA: f32, decay: f32) -> f32 {
    let Y = luma(color);

    // Luminance key: dark trails recede
    let lumaKey = smoothstep(0.03, 0.22, Y);

    // Edge preserve: high motion / gradient regions stay opaque
    let edgeMask = smoothstep(0.0, 0.08, motion + displ * 5.0);

    // Effect intensity: alpha scales with displacement and chromatic split
    let effectAlpha = smoothstep(0.0, 0.14, displ + split * 0.6);

    // Depth-layered: far pixels fade to let background breathe
    let depthAlpha = mix(0.5, 1.0, 1.0 - depth * 0.4);

    // Accumulative paint: previous frame alpha feeds back like pigment
    let trailAlpha = historyA * decay * 0.96;

    var alpha = lumaKey;
    alpha = mix(alpha, edgeMask, 0.35);
    alpha = mix(alpha, effectAlpha, 0.25);
    alpha = alpha * depthAlpha;
    alpha = max(alpha, trailAlpha * 0.9);
    return clamp(alpha, 0.12, 0.98);
}

// ═══════════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    // config.y is the ripple COUNT, not dt (old dt was 0 → frozen spring).
    let clock = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
    let initialized = clock.y > 0.5;
    let dt = select(0.016, clamp(time - clock.x, 0.001, 0.1), initialized);

    // ── Slider params (match the JSON params[] ids) ─────────────
    let p1 = u.zoom_params.x;                              // smear_length
    let decayCtl = clamp(u.zoom_params.y, 0.0, 1.0);       // smear_decay
    let splitCtl = clamp(u.zoom_params.z, 0.0, 1.0);       // chromatic_split
    let turbulence = clamp(u.zoom_params.w, 0.0, 1.0);     // turbulence
    // Former sliders, pinned at the values the JSON defaults produced.
    let springCtl = 0.7;
    let sparkleAmt = 0.5;
    let clampMax = 1.0;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Mouse-velocity spring-damper (persistent state) ─────────
    // Spring stiffness/damping scale with the Mouse Spring slider:
    // low = loose & floaty, high = tight & snappy.
    // State lives in A texel (0,0): extraBuffer is re-uploaded by the host
    // every frame and every thread wrote it (dead + racy spring).
    let springTexel = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    var smoothMouse = springTexel.xy;
    var mouseVel = springTexel.zw;
    if (!initialized) {
        smoothMouse = mouse;
        mouseVel = vec2<f32>(0.0);
    }
    let springK = mix(18.0, 90.0, springCtl);
    let damping = mix(5.0, 14.0, springCtl);
    let accel = (mouse - smoothMouse) * springK - mouseVel * damping;
    mouseVel = mouseVel + accel * dt;
    smoothMouse = smoothMouse + mouseVel * dt;

    mouseVel = clamp(mouseVel, vec2<f32>(-8.0), vec2<f32>(8.0));
    smoothMouse = clamp(smoothMouse, vec2<f32>(-0.5), vec2<f32>(1.5));

    // Velocity of the spring head drives an interactive smear lean
    let velMag = length(mouseVel);
    let velDir = normalize(mouseVel + vec2<f32>(0.0001));
    let velLean = smoothstep(0.15, 1.4, velMag);

    // Depth-aware scaling
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv01, 0.0).r;
    let depthFactor = mix(1.0, 0.3, depth);

    // Previous frame history + motion estimate from luminance gradient
    let texel = vec2<f32>(1.0) / res;
    let isState = global_id.y == 0u && global_id.x < 2u;
    let prev = select(textureSampleLevel(dataTextureC, non_filtering_sampler, uv01, 0.0),
                      vec4<f32>(0.4, 0.4, 0.4, 0.5), isState);
    let hR = luma(textureSampleLevel(dataTextureC, non_filtering_sampler,
                                    uv01 + vec2<f32>(texel.x, 0.0), 0.0).rgb);
    let hL = luma(textureSampleLevel(dataTextureC, non_filtering_sampler,
                                    uv01 - vec2<f32>(texel.x, 0.0), 0.0).rgb);
    let hU = luma(textureSampleLevel(dataTextureC, non_filtering_sampler,
                                    uv01 + vec2<f32>(0.0, texel.y), 0.0).rgb);
    let hD = luma(textureSampleLevel(dataTextureC, non_filtering_sampler,
                                    uv01 - vec2<f32>(0.0, texel.y), 0.0).rgb);
    let grad = vec2<f32>((hR - hL) * 0.5, (hU - hD) * 0.5);
    let motionStrength = length(grad);
    let motionDir = normalize(grad + vec2<f32>(0.0001));

    // Base time direction blended with curl-noise swirl (turbulence fixed
    // at the legacy default 0.3; interactivity moved to the mouse spring)
    let timeAngle = time * 0.5 + turbulence * TAU;
    let timeDir = vec2<f32>(cos(timeAngle), sin(timeAngle));
    let curl = curl2D(uv * (2.0 + turbulence * 6.0) + time * 0.1, time * 0.2);
    let flowDir = normalize(mix(timeDir, curl, 0.4 + turbulence * 0.4));
    var smearDir = normalize(mix(flowDir, motionDir, smoothstep(0.0, 0.05, motionStrength)));
    // Fast mouse flicks bend the smear along the pointer velocity
    smearDir = normalize(mix(smearDir, velDir, velLean * 0.65));

    // Smear length + chromatic split, audio/depth modulated.
    // Mouse speed also stretches the smear a little for gestural feel.
    let smearLength = mix(0.01, 0.25, p1) * (1.0 + velLean * 0.35);
    let chromaticSplit = mix(0.0, 0.05, splitCtl) * (1.0 + mids * 0.5);
    // Idea: highlight-led comet streaks — bright source pixels throw
    // longer smears (long-exposure light trails); shadows stay short.
    let srcLuma = luma(textureSampleLevel(readTexture, u_sampler, uv01, 0.0).rgb);
    let comet = mix(0.65, 1.6, smoothstep(0.25, 0.85, srcLuma));
    let len = smearLength * (1.0 + bass * 0.3) * depthFactor * comet;

    // Domain-warped drift + Halton jitter for sample dithering
    let drift = warpedDrift(uv * 3.0, time, turbulence * 0.04);
    let jit = vec2<f32>(halton(global_id.x + global_id.y * 97u, 2u) - 0.5,
                        halton(global_id.x + global_id.y * 73u, 3u) - 0.5) * 0.002;

    let baseOff = uv01 + drift * len + jit;
    let offR = clamp(baseOff + smearDir * len * (1.0 + chromaticSplit), vec2<f32>(0.0), vec2<f32>(1.0));
    let offG = clamp(baseOff + smearDir * len, vec2<f32>(0.0), vec2<f32>(1.0));
    let offB = clamp(baseOff + smearDir * len * (1.0 - chromaticSplit), vec2<f32>(0.0), vec2<f32>(1.0));

    var colR = textureSampleLevel(readTexture, u_sampler, offR, 0.0).r;
    var colG = textureSampleLevel(readTexture, u_sampler, offG, 0.0).g;
    var colB = textureSampleLevel(readTexture, u_sampler, offB, 0.0).b;
    // Idea: curved streamline taps — two extra taps march further along
    // the curl field (re-evaluated at each tap), so streaks bend with the
    // turbulence instead of being straight offsets. Turbulence 0 = straight.
    var tapPos = offG;
    var tapDir = smearDir;
    var accum = vec3<f32>(colR, colG, colB);
    var wsum = 1.0;
    for (var k = 1; k <= 2; k++) {
        let c = curl2D(tapPos * 3.0 * (2.0 + turbulence * 6.0) + time * 0.1, time * 0.2);
        tapDir = normalize(mix(tapDir, normalize(c + vec2<f32>(0.0001)), turbulence * 0.6));
        tapPos = clamp(tapPos + tapDir * len * 0.5, vec2<f32>(0.0), vec2<f32>(1.0));
        let w = 0.55 / f32(k);
        let tr = textureSampleLevel(readTexture, u_sampler, clamp(tapPos + tapDir * len * chromaticSplit, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
        let tg = textureSampleLevel(readTexture, u_sampler, tapPos, 0.0).g;
        let tb = textureSampleLevel(readTexture, u_sampler, clamp(tapPos - tapDir * len * chromaticSplit, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
        accum += vec3<f32>(tr, tg, tb) * w;
        wsum += w;
    }
    let sampleRGB = accum / wsum;

    // Effect displacement magnitude drives intensity alpha
    let displ = length(offG - uv01);

    // Temporal feedback with per-channel decay variation (decay fixed at
    // the legacy default 0.7; stability is handled by the clamp below)
    let smearDecay = mix(0.3, 0.98, decayCtl); // default 0.7 → 0.776 (legacy)
    // Idea: bass ghost-hold — kicks surge the feedback toward a near-freeze
    // so the frame leaves a held ghost that bleeds out after the hit.
    let ghost = smoothstep(0.45, 0.9, bass);
    let fb = clamp(mix(smearDecay * (1.0 + bass * 0.08), 1.75, ghost), 0.0, 1.9);
    let channelDecay = vec3<f32>(fb * 0.52, fb * 0.45, fb * 0.5);
    var history = mix(sampleRGB, prev.rgb, channelDecay);

    // Treble sparkle near the smoothed pointer, plus full-frame grain
    let sparkle = treble * 0.25 * smoothstep(0.25, 0.0, distance(uv01, smoothMouse));
    history += vec3<f32>(sparkle);
    history += vec3<f32>(sparkleGrain(pixel, time, treble, sparkleAmt * 0.35));

    // ── Feedback stability: clamp pre-write (never run away) ────
    history = clamp(history, vec3<f32>(0.0), vec3<f32>(clampMax));

    // Final color: ACES tone map + semantic alpha driven by luma and depth
    let color = acesToneMap(history * (1.0 + mids * 0.15));

    // Layered alpha: luminance key + edge preserve + effect intensity + depth layer + accumulation
    let alpha = compositeAlpha(color, depth, motionStrength, displ, chromaticSplit, prev.a, smearDecay);

    // Store history ping for next frame, carrying the layered alpha for accumulation
    var stateOut = vec4<f32>(history, alpha);
    if (global_id.x == 0u && global_id.y == 0u) { stateOut = vec4<f32>(smoothMouse, mouseVel); }
    if (global_id.x == 1u && global_id.y == 0u) { stateOut = vec4<f32>(time, 1.0, 0.0, 0.0); }
    textureStore(dataTextureA, pixel, stateOut);

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
