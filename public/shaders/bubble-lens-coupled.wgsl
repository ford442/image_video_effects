// ═══════════════════════════════════════════════════════════════════
//  Bubble Lens Coupled — Fluid-Coupled Magnifying Bubble Lens
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba,
//            fluid-simulation, lens-distortion, semantic-alpha, ACES
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: drained angle-aware soap-film interference (thin-film phase §12.2F: thickness thins toward the top, thickens with the stirred fluid, sin² reflectance at 650/550/450 nm with Snell cosθ, the film takes the light it reflects from the photo); stir wake seeds the film (the cursor's lag velocity injects film thickness that the flow then advects, so moving the bubble leaves swirling colour); flow-dented wall (the bubble radius follows the radial flow sampled AT the rim point, replacing the phase-locked sin(3θ) wobble). Rescued: lens law was singular at the centre (displacement ∝ R·direction → pinwheel + inverted rings) → continuous magnifier; Fresnel used a 2-D polar angle (horizontal rainbow band) → sphere incidence angle; cursor spring lived in the zeroed extraBuffer (stirring dead) → A-texel spring; advection truncated to whole texels (dead below |v|=0.33) → bilinear back-trace + one 2-tap diffusion step (the destination-velocity back-trace never fills pixels outside the click/stir support → a one-texel dens cliff that Ideas 1/2 render as a crisp circular seam); per-pixel hash sparkle strobed → round twinkling glints on a rotated lattice; no validity sentinel (inherited C = fluid) → sentinel-gated reset; centre-pixel normalize(0).
//  A packing: raw fluid state (vel.xy, z = legacy vel.x−vel.y diagnostic — unread, dens). Texels (0,0) = (cursor.xy, cursor vel.xy) and (1,0) = (fract(lastTime), 0, 0, 0.7371 sentinel) are STATE, not pixels (top-left corner); field reads of those texels are masked and an invalid sentinel resets the fluid to rest.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Radius, y=Magnification, z=FilmThickness, w=Viscosity

const SENT: f32 = 0.7371;

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Round, slowly twinkling glints: one soft dot per cell of a lattice rotated 28.6°, centre jittered inside the cell, radius
// 0.3 cell (never clipped by the cell edge → no popping as the domain drifts). The per-pixel, per-frame hash sparkle strobed
// at 60 fps; the value-noise replacement peaked on lattice points and read as 6–10 px axis-aligned rectangles/crosses.
fn glints(p: vec2<f32>, t: f32) -> f32 {
  let q = vec2<f32>(0.8776 * p.x - 0.4794 * p.y, 0.4794 * p.x + 0.8776 * p.y);
  let i = floor(q);
  let f = fract(q);
  let h = hash12(i);
  let c = vec2<f32>(0.3 + 0.4 * hash12(i + vec2<f32>(17.1, 3.7)), 0.3 + 0.4 * hash12(i + vec2<f32>(43.7, 9.3)));
  let tw = 0.55 + 0.45 * sin(t * (1.5 + 2.0 * h) + h * 40.0);
  return smoothstep(0.3, 0.0, length(f - c)) * smoothstep(0.3, 0.75, h) * tw;
}

fn schlickFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(max(1.0 - cosTheta, 0.0), 5.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Free soap film in air: the top surface flips the phase, so R(λ) = sin²(2π·n·d·cosθt / λ)
// (zero thickness is a BLACK film — the thin top of a draining bubble goes dark before it pops).
fn soapFilm(cosT: f32, dNm: f32, n: f32) -> vec3<f32> {
  let lam = vec3<f32>(650.0, 550.0, 450.0);
  let s = sin(6.2831853 * n * dNm * max(cosT, 0.05) / lam);
  return s * s;
}

// Fluid field read from exact C. State texels and an invalid (inherited / first-frame) C read as rest.
fn fieldAt(c: vec2<i32>, maxC: vec2<i32>, ok: bool) -> vec4<f32> {
  let cc = clamp(c, vec2<i32>(0), maxC);
  let isState = cc.y == 0 && cc.x < 2;
  return select(vec4<f32>(0.0), textureLoad(dataTextureC, cc, 0), ok && !isState);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let maxC = vec2<i32>(i32(resolution.x) - 1, i32(resolution.y) - 1);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let mouseDown = u.zoom_config.w > 0.5;
  let held = select(0.0, 1.0, mouseDown);

  // ── Critically damped spring cursor (HEAD constants: 42 / 12.96), persisted in two A texels ──
  // HEAD kept it in extraBuffer[133..138] — re-uploaded zeroed every frame, written by thread (0,0) only —
  // so `mouse` was ≈ rawMouse for every other thread and the stirring below (rawMouse − mouse) was dead.
  // Texel (0,0) = (cursor.xy, cursor vel.xy), texel (1,0) = (fract(lastTime), 0, 0, SENT).
  let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let stateOk = abs(st1.w - SENT) < 0.001;
  var mouse = select(rawMouse, st0.xy, stateOk);
  var sVel = select(vec2<f32>(0.0), st0.zw, stateOk);
  let springDt = select(0.016, clamp(fract(time - st1.x), 0.001, 0.05), stateOk);
  sVel = sVel + ((rawMouse - mouse) * 42.0 - sVel * 12.96) * springDt;
  mouse = mouse + sVel * springDt;
  // f16 rest-snap (A is rgba16float on most tiers): settle exactly once near and slow.
  let settled = all(abs(rawMouse - mouse) < vec2<f32>(0.004)) && length(sVel) < 0.06;
  mouse = select(mouse, rawMouse, settled);
  sVel = select(sVel, vec2<f32>(0.0), settled);

  // Exact parameter contracts
  let bubbleRadius = (u.zoom_params.x * 0.3 + 0.1) * (1.0 + bass * 0.2);
  let magnification = u.zoom_params.y * 2.0 + 1.0;
  let filmThickness = u.zoom_params.z * 2.0 + 0.5;
  let viscosity = mix(0.92, 0.99, u.zoom_params.w);

  // Exact fluid simulation state loaded from dataTextureC.
  // HEAD back-traced by `i32(prevVel * 3.0)` (whole texels): |vel| ≤ 0.5 so the trace was ≤ 1 texel and exactly 0
  // below |vel| = 0.333 — the fluid never advected below a third of its top speed. Bilinear back-trace instead.
  // Where the field is at rest (almost everywhere away from the stir) the trace is < 0.02 texel: reuse the centre load.
  let prevFluid = fieldAt(coord, maxC, stateOk);
  let trace = prevFluid.xy * 3.0;
  var advected = prevFluid;
  if (dot(trace, trace) > 0.0004) {
    let bp = vec2<f32>(coord) - trace;
    let b0 = vec2<i32>(floor(bp));
    let bt = bp - floor(bp);
    let f00 = fieldAt(b0, maxC, stateOk);
    let f10 = fieldAt(b0 + vec2<i32>(1, 0), maxC, stateOk);
    let f01 = fieldAt(b0 + vec2<i32>(0, 1), maxC, stateOk);
    let f11 = fieldAt(b0 + vec2<i32>(1, 1), maxC, stateOk);
    advected = mix(mix(f00, f10, bt.x), mix(f01, f11, bt.x), bt.y);
  }
  // One diffusion step per frame. The back-trace reads the DESTINATION pixel's own velocity, which is exactly 0 outside the
  // click reach / stir radius — nothing is ever pulled into those pixels, so the film ended in a one-texel cliff (dens
  // 0.62 → 0.00 at r = 0.197) that Ideas 1/2 turned into a visible circular colour seam. Mixing toward a neighbour mean
  // (0.3; D ≈ 0.075 texel²/frame) lets the support spread and the front soften; viscosity still decays the whole field.
  // Two loads, not four: a checkerboard picks the axis (even pixels average their ±x neighbours, odd pixels ±y), which
  // measured the same softening as the 4-neighbour mean at half the texture reads (SwiftShader reads are the expensive part).
  // Skipped on an invalid C (everything reads as rest) and within one texel of the two state texels in the corner.
  if (stateOk && (coord.y > 1 || coord.x > 2)) {
    let nb = select(vec2<i32>(1, 0), vec2<i32>(0, 1), ((coord.x + coord.y) & 1) == 1);
    let nMean = (textureLoad(dataTextureC, min(coord + nb, maxC), 0) +
                 textureLoad(dataTextureC, max(coord - nb, vec2<i32>(0)), 0)) * 0.5;
    advected = mix(advected, nMean, 0.3);
  }
  var vel = advected.xy * viscosity;
  var dens = advected.a * viscosity;

  let toMouse = (uv - mouse) * aspectVec;
  let dist = length(toMouse);
  let dirSafe = toMouse / max(dist, 1e-4);
  let mouseRadius = mix(0.04, 0.18, u.zoom_params.w);
  let influence = smoothstep(mouseRadius, 0.0, dist) * (0.6 + held * 0.4);

  let mouseVel = (rawMouse - mouse) * 40.0;
  vel += mouseVel * influence * 0.5;

  let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
  vel += vortexDir * influence * 1.5;

  // ── Idea 2: stir wake seeds the film ──
  // HEAD only added film density on clicks. Dragging the bubble now thickens the film under it in proportion to the
  // stir (capped), and the flow advects that thickness away as a swirling wake.
  dens += min(length(mouseVel), 3.0) * influence * 0.05;

  // Click ripple bursts
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed >= 0.0 && elapsed < 2.0) {
      let rToMouse = (uv - ripple.xy) * aspectVec;
      let rDist = length(rToMouse);
      let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
      let outward = select(vec2<f32>(0.0), normalize(rToMouse / aspectVec), rDist > 0.001);
      vel += outward * rInfluence * 0.35;
      dens += rInfluence * 0.5;
    }
  }

  let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
  vel = vel * smoothstep(0.02, 0.08, edgeDist);
  vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
  dens = clamp(dens, 0.0, 2.0);

  let vorticity = vel.x - vel.y; // legacy diagnostic, never read back (kept: documented packing)
  var aOut = vec4<f32>(vel, vorticity, dens);
  if (global_id.y == 0u && global_id.x == 0u) { aOut = vec4<f32>(mouse, sVel); }
  if (global_id.y == 0u && global_id.x == 1u) { aOut = vec4<f32>(fract(time), 0.0, 0.0, SENT); }
  textureStore(dataTextureA, coord, aOut);

  // ── Idea 3: flow-dented, drag-stretched wall ──
  // HEAD scaled a fixed, phase-locked sin(3θ + 2t) wobble by |vel| at the PIXEL (a pixel at the wall carries no flow).
  // (a) the wall follows the radial component of the C velocity sampled where this pixel's ray meets the rim (clicks);
  // (b) dragging the bubble excites the drop's lowest shape mode (l = 2): stretched along the pull toward the cursor,
  //     squashed across it, 0 at rest. Soft-capped so the wall dents instead of folding.
  // The wall can move at most dentCap (0.4 R) from the rim, so pixels farther than 1.45 R skip all of this.
  var wallDent = 0.0;
  if (dist < bubbleRadius * 1.45) {
    let rimUV = clamp(mouse + dirSafe * bubbleRadius / aspectVec, vec2<f32>(0.0), vec2<f32>(0.9999));
    let rimVel = fieldAt(vec2<i32>(rimUV * resolution), maxC, stateOk).xy;
    let lagAspect = (rawMouse - mouse) * aspectVec;
    let lagLen = length(lagAspect);
    let lagCos = dot(dirSafe, lagAspect / max(lagLen, 1e-4));
    let dentRaw = dot(rimVel, dirSafe) * 0.09 + 0.45 * min(lagLen, 0.2) * (2.0 * lagCos * lagCos - 1.0);
    let dentCap = 0.4 * bubbleRadius;
    wallDent = dentCap * tanh(dentRaw / dentCap);
  }
  let deformedRadius = bubbleRadius + wallDent;
  let ior = 1.3 + dens * 0.2 + mids * 0.1;
  let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);

  var finalColor: vec3<f32>;
  var alpha: f32;

  if (dist < deformedRadius) {
    let factor = dist / max(deformedRadius, 0.001);
    // R1: continuous magnifier. Local zoom Z = `magnification` at the centre falling to 1 at the wall (no seam);
    // HEAD's displacement ∝ R·direction was singular at the centre and inverted the image inside f ≈ 0.45.
    let zoom = 1.0 + (magnification - 1.0) * (1.0 - factor * factor);
    let fluidWarp = vel * dens * 0.02 * (1.0 - factor);
    let warpedUV = clamp(mouse + (uv - mouse) / zoom + fluidWarp, vec2<f32>(0.001), vec2<f32>(0.999));

    let sample = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0).rgb;

    // R2: sphere incidence angle (HEAD used the polar angle of the pixel direction → rainbow band, no rim).
    let cosI = sqrt(max(1.0 - factor * factor, 0.0));
    let fresnel = schlickFresnel(cosI, F0);

    // ── Idea 1: drained, angle-aware soap-film interference (thin-film phase, §12.2F) ──
    // Thickness (nm): FilmThickness slider × a bottom-heavy drainage wedge, + the stirred/clicked film (dens), + treble.
    // cosθt from Snell at the film (n = 1.33) so the bands shift toward the rim like a real bubble.
    let drain = clamp(0.5 + 0.5 * toMouse.y / max(deformedRadius, 0.001), 0.0, 1.0);
    let dNm = filmThickness * 190.0 * (0.45 + 1.1 * drain) + 170.0 * dens + treble * 40.0;
    let sinT = factor / 1.33;
    let film = soapFilm(sqrt(max(1.0 - sinT * sinT, 0.0)), dNm, 1.33);
    // The film reflects a soft top-lit room (+ a small window): that light is taken from the transmitted photo.
    let rUp = clamp(-2.0 * cosI * toMouse.y / max(deformedRadius, 0.001), -1.0, 1.0);
    let room = 0.9 + 0.45 * rUp;
    let nrm = vec3<f32>(toMouse / max(deformedRadius, 0.001), cosI);
    let windowHi = pow(max(dot(nrm, vec3<f32>(-0.4511, -0.5514, 0.7018)), 0.0), 48.0) * 0.8; // light dir = normalize(-0.45,-0.55,0.70)
    let refl = clamp(0.14 + 0.86 * fresnel, 0.0, 1.0);
    finalColor = sample * (1.0 - 0.5 * refl) + film * room * refl * 2.0 + vec3<f32>(windowHi);

    let fluidTint = mix(vec3<f32>(1.0), vec3<f32>(1.0, 0.85, 0.6), dens * 0.4);
    finalColor *= fluidTint;

    if (influence * dens > 0.002) {
      let specular = glints(uv * aspectVec * 60.0 + vec2<f32>(time * 0.6, -time * 0.4), time) * influence * dens * 2.4;
      finalColor += vec3<f32>(0.9, 0.95, 1.0) * specular;
    }

    let highlight = pow(max(0.0, 1.0 - factor), 3.0) * fresnel;
    finalColor += vec3<f32>(highlight);

    let absorption = exp(-filmThickness * 0.5);
    alpha = clamp(mix(absorption, 1.0, fresnel) * mix(0.5, 1.0, dens * 0.3) + held * 0.15, 0.2, 1.0);
  } else {
    let outsideWarp = clamp(uv + vel * dens * 0.005, vec2<f32>(0.001), vec2<f32>(0.999));
    finalColor = textureSampleLevel(readTexture, u_sampler, outsideWarp, 0.0).rgb;
    alpha = 1.0;
  }

  let finalRGB = aces(max(finalColor, vec3<f32>(0.0)));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, coord, finalPixel);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
