// ═══════════════════════════════════════════════════════════════════
//  multi-fractal-compositor-lens — Multi-Layer Fractal & Gravitational Lens
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            fractal-compositor, gravitational-lens, semantic-alpha, ACES
//  Complexity: Very High
//  Upgraded: 2026-11-09
//  Ideas: Einstein arcs from the point-lens magnification (critical-curve brightening + tangential smear, theta_E = sqrt(lensMass*0.01)); foreground bypass (near-depth objects are not lensed)
//  A packing: ACES display RGBA; texel (0,0) = cursor-glide state (glide.x, glide.y, 7 marker, fract(time)) and is masked in the C persistence read
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=LensMass, y=RingGlow, z=RippleMass, w=ChromaBoost

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

// ── Rescue R2: aspect-corrected point-lens deflection ────────────────
// HEAD's deflection was computed in raw uv, so on 16:9 the lens was an ellipse while the painted ring was a
// circle. The lens equation is now evaluated in aspect-corrected distance (units of frame height) and the
// deflection is divided back into uv. Identical to HEAD at aspect 1. With soft eps = 0.001 this is exactly
// the point-lens equation  beta = theta - thetaE^2 * theta / |theta|^2  with thetaE^2 = mass * 0.01.
fn gravitationalBend(uv: vec2<f32>, massPos: vec2<f32>, mass: f32, aspect: f32) -> vec2<f32> {
  let ax = vec2<f32>(aspect, 1.0);
  let toMass = (massPos - uv) * ax;
  let dist2 = dot(toMass, toMass);
  let deflection = mass * toMass / (dist2 + 0.001);
  return uv + deflection * 0.01 / ax;
}

// ── Rescue R1: cursor glide for the LENS mouse only, in A texel (0,0) ─────
// HEAD's critically damped spring lived in extraBuffer[133..138]; the host re-uploads extraBuffer zeroed every
// frame, so the "init" flag read 0 each frame and every pixel fell back to the raw cursor (the spring never
// ran). State = A(0,0) = (glide.x, glide.y, GLIDE_MARK, fract(time)); every pixel reads the same C texel and
// integrates the same step, only pixel (0,0) stores it. This is a FIRST-ORDER glide replacing a dead
// critically-damped spring (HEAD stiffness 42 -> rate ~10): at rest nothing changes, when moving the lens
// lags the cursor by ~1/rate s. zoom_center stays the raw cursor.
const GLIDE_MARK: f32 = 7.0;
fn glideStep(st: vec4<f32>, raw: vec2<f32>, time: f32, rate: f32) -> vec2<f32> {
  let ok = abs(st.z - GLIDE_MARK) < 0.01 && st.w >= 0.0 && st.w <= 1.0;   // <= 1: f16 rounds fract(time) > 0.9997 to exactly 1.0
  let dt = clamp(fract(time - st.w), 0.001, 0.05);
  let g = st.xy + (raw - st.xy) * (1.0 - exp(-rate * dt));
  let snapped = select(g, raw, length(raw - g) < 0.003);   // exact at rest even through f16 rounding
  return select(raw, snapped, ok);
}

fn pingPong(v: vec2<f32>) -> vec2<f32> {
  return 1.0 - abs(fract(v * 0.5) * 2.0 - 1.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let zoom_time = u.zoom_config.x;
  let zoom_center = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;
  let held = select(0.0, 1.0, isMouseDown);
  // Rescue R1: lens mouse = glide of the raw cursor (A texel (0,0), exact C load, same for every pixel).
  let glideState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let mouse = glideStep(glideState, rawMouse, time, 10.0);

  // Exact parameter contracts
  let lensMass = mix(0.5, 5.0, u.zoom_params.x) * (1.0 + bass * 0.35);
  let ringGlowStrength = mix(0.0, 1.0, u.zoom_params.y);
  let rippleMass = mix(0.5, 3.0, u.zoom_params.z);
  let chromaBoost = mix(0.01, 0.07, u.zoom_params.w) * (1.0 + treble * 0.4);

  // Aspect-corrected cursor-lens geometry (Rescue R2): distances in units of frame height.
  let ax = vec2<f32>(aspect, 1.0);
  let toMouse = (uv - mouse) * ax;
  let mouseDist = length(toMouse);
  let thetaE2 = lensMass * 0.01;                 // theta_E^2 of the point-lens equation below
  let thetaE = sqrt(thetaE2);

  // Gravitational bending
  var bentUV = gravitationalBend(uv, mouse, lensMass, aspect);

  // Ripple masses
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed >= 0.0 && elapsed < 3.0) {
      let decay = exp(-elapsed * 0.8);
      let rippleBend = gravitationalBend(uv, ripple.xy, rippleMass * decay, aspect);
      bentUV += (rippleBend - uv) * decay;
    }
  }

  // ── Idea 2: foreground bypass ────────────────────────────────────────
  // A gravitational lens only deflects sources BEHIND it. Engine depth: near = 1, so pixels whose own depth is
  // in the foreground (smoothstep 0.55..0.8) are not displaced at all. Inert when the depth map is flat / zero
  // (depth 0 -> factor 1: the full lens, as in HEAD).
  let depthHere = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let lensKeep = 1.0 - smoothstep(0.55, 0.8, depthHere);
  bentUV = uv + (bentUV - uv) * lensKeep;

  // ── Idea 1: Einstein arcs from the point-lens magnification ───────────
  // Image position theta = mouseDist, x = (theta_E / theta)^2. For a point mass the area magnification is
  // mu = 1 / |1 - x^2| (diverges on the critical curve theta = theta_E) and the TANGENTIAL stretch is
  // mu_t = 1 / (1 - x). HEAD used neither (and never used theta_E at all). Near the critical curve the image
  // brightens by clamp(mu, 1, 3) and the sampled layers are smeared along the circle (3 taps, offset ~ theta_E * |mu_t|,
  // clamped), blended by an arc mask; both fade with lensKeep (no arcs on foreground pixels).
  let xE = thetaE2 / max(mouseDist * mouseDist, 1e-4);
  let magArea = clamp(1.0 / max(abs(1.0 - xE * xE), 1e-3), 1.0, 3.0);
  let magTan = min(abs(1.0 / (1.0 - xE + select(1e-3, -1e-3, xE > 1.0))), 6.0);
  let tanDir = vec2<f32>(-toMouse.y, toMouse.x) / max(mouseDist, 1e-4);      // unit tangent (aspect-corrected)
  let arcMask = smoothstep(1.5, 3.5, magTan) * lensKeep * select(0.0, 1.0, mouseDist > 1e-3);
  let smearUV = tanDir / ax * (thetaE * magTan * 0.06);                      // uv-space tangential tap offset
  let arcOn = arcMask > 0.01;

  var accumulatedColor = vec3<f32>(0.0);
  var accumulatedDepth = 0.0;
  var totalWeight = 0.0;

  for (var i: i32 = 0; i < 4; i = i + 1) {
    let layerDepth = f32(i) / 3.0;
    let layerSpeed = mix(0.2, 0.8, layerDepth);
    let layerPhase = fract(zoom_time * layerSpeed + time * 0.05);
    let layerZoom = 1.0 + layerPhase * 3.0;
    // ── Rescue R3: zoom-wrap pop ──
    // layerZoom jumps 4x -> 1x when the phase wraps, so the composite popped once per layer per cycle. Weight
    // each layer by sin^2(pi * phase) (floor 0.02): a layer fades out as it reaches the wrap and back in on the
    // other side, and the 4 layers wrap at different times, so the normalised composite never jumps.
    let phaseSin = sin(3.14159265 * layerPhase);
    let phaseW = max(phaseSin * phaseSin, 0.02);

    let lensedToCenter = (bentUV - zoom_center) * vec2<f32>(aspect, 1.0);
    let dist = length(lensedToCenter);
    let spinAngle = (0.2 * held / (dist + 0.1)) * layerDepth * (1.0 - layerDepth);
    let cosS = cos(spinAngle);
    let sinS = sin(spinAngle);
    let rotated = vec2<f32>(
      (cosS * lensedToCenter.x - sinS * lensedToCenter.y) / aspect,
      sinS * lensedToCenter.x + cosS * lensedToCenter.y
    ) + zoom_center;

    let flowUV = rotated + vec2<f32>(
      noise(rotated * 6.0 + vec2<f32>(time * 0.15, 0.0)),
      noise(rotated * 6.0 + vec2<f32>(0.0, time * 0.15))
    ) * 0.015 * layerDepth;

    let transformed = (flowUV - zoom_center) / layerZoom + zoom_center;
    let pingUV = pingPong(transformed);

    var sampleColor = textureSampleLevel(readTexture, u_sampler, pingUV, 0.0).rgb;
    let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, pingUV, 0.0).r;
    // Idea 1 (tangential smear of the sampled layer; offset taken before the zoom so the on-screen extent is
    // the same on every layer)
    if (arcOn) {
      let tapA = pingPong((flowUV + smearUV - zoom_center) / layerZoom + zoom_center);
      let tapB = pingPong((flowUV - smearUV - zoom_center) / layerZoom + zoom_center);
      let smeared = 0.5 * sampleColor
        + 0.25 * textureSampleLevel(readTexture, u_sampler, tapA, 0.0).rgb
        + 0.25 * textureSampleLevel(readTexture, u_sampler, tapB, 0.0).rgb;
      sampleColor = mix(sampleColor, smeared, arcMask);
    }

    let density = exp(-layerDepth * 1.5);
    let weight = density * (1.0 + sampleDepth * 0.5) * phaseW;
    accumulatedColor += sampleColor * weight;
    accumulatedDepth += sampleDepth * weight;
    totalWeight += weight;
  }

  let baseColor = accumulatedColor / max(totalWeight, 0.0001);
  let baseDepth = accumulatedDepth / max(totalWeight, 0.0001);

  // Chromatic aberration from lens distortion
  let effectiveChroma = chromaBoost * (1.0 + baseDepth * 0.5);
  let uvR = clamp(uv + vec2<f32>(effectiveChroma, 0.0), vec2<f32>(0.001), vec2<f32>(0.999));
  let uvB = clamp(uv - vec2<f32>(effectiveChroma, 0.0), vec2<f32>(0.001), vec2<f32>(0.999));
  var r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
  var b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
  if (arcOn) {
    // the CA taps carry 70% of R/B (KEEP VERBATIM), so the arc smear is applied to them too
    let sUV = smearUV * 0.5;
    let rS = 0.5 * r
      + 0.25 * textureSampleLevel(readTexture, u_sampler, clamp(uvR + sUV, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r
      + 0.25 * textureSampleLevel(readTexture, u_sampler, clamp(uvR - sUV, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r;
    let bS = 0.5 * b
      + 0.25 * textureSampleLevel(readTexture, u_sampler, clamp(uvB + sUV, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b
      + 0.25 * textureSampleLevel(readTexture, u_sampler, clamp(uvB - sUV, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b;
    r = mix(r, rS, arcMask);
    b = mix(b, bS, arcMask);
  }
  let g = baseColor.g;
  var color = mix(baseColor, vec3<f32>(r, g, b), 0.7);

  // Idea 1 (critical-curve brightening): image brightness x clamp(mu, 1, 3), only where the lens acts.
  color = color * mix(1.0, magArea, lensKeep);

  // Einstein ring glow — Rescue R2: painted on the true critical curve theta_E = sqrt(lensMass * 0.01) in
  // aspect-corrected distance (HEAD: sqrt(lensMass * 0.015), 22% too wide, and an ellipse-vs-circle mismatch).
  let einsteinRadius = thetaE;
  let ringGlow = smoothstep(0.06, 0.0, abs(mouseDist - einsteinRadius)) * ringGlowStrength;
  color += vec3<f32>(0.9, 0.8, 0.6) * ringGlow * (1.0 + mids * 0.3);

  // Core glow
  let coreGlow = exp(-mouseDist * mouseDist * 300.0) * lensMass * 0.25;
  color += vec3<f32>(0.6, 0.9, 1.0) * coreGlow;

  // Exact dataTextureC persistence. Rescue R1: texel (0,0) of C is the glide state, not colour -> masked.
  let isGlideTexel = (gid.x == 0u && gid.y == 0u);
  let prevC = select(textureLoad(dataTextureC, pixel, 0).rgb, color, isGlideTexel);
  color = mix(color, prevC, 0.08);

  let finalRGB = aces(color);
  let alpha = clamp(0.35 + ringGlow * 0.3 + coreGlow * 0.4 + held * 0.15, 0.2, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  // A = ACES display RGBA (C persistence); texel (0,0) = cursor-glide state (Rescue R1)
  textureStore(dataTextureA, pixel, select(finalPixel, vec4<f32>(mouse, GLIDE_MARK, fract(time)), isGlideTexel));
  textureStore(writeDepthTexture, pixel, vec4<f32>(baseDepth, 0.0, 0.0, 0.0));
}
