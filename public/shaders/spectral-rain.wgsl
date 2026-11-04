// ═══════════════════════════════════════════════════════════════════
//  Spectral Rain
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23 (Phase A Upgrade Swarm)
//  Upgraded: 2026-07-31, 2026-11-01 (Batch 20 — per-column FFT voices, springed
//            rain controls, click splash bursts; mids/treble now live)
//  Ideas: streak core; column slant
//  A packing: ACES display RGBA (C unread)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Density, y=ChromaticStr, z=TrailLen, w=AngleControl

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Critically-damped spring integrator (semi-implicit, unconditionally stable).
// Returns vec2(newPos, newVel) easing pos toward goal with ~2.5 Hz settle.
fn spring_step(pos: f32, vel: f32, goal: f32, dt: f32) -> vec2<f32> {
    let omega = 2.0 * 3.14159265 * 2.5;
    let decay = exp(-omega * dt);
    let xOff = pos - goal;
    let temp = (vel + omega * xOff) * dt;
    let newPos = goal + (xOff + temp) * decay;
    let newVel = (vel - omega * temp) * decay;
    return vec2<f32>(newPos, newVel);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / max(resolution.y, 1.0);

    // Audio reactivity — full spectrum is live now:
    // bass   -> global chromatic intensity swell (existing behavior)
    // mids   -> click splash burst gain
    // treble -> per-column brightness shimmer lift
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Mouse Controls — raw mouse is the spring goal, never the direct value.
    var mouse = u.zoom_config.yz;
    let angleGoal = (mouse.x - 0.5) * 2.0;
    let speedGoal = mouse.y * 2.0 + 0.5;

    // ── Spring-damper rain controls (extraBuffer[133..137]) ─────────
    // [0..4] reserved, [5..132] engine FFT — shader state lives at 133+ only.
    // 133/134 = angle pos/vel, 135/136 = speed pos/vel, 137 = last frame time.
    var anglePos = extraBuffer[133];
    var angleVel = extraBuffer[134];
    var speedPos = extraBuffer[135];
    var speedVel = extraBuffer[136];
    let prevTime = extraBuffer[137];
    let dt = clamp(time - prevTime, 0.001, 0.05);
    // Branchless first-frames snap: untouched state jumps straight to goal.
    let stateZero = 1.0 - step(0.0001, abs(anglePos) + abs(angleVel) + abs(speedPos) + abs(speedVel) + abs(prevTime));
    anglePos = mix(anglePos, angleGoal, stateZero);
    speedPos = mix(speedPos, speedGoal, stateZero);
    let angleSpring = spring_step(anglePos, angleVel, angleGoal, dt);
    let speedSpring = spring_step(speedPos, speedVel, speedGoal, dt);
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = angleSpring.x;
        extraBuffer[134] = angleSpring.y;
        extraBuffer[135] = speedSpring.x;
        extraBuffer[136] = speedSpring.y;
        extraBuffer[137] = time;
    }
    // Eased controls: direction changes sweep smoothly instead of snapping.
    let angleVal = angleSpring.x;
    let speedVal = speedSpring.x;

    // Params (slider contract: ids/defaults/ranges unchanged)
    let density = u.zoom_params.x * 20.0 + 5.0;
    let chromaticStr = u.zoom_params.y * 0.05 * (1.0 + bass * 0.4);
    let trailLenBase = u.zoom_params.z * 0.5 + 0.1;

    // Rotate UV for rain direction
    let angle = angleVal * mix(0.0, 1.5, u.zoom_params.w);
    let c = cos(angle);
    let s = sin(angle);
    let rotMat = mat2x2<f32>(c, -s, s, c);

    let rotUV = rotMat * (uv * vec2<f32>(aspect, 1.0));

    // Rain generation
    let gridUV = rotUV * density;
    let gridID = floor(gridUV);
    let gridOffset = fract(gridUV);

    // ── Per-column FFT voice (priority 1) ───────────────────────────
    // Each rain column listens to its own spectrum bin (bins 1..8), so the
    // streaks shimmer across the spectrum instead of all following bass.
    let colBin = plasmaBuffer[(u32(gridID.x) % 8u) + 1u].x;
    // Bin amplitude modulates this column's trail length (±20%).
    let trailLen = clamp(trailLenBase * (1.0 + (colBin - 0.5) * 0.4), 0.02, 0.95);

    let colSpeed = hash12(vec2<f32>(gridID.x, 0.0)) * 0.5 + 0.5;
    // ── Idea 2: column slant ────────────────────────────────────────
    // Faster columns lean inside the rotated field. Rain Angle Scale
    // still owns how much direction varies.
    let slant = (colSpeed - 0.75) * 0.55 * u.zoom_params.w;
    let yPos = rotUV.y + time * speedVal * colSpeed + rotUV.x * slant;
    let dropNoise = fract(yPos * density * 0.1 + hash12(vec2<f32>(gridID.x, 10.0)) * 100.0);
    let drop = smoothstep(1.0 - trailLen, 1.0, dropNoise);
    // ── Idea 1: streak core ─────────────────────────────────────────
    // The tip stays sharp and bright. Chromatic displace uses the tail.
    // Trail Length still sets how long that tail is.
    let headSpan = min(trailLen * 0.22, 0.045);
    let head = smoothstep(1.0 - headSpan, 1.0, dropNoise);
    let tail = drop * (1.0 - head);

    // ── Click splash bursts ─────────────────────────────────────────
    // Each live ripple adds a radial chromatic kick at its click point:
    // ~0.03 amplitude, ~1.0 s fade, along the aspect-corrected radial dir.
    var splash = vec2<f32>(0.0, 0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.0) {
            let fade = 1.0 - age;
            let rVec = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let rDist = length(rVec);
            let rDir = rVec / max(rDist, 0.0001);
            let kick = smoothstep(0.25, 0.0, rDist) * fade * fade * 0.03;
            splash += vec2<f32>(rDir.x / aspect, rDir.y) * kick;
        }
    }
    // Mids drive how hard the clicks splatter the rain.
    splash = splash * (1.0 + mids * 0.6);

    // Apply displacement
    let displace = vec2<f32>(s, c) * tail * chromaticStr + splash;

    let samplePos = clamp(uv + displace, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleNeg = clamp(uv - displace, vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, samplePos, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleNeg, 0.0).b;

    // Column FFT voice lifts the drop brightness; treble adds shimmer.
    let bright = (head * 0.45 + tail * 0.1) * (0.6 + colBin * 1.2) * (1.0 + treble * 0.4);

    // Semantic alpha
    let baseLum = dot(vec3<f32>(r, g, b), vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(drop * 0.6 + head * 0.25 + bright * 2.0 + length(displace) * 8.0 + baseLum * 0.15 + 0.1, 0.1, 1.0);

    let finalRGB = acesToneMap(max(vec3<f32>(r + bright, g + bright, b + bright), vec3<f32>(0.0)));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, alpha));
}
