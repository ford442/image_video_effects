// ═══════════════════════════════════════════════════════════════════
//  Magnetic Ring
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-05
//  Ideas: ring wake from exact C history behind a dragged magnet; swept integer field spokes bent by drag velocity
//  A packing: display RGB + .a ring energy (wake source); texel (0,0) = (prevMouse.xy, prevTime, valid); texel (1,0) = (smoothed velocity.xy aspect-uv/s, sentinel 7, valid)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

const TAU: f32 = 6.28318530717958647;

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let baseRadius = mix(0.02, 0.45, u.zoom_params.x);
    let strength = u.zoom_params.y * bass_env(bass, mids);
    let pulseSpeed = mix(0.5, 8.0, u.zoom_params.z);
    let ringThickness = mix(0.01, 0.18, u.zoom_params.w);

    // The magnet sits directly on the cursor. HEAD's extraBuffer spring was
    // dead (the buffer is re-uploaded every frame, so [137] never stayed set)
    // and raced across workgroups; pointer velocity now comes from A texels.
    let magnetPos = mousePos;
    let coord = vec2<i32>(global_id.xy);
    let aspectV = vec2<f32>(aspect, 1.0);
    let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
    let dt = time - st0.z;
    var rawVel = vec2<f32>(0.0);
    // Our own state carries a sentinel (st1.z == 7); after a shader switch C holds
    // another effect's pixels, so neither the velocity nor the wake is trusted.
    let stOk = st0.w > 0.5 && st1.z == 7.0 && dt > 1e-4 && dt < 0.25
        && all(st1.xy == st1.xy) && dot(st1.xy, st1.xy) <= 16.0;
    if (stOk) {
        rawVel = (mousePos - st0.xy) * aspectV / max(dt, 1e-3);
        let sp = length(rawVel);
        if (sp > 4.0) { rawVel = rawVel * (4.0 / sp); }
    }
    let vel = mix(select(vec2<f32>(0.0), st1.xy, stOk), rawVel, 0.35); // aspect-uv / s
    let speed = length(vel);
    let dtF = select(0.0, clamp(dt, 0.0, 0.1), stOk);

    let dVec = uv - magnetPos;
    let dVecAspect = vec2<f32>(dVec.x * aspect, dVec.y);
    let dist = length(dVecAspect);
    let safeDir = dVecAspect / max(dist, 0.001);
    let tangent = vec2<f32>(-safeDir.y, safeDir.x);
    let angle = atan2(dVecAspect.y, dVecAspect.x);
    let pulse = sin(time * pulseSpeed * bass_env(bass, mids) - dist * 20.0) * 0.5 + 0.5;

    // Multiple concentric rings for field line effect — each ring throbs on
    // its OWN FFT voice (low / mid / high bins) instead of the global pulse.
    let rings = 3.0;
    var ringMask = 0.0;
    var fieldLines = 0.0;
    var voiceGlow = vec3<f32>(0.0, 0.0, 0.0);
    // Idea 2: swept field spokes — the tangential component of the drag velocity
    // leans each spoke more the further it sits from the ring's core radius,
    // so a dragged magnet combs its spokes into curved field lines.
    let sweep = clamp(dot(tangent, vel) * 2.0, -1.2, 1.2);
    for (var i: f32 = 0.0; i < rings; i = i + 1.0) {
      let r = baseRadius * (1.0 + i * 0.6);
      let m = 1.0 - smoothstep(0.0, ringThickness, abs(dist - r));
      ringMask = ringMask + m;
      // Integer spoke count per turn (48 / 24 / 16) so the atan2 seam is invisible.
      let spokes = floor(48.0 / (i + 1.0));
      let lean = sweep * (dist - r) / max(r, 0.02);
      let spokePhase = fract((angle + i * 1.047 + lean) / TAU * spokes);
      let fl = smoothstep(0.0, 0.05, abs(spokePhase - 0.5)) * m;
      fieldLines = fieldLines + fl;
      // Per-ring FFT voice: bins 2 / 10 / 40 (extraBuffer[5..132], read-only).
      // HEAD read plasmaBuffer[i + 1], which the engine never writes.
      let bin = select(select(40u, 10u, i < 1.5), 2u, i < 0.5);
      let voice = clamp(extraBuffer[5u + bin], 0.0, 1.0);
      let ringPulse = sin(time * pulseSpeed * (0.7 + voice * 0.8) - dist * 20.0 + i * 2.094) * 0.5 + 0.5;
      let voiceHue = vec3<f32>(0.25 + 0.25 * i, 0.45 + mids * 0.1, 0.75 - 0.15 * i);
      voiceGlow = voiceGlow + voiceHue * m * (0.25 + ringPulse * 0.75) * (0.5 + voice * 1.2);
    }

    // ── Click flux shockwaves ─────────────────────────────────────────
    // Each live click ripple adds a temporary fourth ring expanding from
    // its click point at radius age*0.4 (~1.5s fade), plus a local pulse
    // boost, so clicks fire flux surges across the field.
    var shockBoost = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri: u32 = 0u; ri < rippleCount; ri = ri + 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age > 0.0 && age < 1.5) {
            let rdAspect = vec2<f32>((uv.x - ripple.x) * aspect, uv.y - ripple.y);
            let rDist = length(rdAspect);
            let decay = 1.0 - age / 1.5;
            let band = 1.0 - smoothstep(0.0, ringThickness * 1.5, abs(rDist - age * 0.4));
            ringMask = ringMask + band * decay * decay;
            shockBoost = shockBoost + decay * exp(-rDist * 3.0);
        }
    }
    ringMask = clamp(ringMask, 0.0, 1.0);

    let displacement = safeDir * ringMask * strength * (0.03 + pulse * 0.04);
    let offsetUV = vec2<f32>(displacement.x / aspect, displacement.y);

    let baseUV = clamp(uv + offsetUV, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let rgbOffset = offsetUV * (0.35 + strength * 0.85);
    let rUV = clamp(uv + rgbOffset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));
    let gUV = baseUV;
    let bUV = clamp(uv - rgbOffset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let gColor = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);

    // Idea 1: ring wake — exact C history (A.a = ring energy) advected opposite
    // the drag velocity, so a dragged magnet leaves fading ghost rings behind.
    // Taps never touch row 0, where texels (0,0)/(1,0) hold pointer state.
    let maxC = vec2<i32>(resolution) - vec2<i32>(1, 1);
    let advect = vec2<i32>(round(vel / aspectV * resolution * dtF * 0.6));
    let h0 = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0, 1), maxC), 0);
    let h1 = textureLoad(dataTextureC, clamp(coord + advect, vec2<i32>(0, 1), maxC), 0);
    let hist = 0.5 * (h0 + h1);
    let wake = select(0.0, clamp(hist.a, 0.0, 1.0) * exp(-dtF * 3.5), stOk);
    let ghost = clamp(wake - ringMask, 0.0, 1.0);

    // Drag speed energizes the field (replaces HEAD's spring lag); hash21 grain keeps lines alive.
    let grain = hash21(vec2<f32>(global_id.xy) * 0.013 + vec2<f32>(fract(time * 0.7), -fract(time * 0.31)));
    let lagGlow = 1.0 + min(speed, 1.5) * 1.5 + shockBoost * 0.9;
    let ringGlow = vec3<f32>(0.2 + treble * 0.1, 0.4 + mids * 0.1, 0.7) * ringMask * (0.3 + pulse * 0.7);
    let fieldGlow = vec3<f32>(0.1, 0.8, 1.0) * fieldLines * pulse * 0.5 * (0.85 + grain * 0.3);
    let shockGlow = vec3<f32>(0.9, 0.6, 1.0) * shockBoost * ringMask * 0.6;
    let wakeGlow = vec3<f32>(0.3, 0.5, 0.9) * ghost * 0.5;
    let finalColor = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
        gColor.g,
        textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
    ) + ringGlow * lagGlow + voiceGlow + fieldGlow + shockGlow + wakeGlow;

    // Display: ACES on clamped-positive RGB, then the ghost of last frame's rings.
    let display = mix(aces(max(finalColor, vec3<f32>(0.0))), clamp(hist.rgb, vec3<f32>(0.0), vec3<f32>(1.0)), ghost * 0.45);

    let alpha = clamp(gColor.a * 0.45 + ringMask * 0.3 + bass * 0.05 + fieldLines * 0.1 + shockBoost * 0.15 + ghost * 0.2, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + ringMask * 0.05, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(display, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // A: display RGB + ring energy in .a (the wake source); two pointer-state texels.
    var aOut = vec4<f32>(display, max(ringMask * (0.4 + 0.6 * pulse), wake));
    if (global_id.x == 0u && global_id.y == 0u) {
        aOut = vec4<f32>(mousePos, time, 1.0);
    } else if (global_id.x == 1u && global_id.y == 0u) {
        aOut = vec4<f32>(vel, 7.0, 1.0);
    }
    textureStore(dataTextureA, coord, aOut);
}
