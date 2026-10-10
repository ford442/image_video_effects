// ═══════════════════════════════════════════════════════════════════
//  Holographic Sticker — Rainbow Diffraction Foil
//  Category: visual-effects
//  Features: audio-reactive, upgraded-rgba, mouse-driven, click-reactive, held-drag, depth-aware, temporal
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: held-pointer edge peel (curl shows paper backing with roll shading + soft shadow on the image); embossed guilloche security rosettes whose hue slides with sticker tilt
//  A packing: ACES display RGBA + semantic alpha; C read back as display RGB for the 5% temporal foil shimmer
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530717958647692;

// Idea 2 helper — one rotated sinusoidal rosette family f = N*rho/R + a*sin(k*theta + phi).
// Returns (ridge coverage, gradient of the ridge height). Line distance uses the analytic
// |grad f| so the ridge is ~1.25 px wide at any radius (no fwidth in compute).
fn guillocheFamily(dvec: vec2<f32>, rho: f32, theta: f32, R: f32, phi: f32, px: f32) -> vec3<f32> {
  let N = 28.0;
  let a = 2.2;
  let k = 10.0;
  let ph = k * theta + phi;
  let f = N * rho / R + a * sin(ph);
  let rr = max(rho, 1e-5);
  let er = dvec / rr;
  let et = vec2<f32>(-er.y, er.x);
  let gradF = er * (N / R) + et * (a * k * cos(ph) / rr);
  let g = max(length(gradF), 1e-5);
  let sf = fract(f + 0.5) - 0.5;
  let lw = 1.25 * px;
  let t = clamp(abs(sf) / g / lw, 0.0, 1.0);
  let ridge = 1.0 - t * t * (3.0 - 2.0 * t);
  let dRidge = -6.0 * t * (1.0 - t) / lw;
  let gradH = dRidge * sign(sf) * gradF / g;
  // Fade where lines would be denser than ~0.3 per pixel (sticker centre)
  let keep = 1.0 - smoothstep(0.3, 0.6, g * px);
  return vec3<f32>(ridge, gradH) * keep;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let px = 1.0 / max(resolution.y, 1.0); // one pixel in aspect-corrected units

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Sliders: exact parameter contracts
  let radius = u.zoom_params.x;       // 0..1, default 0.5
  let intensity = u.zoom_params.y;    // 0..1, default 0.5
  let rainbowSpeed = u.zoom_params.z; // 0..1, default 0.5
  let depthWeight = u.zoom_params.w;  // 0..1, default 0.5

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Critically damped spring cursor in extraBuffer[133..138]
  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let hasState = (arrayLength(&extraBuffer) > 138u);
  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  let isWriter = (global_id.x == 0u && global_id.y == 0u);
  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.1);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 49.0;
    let damping = 14.0;
    let accel = (rawMouse - sPos) * stiffness - sVel * damping;
    sVel = sVel + accel * dt;
    sPos = sPos + sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  // Aspect-corrected sticker distance
  let dM_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dM = length(dM_vec);

  // Audio-driven sticker pulse: bass modulates sticker radius slightly
  // HEAD fix: Radius 0 made smoothstep(0, 0, d) divide by zero (NaN rim/disc); floor it
  let effectiveRadius = max(radius * (0.95 + bass * 0.15 * sin(time * 3.0) + held * 0.08), 2e-3);
  let inCircle = smoothstep(effectiveRadius, effectiveRadius * 0.88, dM);

  // Iridescent hue from angle around the spring-smoothed center
  let viewAngle = atan2(dM_vec.y, dM_vec.x);
  let grating = sin(dM * 320.0 + viewAngle * 8.0) * 0.15;
  let hue = fract(viewAngle / TAU + time * rainbowSpeed * 0.4 + depth * 0.15 + bass * 0.08 + grating);

  // HSV foil construction
  let saturation = 0.88 + treble * 0.12;
  let value = 0.85 + mids * 0.25;
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(vec3<f32>(hue) + k.xyz) * 6.0 - k.www);
  var foil = value * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), saturation);

  // Audio spectrum modulation
  // HEAD fix: plasmaBuffer[1..8] is never uploaded (always 0 → constant dimming). The hue
  // bucket now picks a live plasmaBuffer[0] band (red→bass, green→mids, violet→treble);
  // at silence the factor is 0.7 exactly as HEAD, so default brightness is unchanged.
  let palIdx = u32(clamp(hue * 7.0, 0.0, 7.0));
  let band = select(select(bass, mids, palIdx >= 3u), treble, palIdx >= 5u);
  let palette = vec3<f32>(band);
  foil = mix(foil, foil * (0.7 + palette * 0.6), 0.35 + held * 0.2);

  // ── Idea 2: embossed guilloche security rosettes ──────────────────
  // Three rosettes rotated by TAU/(3k) weave a fine guilloche mesh in the sticker's polar
  // frame. Ridges are embossed (lit through their analytic gradient from a top-left light)
  // and coloured with a hue offset that slides with the sticker's tilt = its offset from
  // screen centre, like the view-angle shift of a security hologram.
  let tilt = (mouse - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  let g0 = guillocheFamily(dM_vec, dM, viewAngle, effectiveRadius, 0.0, px);
  let g1 = guillocheFamily(dM_vec, dM, viewAngle, effectiveRadius, TAU / 3.0, px);
  let g2 = guillocheFamily(dM_vec, dM, viewAngle, effectiveRadius, 2.0 * TAU / 3.0, px);
  let rN = dM / effectiveRadius;
  let gFade = smoothstep(0.12, 0.25, rN) * (1.0 - smoothstep(0.86, 0.93, rN));
  let gLine = clamp(g0.x + g1.x + g2.x, 0.0, 1.0) * gFade;
  let gSlope = (g0.yz + g1.yz + g2.yz) * px * 0.9;
  let gNormal = normalize(vec3<f32>(-gSlope, 1.0));
  let gLight = normalize(vec3<f32>(-0.5, -0.6, 0.62));
  let gShade = (dot(gNormal, gLight) - gLight.z) * gFade;
  let gHue = fract(hue + 0.5 + tilt.x * 0.8 + tilt.y * 0.55 + length(tilt) * 0.4);
  let gp = abs(fract(vec3<f32>(gHue) + k.xyz) * 6.0 - k.www);
  let gCol = value * mix(k.xxx, clamp(gp - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), saturation);
  foil = mix(foil, gCol, gLine * 0.55);
  foil = foil * (1.0 + gShade * 0.6) + vec3<f32>(1.0, 0.97, 0.92) * (max(gShade, 0.0) * max(gShade, 0.0) * 0.5);

  // Click foil flashes
  var flash = vec3<f32>(0.0);
  var youngestAge = 1e3;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0) { youngestAge = min(youngestAge, age); } // Idea 1 peel ease-in
    if (age < 0.0 || age > 1.8) { continue; }
    let ringRadius = age * 0.6;
    let ringDist = abs(length((uv - ripple.xy) * vec2<f32>(aspect, 1.0)) - ringRadius);
    let ringWidth = 0.018 + age * 0.035;
    let ringMask = smoothstep(ringWidth, 0.0, ringDist);
    let decay = max(1.0 - age / 1.8, 0.0);
    let ringHue = fract(hue + age * 0.8 + f32(i) * 0.19);
    let rp = abs(fract(vec3<f32>(ringHue) + k.xyz) * 6.0 - k.www);
    let ringColor = mix(k.xxx, clamp(rp - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), saturation);
    flash += ringColor * ringMask * (decay * decay);
  }
  foil += flash * (0.4 + intensity * 0.8);

  // ── Idea 1: edge peel ─────────────────────────────────────────────
  // While held, the rim facing away from screen centre (the free edge a fingernail gets
  // under) lifts: sticker beyond a fold line is removed, folds back over the foil as a
  // flat flap of white paper backing with cylindrical-roll shading, and the exposed image
  // under the curl gets a soft contact shadow that spills just outside the rim.
  // Peel eases in over 0.5 s from the click that began the hold (ripple age); stateless.
  let peel = held * smoothstep(0.0, 0.5, youngestAge);
  var lifted = 0.0;
  var flapCover = 0.0;
  var paper = vec3<f32>(0.0);
  var peelShadow = 0.0;
  if (peel > 0.001) {
    let peelDir = normalize(tilt + vec2<f32>(0.05, 0.035)); // bias → lower-right at centre
    let peelDepth = effectiveRadius * 0.34 * peel;
    let foldS = effectiveRadius - peelDepth;
    let sAlong = dot(dM_vec, peelDir);
    lifted = smoothstep(foldS - px, foldS + px, sAlong);
    // Flap = lifted cap mirrored across the fold line, lying back-side-up on the foil
    let dFold = foldS - sAlong;
    let pm = dM_vec + 2.0 * dFold * peelDir;
    flapCover = (1.0 - lifted) * smoothstep(effectiveRadius + px, effectiveRadius - px, length(pm));
    // Cylindrical roll: crease is near-vertical (dark), highlight band where the roll
    // faces the light, flat backing toward the flap tip
    let uRoll = clamp(dFold / max(peelDepth, 1e-5), 0.0, 1.0);
    let rollShade = mix(0.55, 1.0, smoothstep(0.0, 0.35, uRoll))
                  + 0.35 * exp(-((uRoll - 0.28) * (uRoll - 0.28)) / 0.01)
                  - 0.08 * uRoll;
    paper = vec3<f32>(0.94, 0.93, 0.9) * rollShade;
    // Soft shadow on the exposed image: darkest at the crease, spilling past the rim
    let beyond = sAlong - foldS;
    let soft = effectiveRadius * 0.25 * peel + 0.02;
    peelShadow = peel * 0.55
               * smoothstep(-2.0 * px, 2.0 * px, beyond)
               * (1.0 - 0.5 * smoothstep(0.0, peelDepth + 1e-4, beyond))
               * (1.0 - smoothstep(0.0, soft, dM - effectiveRadius));
  }
  let inCircleEff = inCircle * (1.0 - lifted);

  // Sticker rim specular & bevel highlight
  let rimGlow = smoothstep(effectiveRadius * 1.08, effectiveRadius, dM) * (1.0 - smoothstep(effectiveRadius, effectiveRadius * 0.94, dM)) * (1.0 - lifted);
  foil = foil + vec3<f32>(1.0, 0.95, 0.9) * (rimGlow * 1.5);

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var finalColor = mix(baseColor.rgb * (1.0 - peelShadow), baseColor.rgb * 0.35 + foil * intensity, inCircleEff);

  // Click flashes bleed across boundaries
  finalColor += flash * 0.25;

  // Idea 1: the folded paper flap sits on top of everything
  finalColor = mix(finalColor, paper, flapCover);

  // Temporal shimmer via exact dataTextureC load
  let prevFoil = textureLoad(dataTextureC, pixel, 0).rgb;
  let shimmer = mix(finalColor, prevFoil * 0.96, 0.05 + mids * 0.02);
  finalColor = mix(finalColor, shimmer, 0.35);

  // ACES tonemapping
  let finalRGB = aces(finalColor);

  // Semantic alpha: depth layer + sticker foil presence + base alpha
  let luma = dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114));
  let depthAlpha = mix(0.4, 1.0, depth);
  let lumaAlpha = mix(0.5, 1.0, luma);
  let blendedAlpha = mix(lumaAlpha, depthAlpha, depthWeight);
  let stickerCover = max(inCircleEff, flapCover); // paper backing is opaque like the foil
  let stickerAlpha = mix(baseColor.a, 1.0, stickerCover * 0.85);
  let finalAlpha = clamp(mix(blendedAlpha, stickerAlpha, stickerCover * 0.6) + rimGlow * 0.2, 0.3, 1.0);

  let finalPixel = vec4<f32>(finalRGB, finalAlpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
