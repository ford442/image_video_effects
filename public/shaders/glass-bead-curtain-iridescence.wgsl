// ═══════════════════════════════════════════════════════════════════
//  Glass Bead Curtain Iridescence — Spherical Thin-Film Lenses
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, refraction, thin-film-interference,
//            spectral-render, semantic-alpha, ACES, upgraded-rgba, temporal-state
//  Complexity: Very High
//  Upgraded: 2026-11-09
//  Ideas: drained film wedge (§12.2F thin-film phase: film thicker toward the bottom of every bead, 2–3 interference bands per bead, slow creep, visible body sheen); inter-bead contact fringe (grazing-angle film of the bead hugs its rim into the gaps); swing wake (the cursor spring's velocity drags the parted beads along the travel and they swing back). Rescued: the extraBuffer spring was zeroed every frame (= raw cursor) → critically damped spring in two A texels; singular parting at the cursor (normalize(0) folded a flower into the centre) → displacement ramps in from 0; film colour was dark/muddy (raw spectral average peaks ~0.4 luma) → divided by its white reference so the fringes are real rainbow colour. Review fixes: film is luma-matched (hue from the film, luminance from the photo; the first-pass bright film lifted meanL +0.04..0.11 and cut stdL by up to 0.07); the contact fringe reads a continuous lattice-space field (value noise + a once-per-row drain) instead of a per-cell hash, which stepped ~5x harder across cell borders than inside a cell; wake clamp 0.08 -> 0.04 (0.08 folded the parting map, min det -0.10).
//  A packing: ACES display RGBA (HEAD). Texels (0,0) = (cursor centre.xy, velocity.xy) and (1,0) = (fract(lastTime), 0, 0, 0.7371 sentinel) are STATE, not pixels (top-left corner, invisible); C reads of those texels are masked.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const SENT: f32 = 0.7371;
// mean of wavelengthToRGB over the 13 film taps 380..680 nm step 25 (white reference of thinFilmColor)
const FILM_WHITE: vec3<f32> = vec3<f32>(0.4694, 0.3936, 0.2601);

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Smooth value noise: the contact fringe reads its film thickness from this (continuous across cell borders)
// instead of the per-cell hash, whose steps showed as hard colour seams where two beads meet.
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
  let g = 1.0 - abs(t - 0.45) * 2.5;
  let b = 1.0 - smoothstep(0.0, 0.45, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
  let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
  let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
  let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;

  var color = vec3<f32>(0.0);
  var sampleCount = 0.0;
  for (var lambda = 380.0; lambda <= 700.0; lambda += 25.0) {
    let phase = opd / lambda;
    let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
    color += wavelengthToRGB(lambda) * interference;
    sampleCount += 1.0;
  }
  // The raw spectral average peaks near 0.4 luma with a warm bias (muddy fringes, the film only ever
  // greyed the rim). Divide by the film's own white reference (same taps, I = 1): constructive at every
  // wavelength = white, fringes carry real saturation.
  return color / max(sampleCount, 1.0) / FILM_WHITE;
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

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Sliders: exact parameter contracts
  let beadSizeParam = u.zoom_params.x;  // 0..1, def 0.5
  let refractParam = u.zoom_params.y;   // 0..1, def 0.5
  let iridParam = u.zoom_params.z;      // 0..1, def 0.6
  let thickParam = u.zoom_params.w;     // 0..1, def 0.5

  let beadSize = mix(15.0, 80.0, beadSizeParam) * (1.0 + bass * 0.15);
  let refractionStr = refractParam * 0.45;
  let iridescenceIntensity = mix(0.1, 1.8, iridParam) * (1.0 + mids * 0.4);
  let filmThicknessBase = mix(220.0, 780.0, thickParam) * (1.0 + treble * 0.25);

  // ── Sprung cursor, persisted in two A texels ─────────────────────
  // HEAD kept this critically damped spring (stiffness 36, damping 12) in extraBuffer[133..138], which is
  // re-uploaded zeroed every frame — on the first-frame branch it collapsed to the raw cursor. Texel (0,0)
  // = (pos.xy, vel.xy), texel (1,0) = (fract(lastTime), 0, 0, SENT). Every thread integrates the same
  // step from the stored state; the sentinel guards the first frame / inherited C.
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let isStateTexel = (pixel.y == 0 && pixel.x < 2);
  let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let stateOk = abs(st1.w - SENT) < 0.001;
  var mouse = select(rawMouse, st0.xy, stateOk);
  var mouseVel = select(vec2<f32>(0.0), st0.zw, stateOk);
  let springDt = select(0.016, clamp(fract(time - st1.x), 0.001, 0.05), stateOk);
  mouseVel = mouseVel + ((rawMouse - mouse) * 36.0 - mouseVel * 12.0) * springDt;
  mouse = mouse + mouseVel * springDt;
  // f16 rest-snap (A is rgba16float on most tiers): settle exactly once near and slow.
  let settled = all(abs(rawMouse - mouse) < vec2<f32>(0.004)) && length(mouseVel) < 0.06;
  mouse = select(mouse, rawMouse, settled);
  mouseVel = select(mouseVel, vec2<f32>(0.0), settled);

  // Interactive bead curtain parting
  let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let repelRadius = 0.35 * (1.0 + held * 0.3);
  let interact = smoothstep(repelRadius, 0.0, dist);
  // HEAD pushed with normalize(distVec)·interact·0.18, singular at the cursor (every pixel inside r<0.18
  // folded across the centre → a flower in the middle of the parting). The push now ramps in from 0
  // (slope < 1, so the map r → r − push(r) stays monotone).
  let partRamp = smoothstep(0.0, 0.25, dist);
  var curtainPart = normalize(distVec + vec2<f32>(0.0001)) * interact * partRamp * 0.18;

  // ── Idea 3: swing wake ───────────────────────────────────────────
  // A hand pushed through a curtain drags the beads along its travel, and they swing back when it stops.
  // The sprung cursor's real velocity (alive now) displaces the lattice along the motion; the
  // critically-damped lag is the swing-back.
  // The clamp is what keeps the lattice map one-to-one: with parting 0.18 ramping over 0.25 and the wake scaled by
  // aspect, ±0.08 flips the Jacobian (min det -0.10 over 8 wake directions, aspect 1 and 16:9, held and idle);
  // ±0.05 only just clears 0 (0.001), ±0.04 keeps det >= 0.02.
  let wake = clamp(mouseVel * 0.07, vec2<f32>(-0.04), vec2<f32>(0.04));
  curtainPart = curtainPart + wake * vec2<f32>(aspect, 1.0) * interact;

  // Click ripple dispersion
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleDisp = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 2.0) { continue; }
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    let wave = sin((rDist - age * 0.5) * 30.0) * exp(-rDist * 3.5) * exp(-age * 1.4);
    let rDir = normalize(uv - ripple.xy + vec2<f32>(0.0001));
    rippleDisp += rDir * wave * 0.06;
  }

  let activeUV = clamp(uv - vec2<f32>(curtainPart.x / aspect, curtainPart.y) - rippleDisp, vec2<f32>(0.0), vec2<f32>(1.0));

  // Bead lattice geometry
  let pxActive = activeUV * resolution;
  let cellIndex = floor(pxActive / beadSize);
  let cellUV = fract(pxActive / beadSize) - 0.5;
  let rCell = length(cellUV);

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var color = src.rgb;
  var alpha = src.a;

  if (rCell < 0.48) {
    let z = sqrt(max(0.0, 0.2304 - rCell * rCell));
    let normal = normalize(vec3<f32>(cellUV, z));
    let glassThickness = 2.0 * z;

    // Refracted UV through spherical bead
    let refractOffset = -normal.xy * refractionStr;
    let refractUV = clamp(activeUV + refractOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    // Fresnel reflection
    let cosTheta = clamp(normal.z, 0.0, 1.0);
    let R0 = 0.045;
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cosTheta, 5.0);

    // Beer-Lambert physical transmission
    let glassColor = vec3<f32>(0.96, 0.98, 1.0);
    let absorption = exp(-(vec3<f32>(1.0) - glassColor) * glassThickness * 2.0);
    let transmission = (1.0 - fresnel) * dot(absorption, vec3<f32>(0.3333));

    // Load background through bead
    let beadSample = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0).rgb;

    // Exact dataTextureC temporal ghost reflection inside bead (state texels are not colour)
    let prevCoord = clamp(vec2<i32>(refractUV * resolution), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
    let prevCRaw = textureLoad(dataTextureC, prevCoord, 0).rgb;
    let prevC = select(prevCRaw, beadSample, prevCoord.y == 0 && prevCoord.x < 2);
    let beadBase = mix(beadSample, prevC, 0.15) * glassColor;

    // Thin-film interference on bead surface
    let cosThetaFilm = sqrt(max(1.0 - rCell * rCell * 1.5, 0.02));
    let filmNoise = hash12(cellIndex * 13.7 + time * 0.05) * 0.4;
    // ── Idea 1: drained film wedge (§12.2F thin-film phase) ─────────
    // A bead's film drains: thicker toward the bottom (cellUV.y grows downward), thinner at the top, so every
    // bead shows 2–3 horizontal interference bands instead of one flat colour; the film creeps slowly per bead.
    let creep = 0.08 * sin(time * 0.4 + hash12(cellIndex * 7.1) * 6.28318);
    let drain = 1.0 + 0.8 * cellUV.y + creep;
    let filmThickness = filmThicknessBase * (0.8 + filmNoise) * drain;
    let filmIOR = 1.48;
    // Luma-matched: the film supplies the HUE, the photo keeps its LUMINANCE (blending a near-constant bright
    // film over the photo was a milky wash: meanL +0.04..+0.11, stdL -0.04..-0.07). Only the Fresnel rim takes the
    // film's own brightness; the slider scales how much of the tint is mixed in.
    let filmN = thinFilmColor(filmThickness, cosThetaFilm, filmIOR);
    let lumaW = vec3<f32>(0.2126, 0.7152, 0.0722);
    let filmLuma = max(dot(filmN, lumaW), 0.05);
    let baseLuma = dot(beadBase, lumaW);
    let iridescent = filmN / filmLuma * mix(baseLuma, filmLuma, fresnel);

    // Specular highlight on bead dome
    let lightDir = normalize(vec3<f32>(-0.6, -0.6, 0.9));
    let spec = pow(max(dot(normal, lightDir), 0.0), 24.0) * (0.65 + treble * 0.35);

    // Film reflectance had only the Fresnel^5 rim (≈ 0.03 at the bead centre → plain grey glass); a small
    // floor keeps the bands visible across the bead body (0.15, hue-only so it no longer lifts the photo).
    let filmMix = clamp(max(fresnel, 0.15) * iridescenceIntensity * 1.6, 0.0, 0.9);
    color = mix(beadBase, iridescent, filmMix) + vec3<f32>(1.0, 0.98, 0.95) * spec;

    // Bead shadow rim
    let rimShadow = smoothstep(0.48, 0.44, rCell);
    color *= (0.85 + 0.15 * rimShadow);
    alpha = clamp(transmission + fresnel * 0.5 + spec * 0.3, 0.4, 1.0);
  } else {
    // Backdrop visible between bead strings with subtle shadow
    let gapDist = rCell - 0.48;
    let gapShadow = smoothstep(0.0, 0.1, gapDist);
    color = src.rgb * (0.88 + 0.12 * gapShadow);
    alpha = clamp(src.a * 0.9, 0.3, 1.0);

    // ── Idea 2: inter-bead contact fringe ───────────────────────────
    // Coated beads show their film at grazing incidence along the rim that faces the gap, hugging the bead and
    // fading with gapDist. Thickness is a CONTINUOUS field of lattice position (value noise + a periodic drain
    // that repeats once per row), so the colour is the same on both sides of a cell border — a per-cell hash
    // stepped there (fringe jumped ~5x more across borders than inside a cell). Hue only: the gap keeps its own
    // luminance, so the fringe tints the backdrop instead of whitening it.
    let lat = pxActive / beadSize;
    let gapDrain = 1.0 + 0.35 * sin(lat.y * 6.28318 + 1.0);
    let gapThickness = filmThicknessBase * (0.8 + valueNoise(lat * 0.9 + vec2<f32>(time * 0.03, 0.0)) * 0.4) * gapDrain;
    let rimN = thinFilmColor(gapThickness, 0.18, 1.48);
    let rimTint = rimN / max(dot(rimN, vec3<f32>(0.2126, 0.7152, 0.0722)), 0.05) * dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
    color = mix(color, rimTint, exp(-gapDist * 12.0) * 0.8 * clamp(iridescenceIntensity * 0.6, 0.0, 1.0));
  }

  // Exact dataTextureC persistence (state texels are not colour)
  let prevRaw = textureLoad(dataTextureC, pixel, 0).rgb;
  let prev = select(prevRaw, color, isStateTexel);
  color = mix(color, prev, 0.06);

  // ACES Tonemap
  let finalRGB = aces(max(color, vec3<f32>(0.0)));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let finalPixel = vec4<f32>(finalRGB, alpha);

  // State texels carry the sprung cursor instead of pixels (writeTexture is unaffected).
  var aOut = finalPixel;
  if (pixel.y == 0 && pixel.x == 0) { aOut = vec4<f32>(mouse, mouseVel); }
  if (pixel.y == 0 && pixel.x == 1) { aOut = vec4<f32>(fract(time), 0.0, 0.0, SENT); }

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, aOut);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
