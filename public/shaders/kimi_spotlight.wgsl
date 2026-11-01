// ═══════════════════════════════════════════════════════════════════
//  Kimi Spotlight
//  Category: interactive-mouse
//  Features: mouse-driven, interactive, spotlight, reveal, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-06-28 (alpha) / 2026-07-30 (Interactivist pass) / 2026-10-31
//  Ideas: spring-damped beam; click light rings; soft inverse-square inside the gate (§12.2F); Airy rings on the hotspot (§12.2F)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn airy(x: f32) -> f32 {
  let xs = clamp(abs(x), 1e-4, 8.0);
  let j1 = xs * (0.5 - xs * xs * (0.0625 - xs * xs * (0.0026042 - xs * xs * 0.0000543)));
  let v = 2.0 * j1 / xs;
  return select(0.0, v * v, abs(x) <= 8.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    // Per-bin treble (high FFT bins) for the beam-rim flicker.
    let trebleBins = (plasmaBuffer[6].x + plasmaBuffer[7].x + plasmaBuffer[8].x) * 0.333333;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let aspect = resolution.x / resolution.y;
    let p = vec2<f32>(uv.x * aspect, uv.y);

    // ── Critically-damped spring: beam glides toward the cursor ──────
    // extraBuffer map (persistent state lives in [133..255] ONLY):
    //   [133..134] = spring position (uv), [135..136] = spring velocity,
    //   [137] = last time, [138] = init flag. [0..4] reserved,
    //   [5..132] engine FFT bins - untouched.
    let hasState = (arrayLength(&extraBuffer) > 138u);
    var spotCenter = vec2<f32>(0.5, 0.5);
    if (hasState) {
        if (extraBuffer[138] > 0.5) {
            spotCenter = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        }
    }
    let isWriter = ((global_id.x == 0u) && (global_id.y == 0u));
    if (isWriter && hasState) {
        let lastTime = extraBuffer[137];
        let dt = clamp(time - lastTime, 0.0, 0.1);
        var sPos = spotCenter;
        var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[138] < 0.5) {
            sVel = vec2<f32>(0.0, 0.0);
        }
        // Negative mouse sentinel = cursor inactive: glide back to center.
        let springTarget = select(mouse, vec2<f32>(0.5, 0.5), mouse.x < 0.0);
        // Critical damping: c = 2 * sqrt(k) = 12 for k = 36.
        let stiffness = 36.0;
        let damping = 12.0;
        let accel = (springTarget - sPos) * stiffness - sVel * damping;
        sVel = sVel + accel * dt;
        sPos = sPos + sVel * dt;
        extraBuffer[133] = sPos.x;
        extraBuffer[134] = sPos.y;
        extraBuffer[135] = sVel.x;
        extraBuffer[136] = sVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
    }

    let mousePos = vec2<f32>(spotCenter.x * aspect, spotCenter.y);

    let dist = length(p - mousePos);

    let spotSize = mix(0.1, 0.6, clamp(u.zoom_params.x, 0.0, 1.0)) * (1.0 + bass * 0.15 + mids * 0.05);
    let spotSoftness = max(mix(0.001, 0.5, clamp(u.zoom_params.y, 0.0, 1.0)), 0.001);
    let edgeDarkness = mix(0.1, 1.0, clamp(u.zoom_params.z, 0.0, 1.0));
    let saturationBoost = mix(1.0, 3.0, clamp(u.zoom_params.w, 0.0, 1.0));

    var spotlight = 1.0 - smoothstep(spotSize - spotSoftness, spotSize + spotSoftness, dist);

    // ── Idea 1: soft inverse-square inside the gate (§12.2F) ────────
    // The smoothstep radius is still spot size. The axis is brighter.
    let coreR = max(spotSize * 0.55, 0.02);
    let invSq = 1.0 / ((dist * dist) / (coreR * coreR) + 1.0);
    let spotBody = spotlight * mix(0.62, 1.0, invSq);

    // Click pulse stays applied AFTER the spring (hand-tuned, verbatim).
    let clickPulse = mouseDown * sin(time * 10.0) * 0.1;
    spotlight = clamp(min(1.0, spotlight + clickPulse), 0.0, 1.0);

    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    let gray = dot(original.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let desaturated = vec3<f32>(gray) * 0.3;

    let luminance = dot(original.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let saturated = mix(vec3<f32>(luminance), original.rgb, saturationBoost);

    // ── Click light rings: expanding luminous reveal from each click ──
    var ringGlow = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age > 0.0 && age < 2.0) {
            let rPos = vec2<f32>(ripple.x * aspect, ripple.y);
            let rDist = length(p - rPos);
            let ringRadius = age * 0.4;
            let ringBand = smoothstep(0.08, 0.0, abs(rDist - ringRadius));
            let ringFade = exp(-age * 2.0);
            ringGlow = ringGlow + ringBand * ringFade;
        }
    }
    ringGlow = clamp(ringGlow, 0.0, 1.0);

    // Rings locally lift the desaturated darkness (flash-reveal), while the
    // desaturate-outside / saturate-inside mix structure stays intact.
    let reveal = clamp(spotBody + clickPulse + ringGlow * 0.85, 0.0, 1.0);
    var color = mix(desaturated * edgeDarkness, saturated, reveal);
    color = color + vec3<f32>(0.9, 0.95, 1.0) * ringGlow * 0.15;

    // Beam ring band (hand-tuned core kept verbatim) + per-bin treble flicker.
    let rimFlicker = 1.0 + trebleBins * (0.6 + 0.4 * sin(time * 24.0 + dist * 20.0));
    let beamWidth = max(spotSize * 0.1, 0.001);
    let beamDist = abs(dist - spotSize * 0.8);
    let beam = smoothstep(beamWidth, 0.0, beamDist) * 0.2 * spotlight * rimFlicker;
    color = color + vec3<f32>(0.9, 0.95, 1.0) * beam;

    // Hotspot term (hand-tuned, verbatim) plus Airy rings at the focus.
    let hotspot = smoothstep(spotSize * 0.3, 0.0, dist) * 0.3;
    // ── Idea 2: Airy rings on the hotspot (§12.2F) ──────────────────
    let airyX = dist / max(spotSize * 0.12, 0.004);
    let airyRings = airy(airyX) * spotlight;
    color = color + vec3<f32>(hotspot);
    color = color + vec3<f32>(0.90, 0.95, 1.0) * airyRings * 0.22;

    let noise = fract(sin(dot(uv * max(time, 0.001), vec2<f32>(12.9898, 78.233))) * 43758.5453);
    color = color + (noise - 0.5) * 0.02 * (1.0 - spotlight);

    let alpha = clamp(original.a * (spotlight * 0.7 + hotspot * 0.2 + beam * 0.1 + airyRings * 0.08 + 0.15 + treble * 0.05), 0.0, 1.0);

    let finalRGBA = vec4<f32>(aces(max(color, vec3<f32>(0.0))), alpha);

    // Honest depth: real bump inside the spot instead of pure passthrough.
    let depthIn = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depth = clamp(depthIn + spotlight * 0.05, 0.0, 1.0);
    textureStore(writeTexture, coords, finalRGBA);
    textureStore(dataTextureA, global_id.xy, finalRGBA);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
