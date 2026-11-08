// ═══════════════════════════════════════════════════════════════════
//  Topological Acoustic Knots v4
//  Category: generative
//  Features: nematic-Q-tensor, topological-charge, trefoil-sdf,
//            schlieren-texture, audio-driven, mouse-anchoring, temporal,
//            upgraded-rgba
//  Complexity: Very High
//  Chunks From: nematic tensor + defect tracking + ACES tm
//  Created: 2026-05-31
//  By: 4-Agent Upgrade Swarm
//  Upgraded: 2026-11-08
//  Ideas: crossed-polarizer extinction brushes (2 per ±1/2 core, 4 per ±1); birefringence retardance tint (dn ~ S, Michel-Levy, trefoil thickness wedge); Kibble-Zurek correlated quench noise growing where order is low
//  A packing: raw sim state (Qxx, Qxy, S, defectDensity) - SIGNED, never tone-mapped; ACES on writeTexture only
//  v3 (2026-07-22, Algorithmist swarm): honest slider wiring -
//    p1 -> Kibble-Zurek quench amplitude (true defect nucleation rate)
//    p3 -> opposite-sign annihilation rate + annihilation flash
//  v4 (2026-11-08): rescue - at HEAD any audio >= 0.1 pinned the order
//    parameter S at 0 (alpha = S -> black). Fixes: S melts at a fractional
//    rate; C read with exact textureLoad (was a filtering sampler at texel
//    corners -> drift + blur) and the director decoded from Q (was Qxx read
//    as an angle); charge is a true plaquette winding number; the polarizer
//    sweep / cascade pulse lived in extraBuffer[133..136], which the host
//    re-uploads (zeroes) every frame, so they are now stateless.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Smooth value noise: correlated over one cell (HEAD fed raw hash12 per pixel
// into the quench, so every pixel nucleated independently - white noise).
fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (2.51 * x + 0.03);
  let b = x * (2.43 * x + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Trefoil knot SDF (2D projection slice)
fn trefoilSDF(uv: vec2<f32>, t: f32) -> f32 {
  let p = (uv - 0.5) * 6.283185;
  // Projected trefoil parametric
  let kx = sin(p.x) + 2.0 * sin(2.0 * p.x);
  let ky = cos(p.x) - 2.0 * cos(2.0 * p.x);
  let proj = vec2<f32>(kx * 0.12 + 0.5, ky * 0.12 + 0.5);
  let d = length(uv - proj);
  let p2 = vec2<f32>(sin(p.y + t) + 2.0 * sin(2.0 * p.y + t), cos(p.y + t) - 2.0 * cos(2.0 * p.y + t)) * 0.12 + 0.5;
  let d2 = length(uv - p2);
  return min(d, d2);
}

// Exact (unfiltered) state read with edge clamp. C holds SIGNED sim state.
fn loadQ(c: vec2<i32>, dim: vec2<i32>) -> vec4<f32> {
  return textureLoad(dataTextureC, clamp(c, vec2<i32>(0), dim - vec2<i32>(1)), 0);
}

// Director angle from the stored Q-tensor: Qxx = S(nx^2 - 1/3), Qxy = S nx ny
// => S cos2t = 2 Qxx - S/3, S sin2t = 2 Qxy.
fn dirAngle(q: vec4<f32>) -> f32 {
  return 0.5 * atan2(2.0 * q.g, 2.0 * q.r - q.b * 0.33333334);
}

// A director is a headless line: angle differences live in (-pi/2, pi/2].
fn wrapHalfPi(d: f32) -> f32 {
  return d - 3.14159265 * round(d / 3.14159265);
}

// Winding number of the director on an 8-point loop of Chebyshev radius R
// around c: +-0.5 for a nematic disclination, +-1 for a pinned hedgehog.
fn windingAt(c: vec2<i32>, R: i32, dim: vec2<i32>) -> f32 {
  let a0 = dirAngle(loadQ(c + vec2<i32>( R, 0), dim));
  let a1 = dirAngle(loadQ(c + vec2<i32>( R, R), dim));
  let a2 = dirAngle(loadQ(c + vec2<i32>( 0, R), dim));
  let a3 = dirAngle(loadQ(c + vec2<i32>(-R, R), dim));
  let a4 = dirAngle(loadQ(c + vec2<i32>(-R, 0), dim));
  let a5 = dirAngle(loadQ(c + vec2<i32>(-R,-R), dim));
  let a6 = dirAngle(loadQ(c + vec2<i32>( 0,-R), dim));
  let a7 = dirAngle(loadQ(c + vec2<i32>( R,-R), dim));
  let w = wrapHalfPi(a1 - a0) + wrapHalfPi(a2 - a1) + wrapHalfPi(a3 - a2) + wrapHalfPi(a4 - a3)
        + wrapHalfPi(a5 - a4) + wrapHalfPi(a6 - a5) + wrapHalfPi(a7 - a6) + wrapHalfPi(a0 - a7);
  return w * 0.15915494;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
  let dim = vec2<i32>(res);
  let ci = vec2<i32>(gid.xy);
  // Lattice scale: winding-loop radius grows with render height so the
  // defect look is the same at 192 px and at 1080 px.
  let R = max(2, i32(round(res.y / 216.0)));
  let uv = (vec2<f32>(gid.xy) + vec2<f32>(0.5)) / res;
  let time = u.config.x * 0.8;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;

  // Read previous nematic state: Qxx, Qxy, S, defect (exact loads)
  let prev = loadQ(ci, dim);
  let prevS = clamp(prev.b, 0.0, 1.0);
  let prevAngle = dirAngle(prev);

  // Neighbour Q for relaxation. Q-averaging (S-weighted) is the elastic
  // one-constant relaxation: melted cores (S ~ 0) don't vote on the director.
  let n = loadQ(ci + vec2<i32>(0, 1), dim);
  let s = loadQ(ci + vec2<i32>(0, -1), dim);
  let e = loadQ(ci + vec2<i32>(1, 0), dim);
  let w = loadQ(ci + vec2<i32>(-1, 0), dim);
  let sumC = (2.0 * (n.r + s.r + e.r + w.r)) - (n.b + s.b + e.b + w.b) * 0.33333334;
  let sumS = 2.0 * (n.g + s.g + e.g + w.g);
  let avgAngle = select(prevAngle, 0.5 * atan2(sumS, sumC), (sumC * sumC + sumS * sumS) > 1e-8);

  // Relaxation with mobility (wrap-aware: the director is mod pi)
  let mobility = 0.3 + mids * 0.7 + p2 * 0.5;
  var angle = prevAngle + wrapHalfPi(avgAngle - prevAngle) * clamp(mobility * 0.25, 0.0, 0.9);

  // ── Idea 3: Kibble-Zurek quench toward a random smooth Q-field ─────────
  // p1 ('Defect Density') scales the nucleation strength, so the slider
  // directly controls how many defect pairs nucleate; bass heats the film.
  // Where order is low (the isotropic start) the director is pulled toward a
  // random, smooth Q-tensor field (two noise components) with correlation
  // length ~1/9 of the screen. The zeros of that field are exactly the +-1/2
  // disclinations, so defects appear where the domains meet and are
  // independent of the render resolution. The pull freezes out as S grows
  // ((1-S)^4), leaving the defects behind to coarsen / annihilate. (HEAD's flat
  // +-0.09 rad per-pixel noise never produced a defect; a first draft here used
  // a per-block hash and left a visible pixel mosaic above ~512 px.)
  let freeze = pow(1.0 - prevS, 4.0);
  let qAmp = freeze * (0.9 + bass * 1.5) * (0.5 + p1);
  let qa = vnoise(uv * 9.0 + vec2<f32>(time * 0.11, 3.0)) - 0.5;
  let qb = vnoise(uv * 9.0 + vec2<f32>(-time * 0.09, 17.0)) - 0.5;
  let noiseAngle = 0.5 * atan2(qb, qa);
  let quenchNoise = wrapHalfPi(noiseAngle - angle) * clamp(qAmp * 0.5, 0.0, 0.7);
  angle += quenchNoise;

  // Treble adds acoustic phonon waves
  let phonon = sin(uv.x * 18.0 + time * 5.0 + treble * 3.0) * cos(uv.y * 14.0 - time * 4.0) * treble * 0.08;
  angle += phonon;

  // Trefoil knot SDF constraint: director avoids knot curve
  let knotDist = trefoilSDF(uv, time * 0.2);
  let knotInfluence = smoothstep(0.08, 0.0, knotDist) * (0.5 + p3 * 0.5);
  let tangentAngle = atan2(cos(uv.x * 6.283185 + time), sin(uv.y * 6.283185));
  angle = angle + wrapHalfPi(tangentAngle - angle) * knotInfluence * 0.6;

  // Mouse homeotropic anchoring: pins director radially
  let mouseDist = length(uv - mouse);
  let anchor = smoothstep(0.18, 0.0, mouseDist) * mouseDown * (1.0 + p4 * 2.0);
  let radialAngle = atan2(uv.y - mouse.y, uv.x - mouse.x);
  // (clamped: anchor*0.85 reaches 2.4 at p4=1, and a factor > 1 overshoots the
  // radial target every frame - the pinned region diverged instead of pinning)
  angle = angle + wrapHalfPi(radialAngle - angle) * clamp(anchor * 0.85, 0.0, 1.0);

  // Ripples spawn defect loops (age in the same clock as the start time)
  let rCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rCount; i = i + 1u) {
    let rp = u.ripples[i];
    let rd = length(uv - rp.xy);
    let rt = (u.config.x - rp.z) * 0.8;
    let rippleStrength = exp(-rd * 6.0) * smoothstep(2.5, 0.0, rt) * 0.12 * step(0.0, rt);
    angle += rippleStrength * sin(rt * 8.0 + rd * 15.0);
  }

  // Reconstruct Q tensor: Q = s(nn^T - I/3)
  let nx = cos(angle);
  let ny = sin(angle);
  // Order parameter: relaxes toward 0.7 at 3 %/frame. Bass / quench MELT it
  // at a fractional per-frame rate (HEAD subtracted an absolute |disorder|, which
  // exceeds the recovery for any bass > ~0.08 and pinned S - and alpha - at 0).
  let relaxS = mix(prevS, 0.7, 0.03);
  // melt rate is super-linear in bass: a loud hit re-quenches the film (S drops,
  // the Kibble-Zurek noise below re-nucleates domains while S recovers),
  // sustained moderate audio keeps it ordered and visible.
  let melt = clamp(bass * bass * 0.05 + bass * 0.008, 0.0, 0.5);
  let S = clamp(relaxS * (1.0 - melt), 0.0, 1.0);

  // Topological charge: true plaquette winding of last frame's director.
  // ±0.5 = nematic disclination (blue), ±1 = pinned hedgehog (red / bloom).
  let chargeRaw = windingAt(ci, R, dim);

  // ── Annihilation dynamics (Defect Pairing, p3) ─────────────────────
  // Windings of the plaquettes 2R px east and west: where they carry OPPOSITE
  // sign a +defect and a -defect sit side by side - p3 damps the local
  // winding (pair annihilation) and melts the order parameter at the core.
  let windE = windingAt(ci + vec2<i32>(2 * R, 0), R, dim);
  let windW = windingAt(ci + vec2<i32>(-2 * R, 0), R, dim);
  let oppPair = select(0.0, 1.0, windE * windW < -0.05);
  let annihilation = oppPair * p3 * smoothstep(0.05, 0.4, abs(chargeRaw));
  let charge = clamp(chargeRaw * (1.0 - annihilation * 0.55), -1.0, 1.0);

  // Defect density
  let defectDensity = smoothstep(0.15, 0.5, abs(charge));

  // Annihilation melts the core: reduce S locally (re-derived Q stays signed)
  let Sann = clamp(S * (1.0 - annihilation * 0.5), 0.0, 1.0);
  let QxxAnn = Sann * (nx * nx - 0.3333);
  let QxyAnn = Sann * nx * ny;

  // Store state (SIGNED Q-tensor sim state - never clamp/tonemap this write)
  textureStore(dataTextureA, gid.xy, vec4<f32>(QxxAnn, QxyAnn, Sann, defectDensity));

  // ── Idea 1: crossed-polarizer extinction brushes ───────────────────
  // Between crossed polarizers the transmitted light is sin^2(2(theta - phi)),
  // so a +-1/2 core shows 2 dark brushes and a +-1 core 4 (HEAD's single
  // polarizer term gave one brush per core). The polarizer angle phi sweeps
  // with time and wobbles with mids - stateless (the old extraBuffer[136]
  // accumulator was zeroed by the host every frame).
  let phi = time * 0.45 + sin(time * 0.7) * mids * 0.8;
  let sb = sin(2.0 * (angle - phi));
  let brush = sb * sb;

  // ── Idea 2: birefringence retardance tint (Michel-Levy) ────────────
  // Retardance Gamma = dn * d with dn ~ S: ordered film is coloured,
  // melted cores (S -> 0) go isotropic-black. The film is thicker around the
  // trefoil (wedge), so the knot reads as interference-colour contours.
  let wedge = smoothstep(0.35, 0.0, knotDist);
  let gammaNm = (180.0 + 2300.0 * (0.35 + 0.65 * wedge)) * Sann;
  let phase = sin(vec3<f32>(3.14159265) * gammaNm / vec3<f32>(650.0, 550.0, 450.0));
  let retard = phase * phase;

  // Defect core colors: integer (red) vs half-integer (blue)
  let isInteger = abs(abs(charge) - 1.0) < 0.3;
  let defectCol = select(vec3<f32>(0.3, 0.5, 1.0), vec3<f32>(1.0, 0.3, 0.2), isInteger);
  // core halo: a 2-px plaquette flag is tiny at high resolution, so spread last
  // frame's defect flag over a smooth 3x3 (stride 3) tent for the glow footprint.
  var halo = 0.0;
  for (var hy: i32 = -1; hy <= 1; hy = hy + 1) {
    for (var hx: i32 = -1; hx <= 1; hx = hx + 1) {
      let wgt = (2.0 - abs(f32(hx))) * (2.0 - abs(f32(hy))) * 0.0625;
      halo += loadQ(ci + vec2<i32>(hx, hy) * (R + 1), dim).a * wgt;
    }
  }
  let coreMask = max(defectDensity, clamp(halo * 2.0, 0.0, 1.0));
  let defectGlow = coreMask * defectCol * (0.85 + treble * 0.9);

  // HDR bloom on +1 defects
  let plusOneBloom = select(0.0, 1.0, charge > 0.65) * coreMask * vec3<f32>(1.0, 0.7, 0.4) * 2.0;

  let base = retard * (0.10 + 0.90 * brush) * 1.25;
  var hdr = base + defectGlow + plusOneBloom + vec3<f32>(phonon * 0.3 + 0.1);

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + bass);
  hdr = vec3<f32>(hdr.r + caStr, hdr.g, hdr.b - caStr * 0.5);

  // Exposure: steady base + a local flash where a +/- pair annihilates
  // (replaces the global cascade pulse that lived in zeroed extraBuffer[135]).
  let flash = annihilation * 1.4;
  let tone = acesToneMap(max(hdr, vec3<f32>(0.0)) * (0.85 + flash * 0.7));

  // Alpha: order parameter S × (1.0 + defect_charge_density)
  let alpha = clamp(S * (1.0 + defectDensity * 0.6) * 0.7, 0.0, 1.0);

  textureStore(writeTexture, gid.xy, vec4<f32>(tone * alpha, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(defectDensity * 0.8 + S * 0.2, 0.0, 0.0, 0.0));
}
