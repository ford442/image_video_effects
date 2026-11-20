// ═══════════════════════════════════════════════════════════════════
//  Mirror Dimension
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, click-spin
//  Complexity: Medium
//  Upgraded: 2026-05-17, 2026-11-19
//  Ideas: mirror bevel; tube caustic; fold fringe
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn aces(x_in: vec3<f32>) -> vec3<f32> {
    let x = max(x_in, vec3<f32>(0.0));
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn foldUV(ang: f32, rad: f32, off: f32, zm: f32, aspect: f32) -> vec2<f32> {
    var q = vec2<f32>(cos(ang), sin(ang)) * rad;
    q = q + vec2<f32>(off * 0.1);
    q = q * zm;
    q = vec2<f32>(q.x / max(aspect, 0.001), q.y);
    q = q + vec2<f32>(0.5);
    return clamp(q, vec2<f32>(0.0), vec2<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let time = u.config.x;
    let aspect = resolution.x / max(resolution.y, 0.001);

    // ── Spring-damped symmetry center ────────────────────────────────
    // The fracture point no longer snaps to the cursor: a critically
    // damped spring (zeta = 1) chases the RAW mouse, so the center of
    // symmetry drifts smoothly into place. Raw mouse stays the target.
    // State lives in extraBuffer[133..138] (reserved: [0..4], FFT: [5..132]).
    let mouseActive = step(0.001, u.zoom_config.y); // branchless gate on RAW mouse
    let springTarget = mix(vec2<f32>(0.5, 0.5), u.zoom_config.yz, mouseActive);
    if (global_id.x == 0u && global_id.y == 0u) {
        var sPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[137] < 0.5) {
            // First frame: start AT the target so we don't lurch in from (0,0).
            sPos = springTarget;
            sVel = vec2<f32>(0.0, 0.0);
        }
        let dt = clamp(time - extraBuffer[138], 0.0005, 0.05);
        let omega = 5.0; // low stiffness = slow drift; zeta = 1 (critical, no wobble)
        let sAcc = omega * omega * (springTarget - sPos) - 2.0 * omega * sVel;
        sVel = sVel + sAcc * dt;
        sPos = sPos + sVel * dt;
        extraBuffer[133] = sPos.x;
        extraBuffer[134] = sPos.y;
        extraBuffer[135] = sVel.x;
        extraBuffer[136] = sVel.y;
        extraBuffer[137] = 1.0;
        extraBuffer[138] = time;
    }
    // Every thread rides the sprung center (<=1 frame of slack IS the lag).
    let center = vec2<f32>(extraBuffer[133], extraBuffer[134]);

    // Params (saved-preset contract: ids, defaults, mapping order unchanged)
    let segments  = floor(mix(2.0, 12.0, u.zoom_params.x));
    let baseRotSpeed = mix(-1.0, 1.0, u.zoom_params.y);
    // Bass modulates rotation speed
    let rotSpeed  = baseRotSpeed * (1.0 + bass * 0.5);
    let offsetVal = u.zoom_params.z;
    // Mids modulate zoom intensity
    let zoom      = mix(0.5, 2.0, u.zoom_params.w) * (1.0 + mids * 0.15);

    // Center UV and correct aspect
    var p = uv - 0.5;
    p.x *= aspect;

    // Branchless mouse offset: apply when zoom_config.y > 0
    let m = (center - 0.5) * vec2<f32>(aspect, 1.0);
    p -= m * mouseActive;

    // Polar coords
    let r = length(p);
    var a = atan2(p.y, p.x);

    // Animate rotation
    a += u.config.x * rotSpeed;

    // ── Click mirror spins ───────────────────────────────────────────
    // Each live ripple is a one-way spin impulse: exp(-age * 2.0) * 2.0
    // radians, signed by a hash of the click position, so clicks whirl
    // the kaleidoscope and the whirl relaxes over ~2 seconds.
    var spinKick = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age < 0.0) { continue; }
        let h = fract(sin(dot(rp.xy, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        let dir = select(-1.0, 1.0, h >= 0.5);
        spinKick += dir * exp(-age * 2.0) * 2.0;
    }
    a += spinKick;

    // Segment angle
    let segmentAngle = 3.14159265 * 2.0 / max(segments, 1.0);

    // Segment index from the PRE-FOLD angle (drives per-segment FFT shimmer).
    // fract() keeps the modulo positive even for negative angles.
    let segIdx = u32(fract(floor(a / segmentAngle) / 8.0) * 8.0);

    // Branchless modulo into [0, segmentAngle] using fract — handles negatives
    a = fract(a / segmentAngle) * segmentAngle;

    // Triangle fold (mirror half of the segment)
    a = abs(a - segmentAngle * 0.5);

    // ── Idea 1: mirror bevel ──────────────────────────────────────
    // The crease is glass, not a line. Inset the sample angle and
    // darken it. foldCloseness below still uses the mathematical crease.
    let crease = a;
    let bevel = 1.0 - smoothstep(0.0, 0.04, crease);
    a = crease + bevel * 0.02;

    // ── Idea 3: fold fringe ───────────────────────────────────────
    // Red and blue take a small angular step, and only on the bevel.
    let fringe = bevel * 0.05;
    let uvG = foldUV(a, r, offsetVal, zoom, aspect);
    let uvR = foldUV(a + fringe, r, offsetVal, zoom, aspect);
    let uvB = foldUV(max(a - fringe, 0.0), r, offsetVal, zoom, aspect);
    let sampG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
    let sampR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let sampB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
    var sampled = vec4<f32>(sampR, sampG.g, sampB, sampG.a);
    sampled = vec4<f32>(sampled.rgb * (1.0 - bevel * 0.68), sampled.a);
    // ── Idea 2: tube caustic ──────────────────────────────────────
    // Reflections pile up on the axis. Zoom tightens the hot spot.
    let caustic = exp(-r * (1.1 + zoom * 0.9)) * 0.38;
    sampled = vec4<f32>(sampled.rgb * (1.0 + caustic), sampled.a);

    // ── Per-segment FFT shimmer ──────────────────────────────────────
    // Each folded segment pulses to its own spectrum bin: ±8% brightness.
    let segEnergy = plasmaBuffer[segIdx + 1u].x;
    sampled = vec4<f32>(sampled.rgb * (1.0 + (segEnergy - 0.5) * 0.16), sampled.a);

    // Meaningful alpha: encodes radial position + fold angle closeness + bass energy
    let foldCloseness = 1.0 - clamp(crease / max(segmentAngle * 0.5, 0.001), 0.0, 1.0);
    let radialFactor  = clamp(1.0 - r * 0.8, 0.0, 1.0);
    let alpha = clamp(radialFactor * 0.5 + foldCloseness * 0.3 + bass * 0.2, 0.0, 1.0);

    // Treble seam glow: the mirror fold lines light up with the highs,
    // tracing the kaleidoscope's skeleton as the music brightens.
    let seamGlow = pow(foldCloseness, 6.0) * treble * 0.45;
    let glowColor = vec3<f32>(0.9, 0.95, 1.0) * seamGlow;

    let finalColor = vec4<f32>(aces(sampled.rgb + glowColor), alpha);

    textureStore(writeTexture, coord, finalColor);

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
