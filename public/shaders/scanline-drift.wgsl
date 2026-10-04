// ═══════════════════════════════════════════════════════════════════
//  Scanline Drift
//  Category: retro-glitch
//  Features: audio-reactive, upgraded-rgba, mouse-driven, click-reactive, held-drag
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: tape-stretch shear; h-sync porch at the wrap seam; drift-velocity smear
//  A packing: ACES display RGBA (C read back as colour for the tear blend)
// ═══════════════════════════════════════════════════════════════════
// Horizontal strips drift sideways with RGB split; a pointer band adds
// jitter, mouse.x boosts strip edges, held boosts jitter, clicks tear.
// Audio: bass -> drift speed / exposure, mids -> jitter, treble -> per-strip
// flicker (plasmaBuffer[0].xyz only). The extraBuffer[133..138] band spring
// is kept from HEAD but is a runtime no-op (that range is zeroed per frame).

#include "_prelude.wgsl"
// zoom_params: x=DriftSpeed, y=LineHeight, z=Jitter, w=ColorShift

fn hash11(p: f32) -> f32 {
    var p2 = fract(p * .1031);
    p2 *= p2 + 33.33;
    p2 *= p2 + p2;
    return fract(p2);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Per-strip drift, HEAD's recipe verbatim (sin drift + hash jitter + mouse
// band + mouse.x edge proximity + treble flicker), factored so Idea 1 can
// evaluate the neighbouring strip. Returns (offset, drift velocity).
fn stripDrift(sid: f32, time: f32, driftSpeed: f32, jitter: f32, mouseEffect: f32,
              uvx: f32, mouseX: f32, treble: f32) -> vec2<f32> {
    let stripRand = hash11(sid);
    let phase = time * driftSpeed + stripRand * 6.28;
    var offset = sin(phase) * jitter;
    // Idea 3 input — analytic d/dt of the sin drift (uv units per second).
    var vel = cos(phase) * driftSpeed * jitter;
    offset += (hash11(sid + time) - 0.5) * mouseEffect * jitter * 2.0;

    // mouse.x axis: horizontal proximity to each strip's displaced edge
    // subtly boosts that strip's drift — mouse-driven in both axes.
    let edgeProx = smoothstep(0.15, 0.0, abs(mouseX - fract(uvx + offset)));
    offset += (stripRand - 0.5) * edgeProx * jitter * 1.2;

    // Audio flicker: treble adds a faint per-strip shimmer on the drift so
    // the tracking breathes with the soundtrack (hash-timed at 12 Hz).
    let flicker = 1.0 + treble * 0.3 * (hash11(sid * 3.7 + floor(time * 12.0)) - 0.5);
    offset *= flicker;
    vel *= flicker;
    return vec2<f32>(offset, vel);
}

// Idea 2 — horizontal-blanking porch revealed at a wrap seam.
// s = fract(sample x); returns (blank mask, sync-tip sliver), both 0..1.
fn hsyncPorch(s: f32, resX: f32, porchW: f32) -> vec2<f32> {
    let dAfter = s * resX;            // px since the line restarted (back porch side)
    let dBefore = (1.0 - s) * resX;   // px before the line ended (front porch side)
    let back = 1.0 - smoothstep(porchW - 1.0, porchW, dAfter);
    let front = 1.0 - smoothstep(1.0, 2.0, dBefore);
    let sync = 1.0 - smoothstep(0.5, 1.5, abs(dAfter - porchW * 0.4));
    return vec2<f32>(max(back, front), sync);
}

// Idea 3 — trailing 3-tap smear of one channel along the drift velocity.
fn smearTap(off: f32, smear: f32, uv: vec2<f32>, ch: u32) -> f32 {
    let t0 = textureSampleLevel(readTexture, u_sampler, vec2<f32>(fract(uv.x + off), uv.y), 0.0)[ch];
    if (abs(smear) < 1e-6) { return t0; }
    let t1 = textureSampleLevel(readTexture, u_sampler, vec2<f32>(fract(uv.x + off - smear * 0.5), uv.y), 0.0)[ch];
    let t2 = textureSampleLevel(readTexture, u_sampler, vec2<f32>(fract(uv.x + off - smear), uv.y), 0.0)[ch];
    return t0 * 0.5 + t1 * 0.3 + t2 * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let held = u.zoom_config.w > 0.5;
    var mouse = u.zoom_config.yz;

    let driftSpeed = u.zoom_params.x * 2.0 * (1.0 + bass * 0.2);
    let lineHeight = mix(0.001, 0.1, u.zoom_params.y);
    let jitter = u.zoom_params.z * 0.1 * (1.0 + mids * 0.3) * select(1.0, 1.35, held);
    let colorShiftBase = u.zoom_params.w * 0.05;

    var bandPos = mouse.y;
    let hasSpring = arrayLength(&extraBuffer) > 138u;
    if (hasSpring && extraBuffer[138] > 0.5) {
      bandPos = extraBuffer[133];
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
      var springVel = extraBuffer[134];
      if (extraBuffer[138] <= 0.5) {
        bandPos = mouse.y;
        springVel = 0.0;
      } else {
        let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
        let omega = 8.0;
        let accel = (mouse.y - bandPos) * (omega * omega) - springVel * (2.0 * omega);
        springVel += accel * dt;
        bandPos += springVel * dt;
      }
      extraBuffer[133] = bandPos;
      extraBuffer[134] = springVel;
      extraBuffer[137] = time;
      extraBuffer[138] = 1.0;
    }

    // Determine which horizontal strip we are in
    let stripId = floor(uv.y / lineHeight);
    let stripUVy = fract(uv.y / lineHeight);

    // Mouse proximity increases jitter (band eased by the spring)
    let distY = abs(uv.y - bandPos);
    let mouseEffect = smoothstep(0.2, 0.0, distY);

    // Calculate horizontal offset (HEAD recipe, this strip and the next)
    let driftA = stripDrift(stripId, time, driftSpeed, jitter, mouseEffect, uv.x, mouse.x, treble);
    let driftB = stripDrift(stripId + 1.0, time, driftSpeed, jitter, mouseEffect, uv.x, mouse.x, treble);

    // ── Click tracking tears ─────────────────────────────────────────
    // Each live ripple slams a hard horizontal tear onto the strips near
    // its click row: a one-shot offset spike decaying over ~0.8s, plus a
    // brief colorShift doubling while the tear is alive.
    var tearA = 0.0;
    var tearB = 0.0;
    var tearChroma = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age <= 0.0 || age > 0.8) { continue; }
        let rowMask = smoothstep(0.08, 0.0, abs(uv.y - rp.y));
        let decay = 1.0 - age / 0.8;
        let slam = rowMask * decay * decay;
        // Tear direction hashed per strip per click — hard VHS slam.
        tearA += slam * (hash11(stripId + rp.z * 7.31) - 0.5) * 2.0;
        tearB += slam * (hash11(stripId + 1.0 + rp.z * 7.31) - 0.5) * 2.0;
        tearChroma += slam;
    }

    // Idea 1 — tape-stretch shear: over the lower ~30% of each strip the
    // offset (drift, tear and velocity) eases into the next strip's, so the
    // strips shear into one another like stretched tape. Upper 70% = HEAD.
    let stretch = smoothstep(0.7, 1.0, stripUVy);
    let offset = mix(driftA.x + tearA * 0.12, driftB.x + tearB * 0.12, stretch);
    let driftVel = mix(driftA.y, driftB.y, stretch);
    let colorShift = colorShiftBase * (1.0 + tearChroma);

    // Color separation
    let rOffset = offset + colorShift;
    let gOffset = offset;
    let bOffset = offset - colorShift;

    // Idea 3 — drift-velocity smear: each strip streaks along its own drift
    // velocity over a ~0.2 s "exposure" (bass lengthens it), so fast strips
    // blur and slow ones stay crisp. Taps are skipped below 1 px of smear.
    var smear = clamp(driftVel * 0.2 * (1.0 + bass * 0.5), -0.04, 0.04);
    if (abs(smear) * resolution.x < 1.0) { smear = 0.0; }

    let r = smearTap(rOffset, smear, uv, 0u);
    let g = smearTap(gOffset, smear, uv, 1u);
    let b = smearTap(bOffset, smear, uv, 2u);

    // Scanline darkness at strip boundaries
    let lineDark = smoothstep(0.0, 0.1, stripUVy) * smoothstep(1.0, 0.9, stripUVy);

    var color = vec3<f32>(r, g, b);
    color *= mix(0.8, 1.0, lineDark);

    // Idea 2 — h-sync porch: where each channel's displaced line wraps
    // (fract seam) the blanking interval shows through — a dark porch a few
    // px wide with a faint bright sync-tip sliver. Only on strips displaced
    // by more than the porch, so an undisplaced frame keeps clean edges.
    let porchW = max(3.0, resolution.x * 0.004);
    let dispPx = abs(gOffset - round(gOffset)) * resolution.x;
    let porchVis = smoothstep(porchW, 2.0 * porchW, dispPx);
    let pR = hsyncPorch(fract(uv.x + rOffset), resolution.x, porchW);
    let pG = hsyncPorch(fract(uv.x + gOffset), resolution.x, porchW);
    let pB = hsyncPorch(fract(uv.x + bOffset), resolution.x, porchW);
    let blank = vec3<f32>(pR.x, pG.x, pB.x) * porchVis;
    let syncTip = vec3<f32>(pR.y, pG.y, pB.y) * porchVis;
    color = color * (1.0 - blank * 0.9) + syncTip * 0.18;
    color = acesToneMap(color * (0.96 + bass * 0.04));

    let prevDrift = textureLoad(dataTextureC, coord, 0).rgb;
    color = mix(color, prevDrift, tearChroma * 0.08);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let driftMag = abs(rOffset - bOffset);
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let effectIntensity = clamp(driftMag * 10.0 + mouseEffect * 0.3 + tearChroma * 0.3 + luma * 0.2, 0.0, 1.0);
    let finalAlpha = clamp(mix(baseColor.a, 1.0, effectIntensity * 0.7) + bass * 0.05, 0.0, 1.0);

    let depth = textureLoad(readDepthTexture, coord, 0).r;

    textureStore(writeTexture, coord, vec4<f32>(color, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(color, finalAlpha));
}
