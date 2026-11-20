// ═══════════════════════════════════════════════════════════════════
//  Chronos Brush
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal-painting, depth-aware-opacity, chromatic-brush, upgraded-rgba
//  Complexity: High
//  Chunks From: chronos-brush, bass_env, temporal-feedback
//  Created: 2024-01-01
//  Upgraded: 2026-06-28
//  Rewired: 2026-07-30 (Batch 17 - honest slider semantics, click-stamp blooms, paint/erase mode)
//  Upgraded: 2026-10-04, 2026-11-20
//  Ideas: chronophotograph shutter stamps; thaw drip of fading frozen paint; wet-edge pooling (§12.2C); dwell pressure (§12.2C)
//  A packing: raw feedback RGBA (never tonemapped); .a = paint freshness (decays with history). writeTexture adds the wet-edge rim (display only, never stored)
// ═══════════════════════════════════════════════════════════════════
//  Slider contract (labels now tell the truth):
//    x = Brush Size         -> brush radius (audio-boosted via bass_env)
//    y = Freeze Decay       -> history persistence (default 0.9 == legacy fade)
//    z = Time Edge Distort  -> temporal sinusoid wobble of the history sample UV
//    w = Mode (Paint/Erase) -> <=0.5 paints tinted strokes, >0.5 erases to live
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=BrushSize, y=FreezeDecay, z=TimeEdgeDistort, w=Mode

fn hash11(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    // zoom_config.w = mouseDown (available, not needed by the legacy stroke).
    let clickCount = u.config.y;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthOpacity = mix(0.7, 1.0, depth);

    // ── Honest slider wiring ────────────────────────────────────────
    // x: Brush Size (unchanged semantic, still audio-boosted).
    let brushSize = mix(0.0, 1.0, clamp(u.zoom_params.x, 0.0, 1.0)) * bass_env(bass, mids);
    // y: Freeze Decay -> history persistence. Default 0.9 maps to the legacy
    //    fade constant (decay = 0.975 at silence); y=1.0 freezes forever.
    let freezeDecay = clamp(u.zoom_params.y, 0.0, 1.0);
    // z: Time Edge Distort -> amplitude of the temporal UV wobble (0 = off).
    let timeDistort = clamp(u.zoom_params.z, 0.0, 1.0);
    // w: Mode -> 0..0.5 paint (Freeze), 0.5..1 erase (Unfreeze).
    let eraseMode = u.zoom_params.w > 0.5;

    let aspect = resolution.x / resolution.y;
    let aspectCorrection = vec2<f32>(aspect, 1.0);
    let diff = (uv - mousePos) * aspectCorrection;
    let dist = length(diff);

    // Exact-load bounds shared by every history tap below.
    let maxCoord = vec2<i32>(resolution) - vec2<i32>(1);

    // Idea 4 — dwell pressure (§12.2C): a held pointer presses harder where it rests. The
    // pressure is read from the paint-freshness already stored under the cursor, so a brush
    // that lingers blooms (radius up to 1.6x, deeper freshness) while one sweeping over fresh
    // canvas stays thin. Real brush kinematics, no spring, no new state.
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let cursorCoord = clamp(vec2<i32>(mousePos * resolution), vec2<i32>(0), maxCoord);
    let cursorFresh = textureLoad(dataTextureC, cursorCoord, 0).a;
    let pressure = held * smoothstep(0.2, 0.9, cursorFresh);

    let radius = (0.02 + brushSize * 0.15) * (1.0 + 0.6 * pressure);
    let brush = 1.0 - smoothstep(radius * 0.8, radius, dist);

    // ── Temporal distortion: wobble the history fetch, not the live feed ──
    // Quadratic falloff keeps the low end (and the 0.5 default) gentle so the
    // painted look stays intact until the slider is pushed.
    let wobbleAmp = timeDistort * timeDistort * 0.012;
    let wobble = vec2<f32>(
        sin(uv.y * 23.0 + time * 1.7) + sin(uv.y * 7.0 - time * 0.9),
        cos(uv.x * 19.0 - time * 1.3) + cos(uv.x * 5.0 + time * 0.7)
    ) * wobbleAmp * 0.5;
    let historyUV = clamp(uv + wobble, vec2<f32>(0.0), vec2<f32>(1.0));

    // Exact history loads (rgba32float history must not go through a filtering sampler).
    let historyCoord = clamp(vec2<i32>(historyUV * resolution), vec2<i32>(0), maxCoord);
    let heldColor = textureLoad(dataTextureC, historyCoord, 0);

    // Idea 2 — thaw drip: frozen paint that has faded (low freshness in .a) slides down
    // a pixel per frame, column-jittered, so old time melts and runs before it vanishes.
    let above = textureLoad(dataTextureC, clamp(historyCoord - vec2<i32>(0, 1), vec2<i32>(0), maxCoord), 0);
    let aboveLuma = dot(above.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    let columnJitter = 0.4 + 0.6 * hash11(f32(global_id.x) + floor(time * 0.5) * 17.0);
    let notFresher = step(heldColor.a, above.a + 0.05);
    let thaw = smoothstep(0.75, 0.2, above.a) * smoothstep(0.01, 0.06, aboveLuma) * columnJitter * notFresher * (1.0 - freezeDecay * freezeDecay * 0.6);
    let historyColor = mix(heldColor, above, clamp(thaw * 0.5, 0.0, 1.0));
    let liveColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Chromatic brush: cycle HSL hue per click via time (legacy 0.45 rate).
    let hue = fract(sin(clickCount * 0.5 + time * 0.45 + bass * 0.1) * 43758.5453);
    let sat = 0.8 + mids * 0.2;
    let val = 0.9 + treble * 0.1;

    // HSV to RGB inline
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
    let brushTint = clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
    let tintColor = vec3<f32>(sat * val) * mix(vec3<f32>(val), brushTint, sat);

    let tintedLive = vec4<f32>(liveColor.rgb * tintColor, liveColor.a);

    // ── Click-stamp blooms: every live ripple dabs a soft round bloom ──
    // so single clicks paint even without dragging. Radius ~ brush * 1.5,
    // strength decays exponentially with age over a ~1.5s usable life.
    var stamp = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age < 0.0 || age > 3.0) { continue; }
        let rDiff = (uv - ripple.xy) * aspectCorrection;
        let rDist = length(rDiff);
        let rRadius = radius * 1.5;
        let bloom = 1.0 - smoothstep(rRadius * 0.5, rRadius, rDist);
        stamp = max(stamp, bloom * exp(-age * 2.0));
    }

    // Idea 1 — chronophotograph shutter: the brush exposes at full strength only on
    // shutter ticks (8 Hz; bass holds the shutter open longer), so a drag leaves a
    // Marey-style row of frozen frames and a resting brush shows the live feed stepping.
    // The rate stays fixed: scaling `time` by an audio term would jump the phase at large t.
    let shutterOpen = select(0.18, 1.0, fract(time * 8.0) < 0.22 + bass * 0.18);
    let shutter = select(shutterOpen, 1.0, eraseMode);

    // Click blooms merge with the drag stroke into one paint mask.
    let brushMask = max(brush * shutter, stamp);

    // ── History update (RAW feedback - never tonemapped) ────────────
    let decay = 1.0 - (1.0 - freezeDecay) * 0.25 * (1.0 - bass * 0.03);
    var newHistoryColor = historyColor * decay;

    let mixFactor = brushMask * depthOpacity * (1.0 + bass * 0.3);
    if (eraseMode) {
        // Unfreeze: brush strokes thaw history back toward the live frame.
        newHistoryColor = mix(newHistoryColor, liveColor, mixFactor);
    } else {
        // Freeze: brush strokes stamp chromatic tinted paint into history.
        newHistoryColor = mix(newHistoryColor, tintedLive, mixFactor);
    }

    let alpha = clamp(newHistoryColor.a + brushMask * (0.15 + 0.1 * pressure) + bass * 0.05, 0.0, 1.0);
    let finalColor = vec4<f32>(newHistoryColor.rgb, alpha);

    // Idea 3 — wet-edge pooling (§12.2C): pigment gathers at the boundary of a fresh stroke.
    // edge = max(-laplacian(a), 0) on the freshness field in C.a (5-point stencil, step follows
    // the brush's edge softness, 0.2 * radius): positive on the inner shoulder where the paint field turns over, so the
    // rim darkens and saturates. It rides `a` itself, so a drying stroke loses its rim on its own,
    // and a pressed brush (Idea 4) pools more. Display only: history in A is not touched, so
    // nothing accumulates frame to frame.
    let rimStep = clamp(i32(radius * 0.16 * resolution.y), 2, 12);
    let aL = textureLoad(dataTextureC, clamp(historyCoord + vec2<i32>(-rimStep, 0), vec2<i32>(0), maxCoord), 0).a;
    let aR = textureLoad(dataTextureC, clamp(historyCoord + vec2<i32>(rimStep, 0), vec2<i32>(0), maxCoord), 0).a;
    let aU = textureLoad(dataTextureC, clamp(historyCoord + vec2<i32>(0, -rimStep), vec2<i32>(0), maxCoord), 0).a;
    let aD = textureLoad(dataTextureC, clamp(historyCoord + vec2<i32>(0, rimStep), vec2<i32>(0), maxCoord), 0).a;
    let paintLap = aL + aR + aU + aD - 4.0 * heldColor.a;
    let pool = clamp(-paintLap * (5.0 + 2.5 * pressure), 0.0, 1.0) * smoothstep(0.08, 0.45, heldColor.a);
    let paintLuma = dot(finalColor.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    let pooled = mix(vec3<f32>(paintLuma), finalColor.rgb, 1.0 + 0.7 * pool) * (1.0 - 0.38 * pool);
    let shown = vec4<f32>(max(pooled, vec3<f32>(0.0)), alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), shown);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
