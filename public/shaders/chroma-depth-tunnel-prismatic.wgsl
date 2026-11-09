// ═══════════════════════════════════════════════════════════════════
//  chroma-depth-tunnel-prismatic — Deep Prismatic Chromatic Tunnel
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            chroma-depth-tunnel, spec-prismatic-dispersion, semantic-alpha, ACES
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: ring-joint dispersive rim (bevel highlight per band, rainbow-split for free);
//         chromatic flight lag (each band samples its own depth, wake grows with speed);
//         depth-integrated Beer–Lambert (absorption path grows toward the vanishing point)
//  A packing: ACES display RGBA; texel (0,0) = (cursor glide.xy, 7, fract(time)), skipped by the C persistence
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=TunnelSpeed, y=RingDensity, z=ChromaticSpread, w=CenterFade

fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
  let lambdaUm = wavelengthNm * 0.001;
  return A + B / (lambdaUm * lambdaUm);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
  let g = 1.0 - abs(t - 0.4) * 3.0;
  let b = 1.0 - smoothstep(0.0, 0.4, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn refractUV(uv: vec2<f32>, center: vec2<f32>, ior: f32, curvature: f32) -> vec2<f32> {
  let toCenter = uv - center;
  let dist = length(toCenter);
  let lensStrength = curvature * 0.4;
  let offset = toCenter * (1.0 - 1.0 / ior) * lensStrength * (1.0 + dist * 2.0);
  return uv + offset;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let held = step(0.5, u.zoom_config.w);

  // Rescue R1 — the cursor spring lived in extraBuffer[133..138], which the host re-uploads
  // as zero every frame, so it never persisted (the raw cursor won, with a write race). The
  // eased cursor now lives in texel (0,0) of A and comes back through an exact C load: every
  // pixel computes the same glide, only (0,0) stores it, and that texel skips the C persistence.
  let isWriter = (gid.x == 0u && gid.y == 0u);
  let glideState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let hasGlide = abs(glideState.z - 7.0) < 0.01;
  let frameT = fract(time);
  let glideDt = clamp(frameT - glideState.w + select(0.0, 1.0, frameT < glideState.w), 0.0, 0.1);
  let glideK = 1.0 - exp(-6.5 * glideDt); // 6.5 = sqrt(42), HEAD's spring natural frequency
  let mouse = select(rawMouse, glideState.xy + (rawMouse - glideState.xy) * glideK, hasGlide);

  // Exact parameter contracts. Rescue R-phase: audio used to ride on `time * speed`,
  // `time * (13 + bass*5)` and `time * (9 + mids*6)`, so every change of bass/mids jumped the
  // phase by time*delta (a strobe). Audio now drives amplitude; time keeps a constant rate.
  let speed = (u.zoom_params.x - 0.5) * 2.0;
  let density = u.zoom_params.y * 5.0 + 1.0;
  let chroma = u.zoom_params.z * 0.05;
  let centerFade = u.zoom_params.w;

  var p = uv - mouse;
  let pointerPull = exp(-dot(p, p) * 18.0) * held;
  p *= (1.0 - pointerPull * 0.16);
  let p_aspect = vec2<f32>(p.x * aspect, p.y);
  let radius = length(p_aspect);
  let angle = atan2(p.y, p.x) + pointerPull * sin(time * 7.0) * 0.18;

  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rippleAge = max(time - ripple.z, 0.0);
    if (rippleAge < 2.0) {
      let rippleDist = distance(uv, ripple.xy);
      let front = abs(rippleDist - rippleAge * (0.20 + bass * 0.10));
      clickFront += exp(-front * 115.0) * exp(-rippleAge * 1.5);
    }
  }

  let u_coord = angle / 3.14159265;
  let v_coord = 1.0 / (radius + 0.001);
  let axialPacket = pow(max(0.0, sin(v_coord * 0.55 - time * 13.0)), 14.0) * (1.0 + bass * 0.6);
  let spectralHelix = 0.5 + 0.5 * sin(angle * (4.0 + density) + radius * 38.0 - time * 9.0);
  let tunnelUV = vec2<f32>(
    u_coord + spectralHelix * 0.018 * (1.0 + mids * 0.8) + clickFront * 0.025,
    v_coord * density + time * speed + axialPacket * 0.12
  );

  let glassCurvature = mix(0.1, 1.2, u.zoom_params.z);
  let cauchyB = mix(0.01, 0.08, u.zoom_params.y) + chroma * (1.0 + mids * 0.6);
  let glassThickness = mix(0.3, 1.5, u.zoom_params.w);
  let spectralSat = mix(0.3, 1.2, u.zoom_params.x);

  // ── Idea 3: depth-integrated Beer–Lambert ──────────────────────────────
  // Light from far down the pipe (small radius) crossed more glass than light from the near
  // wall, so the absorption path grows toward the vanishing point: distant rings warm
  // (blue is absorbed first) instead of only fading to black.
  let pathLength = 1.0 + 1.4 * (1.0 - smoothstep(0.0, 0.55, radius));

  // ── Idea 2: chromatic flight lag ──────────────────────────────────────
  // A flying prism smears its spectrum along the flight axis: each band sees the tunnel at its
  // own depth. At rest (speed 0) the bands coincide; the faster the flight, the longer the wake.
  let flightLag = speed * 0.04;

  let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
  var finalColor = vec3<f32>(0.0);
  var jointRim = vec3<f32>(0.0);

  for (var i: i32 = 0; i < 4; i = i + 1) {
    let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyB);
    let bandUV = tunnelUV - vec2<f32>(0.0, (f32(i) - 1.5) * flightLag);
    let refractedUV = refractUV(bandUV, vec2<f32>(0.5), ior, glassCurvature + clickFront * 0.3);
    let wrappedUV = fract(refractedUV);
    let sample = textureSampleLevel(readTexture, u_sampler, wrappedUV, 0.0);
    let absorption = exp(-glassThickness * (4.0 - f32(i)) * 0.15 * pathLength);
    let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[i])) * absorption;
    finalColor += wavelengthToRGB(WAVELENGTHS[i]) * bandIntensity * spectralSat;

    // ── Idea 1: ring-joint dispersive rim ───────────────────────────────
    // The tunnel is a stack of glass rings; the joint between two rings is a bevel that catches
    // light. Each band finds the joint at its own refracted depth, so the rim splits into a
    // rainbow with no extra samples.
    let ringPhase = fract(refractedUV.y);
    let jointDist = min(ringPhase, 1.0 - ringPhase);
    jointRim += wavelengthToRGB(WAVELENGTHS[i]) * exp(-jointDist * 26.0) * absorption;
  }

  finalColor = finalColor / (1.0 + finalColor * 0.3);
  finalColor += jointRim * 0.2 * spectralSat;
  finalColor += wavelengthToRGB(470.0 + spectralHelix * 190.0) * (axialPacket * (0.12 + treble * 0.35) + clickFront * 0.22);

  if (centerFade > 0.0) {
    let fog = smoothstep(0.0, centerFade, radius);
    finalColor *= fog;
  }

  let throat = exp(-pow(radius * 8.0 - 1.0, 2.0) * 3.0) * bass;
  finalColor += vec3<f32>(0.6, 0.8, 1.0) * throat * 0.7;

  // Exact dataTextureC persistence
  // (texel (0,0) holds the cursor glide, not colour: it skips the persistence mix)
  let prevC = textureLoad(dataTextureC, pixel, 0).rgb;
  finalColor = mix(finalColor, prevC, 0.08 * select(1.0, 0.0, isWriter));

  let finalRGB = aces(finalColor);
  let alpha = clamp(dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114)) * (1.0 + bass * 0.4) + throat + held * 0.1, 0.1, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, select(finalPixel, vec4<f32>(mouse, 7.0, frameT), isWriter));

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(d, 0.0, 0.0, 0.0));
}
