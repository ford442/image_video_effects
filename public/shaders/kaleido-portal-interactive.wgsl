// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
// ═══════════════════════════════════════════════════════════════════
//  Kaleido Portal Interactive
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, spring-portal,
//            click-spin-bursts, hdr-tamed
//  Complexity: Medium
//  Chunks From: kaleido-portal-interactive
//  Created: 2026-05-30
//  By: Copilot CLI
//  Upgraded: 2026-07-30, 2026-11-20
//  Ideas: portal lip; spin smear
//  A packing: raw portal tuple (mask, border, segments/16, alpha); ACES on writeTexture only
//  Spring center, click spin, and the soft-knee border glow stay.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
// zoom_params: x=Radius, y=Segments, z=Rotation, w=Hardness

// Persistent shader state in extraBuffer ([133..255] only; 0..132 are reserved/engine):
//   [133..134] = springed portal center (xy)
//   [135]      = last frame time (for dt)
//   [136..137] = spring velocity (xy)
//   [138]      = init flag (0.0 => uninitialized)
//   [139]      = spin phase accumulated from click bursts
// All invocations compute identical values, so the racy-but-identical writes are benign.

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    // --- Slider mapping (shader-specific constants of THIS algorithm) ---
    let radius = mix(0.1, 0.5, u.zoom_params.x) * (1.0 + bass * 0.12);
    let segments = floor(mix(3.0, 16.0, u.zoom_params.y) + treble * 2.0);
    let rotationSpeed = u.zoom_params.z * (0.5 + mids * 0.6);
    let hardness = mix(0.01, 0.2, u.zoom_params.w);

    // --- Frame dt (clamped so tab-switch pauses don't explode the spring) ---
    let dt = clamp(time - extraBuffer[135], 0.0, 0.05);
    extraBuffer[135] = time;

    // --- Technique 2: critically-damped spring on the portal center -------
    // Raw mouse is the spring target; the kaleidoscope glides toward it.
    let rawMouse = u.zoom_config.yz;
    var springCenter = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var springVel = vec2<f32>(extraBuffer[136], extraBuffer[137]);
    if (extraBuffer[138] < 0.5) {
        springCenter = rawMouse;
        springVel = vec2<f32>(0.0, 0.0);
        extraBuffer[138] = 1.0;
    }
    let springK = 90.0;                      // stiffness
    let springC = 2.0 * sqrt(springK);       // critical damping ratio = 1.0
    let springAccel = (rawMouse - springCenter) * springK - springVel * springC;
    springVel = springVel + springAccel * dt;
    springCenter = clamp(springCenter + springVel * dt, vec2<f32>(-0.1, -0.1), vec2<f32>(1.1, 1.1));
    extraBuffer[133] = springCenter.x;
    extraBuffer[134] = springCenter.y;
    extraBuffer[136] = springVel.x;
    extraBuffer[137] = springVel.y;

    // --- Technique 3: click counter-rotation bursts -----------------------
    // Each live ripple contributes a decaying angular velocity spike; the sign
    // alternates per ripple index so successive clicks spin opposite ways.
    var burstVel = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age > 0.0 && age < 2.0) {
            let dirSign = select(1.0, -1.0, (i & 1u) == 1u);
            // Sharp attack, ~2s exponential decay => a visible spin kick.
            let decay = exp(-age * 2.5) * (1.0 - age * 0.5);
            burstVel = burstVel + dirSign * decay * 6.0;
        }
    }
    // Integrate the burst velocity into a persistent spin phase so the mandala
    // winds down smoothly instead of snapping back when the burst ends.
    let spinPhase = extraBuffer[139] + burstVel * dt;
    extraBuffer[139] = spinPhase;

    // The springed center drives the portal; downstream fold math is verbatim.
    var mouse = springCenter;
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let mask = 1.0 - smoothstep(radius, radius + hardness, dist);

    var finalUV = uv;

    if (mask > 0.0) {
        let rel = uv - mouse;
        let relCorrected = rel * vec2<f32>(aspect, 1.0);
        var angle = atan2(relCorrected.y, relCorrected.x);
        let rad = length(relCorrected);
        let segmentAngle = 6.2831853 / max(segments, 1.0);

        angle = angle + time * rotationSpeed + spinPhase;
        if (angle < 0.0) {
            angle = angle + 6.2831853;
        }

        var a = angle % segmentAngle;
        if (a > segmentAngle * 0.5) {
            a = segmentAngle - a;
        }

        let newDir = vec2<f32>(cos(a), sin(a));
        let newRelCorrected = newDir * rad;
        let newRel = vec2<f32>(newRelCorrected.x / aspect, newRelCorrected.y);
        let kaleidoUV = clamp(mouse + newRel, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
        finalUV = mix(uv, kaleidoUV, mask);
    }

    // ── Idea 1: portal lip ────────────────────────────────────────
    // The circular edge is a glass lip. Hardness is the lip width.
    // Radius still places the portal.
    let lipLo = radius - max(hardness, 0.001) * 2.0;
    let lipHi = radius + max(hardness, 0.001);
    let lip = smoothstep(lipLo, radius, dist) * (1.0 - smoothstep(radius, lipHi, dist));
    let radialDir = distVec / max(dist, 0.0001);
    finalUV = clamp(finalUV + radialDir * lip * (0.01 + hardness * 0.035), vec2<f32>(0.001), vec2<f32>(0.999));

    let border = smoothstep(radius, radius + 0.01, dist) * (1.0 - smoothstep(radius + 0.01, radius + 0.02 + hardness, dist));

    // --- Technique 1 (PRIORITY): tame the HDR border glow ------------------
    // Was: border * (5.0 + bass * 2.0) added raw => up to ~7.0 in rgba32float.
    // Now: soft-knee compresses the hot core, then a hue-preserving cap at 1.5
    // keeps the border legal while bass still visibly pumps it.
    let borderGlowRaw = border * (5.0 + bass * 2.0);
    let borderGlowSoft = borderGlowRaw / (1.0 + borderGlowRaw * 0.35);
    let borderGlow = min(borderGlowSoft, 1.5);
    let borderColor = vec3<f32>(0.5 + treble * 0.2, 0.8 + mids * 0.15, 1.0);

    // ── Idea 2: spin smear ────────────────────────────────────────
    // Rotation and the click burst are already an angular velocity.
    let tang = vec2<f32>(-distVec.y, distVec.x) / max(dist, 0.0001);
    let smear = (abs(rotationSpeed) * 0.012 + abs(burstVel) * 0.0035) * mask;
    let smearUV = clamp(finalUV + tang * smear, vec2<f32>(0.001), vec2<f32>(0.999));
    let base = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
    let spun = textureSampleLevel(readTexture, u_sampler, smearUV, 0.0);
    let smearMix = clamp(smear * 28.0, 0.0, 0.55);
    var finalColor = mix(base.rgb, spun.rgb, smearMix) + borderColor * borderGlow;
    // Soft-knee border stays. Reinhard, then ACES on the display only.
    finalColor = finalColor / (1.0 + max(finalColor - vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(0.0, 0.0, 0.0)) * 0.3);
    finalColor = aces(max(finalColor, vec3<f32>(0.0)));

    let finalAlpha = clamp(base.a * (1.0 - mask * 0.25) + border * (0.32 + bass * 0.16) + mask * 0.18 + lip * 0.12, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV, 0.0).r + mask * 0.04, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(mask, border, segments / 16.0, finalAlpha));
}
