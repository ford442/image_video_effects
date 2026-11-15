// ═══════════════════════════════════════════════════════════════════
//  Solar Wind Ribbons
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium-High
//  Created: 2026-05-30
//  Upgraded: 2026-09-15, 2026-11-15
//  Ideas: Parker spiral IMF lag in ribbonCentre; Kelvin-Helmholtz scallops on the sheet edge; field-aligned flux-tube striations (nearest-segment s + signed side promoted from the min-distance search, faded where a far branch of the sheet competes); reconnection flare where two ribbons cross (pairwise mask overlap)
//  Rescue: nearest-SEGMENT distance on a rolling window of centres (HEAD took the nearest of 64 points, so thin ribbons rendered as beads; 68 ribbonCentre calls per ribbon instead of 128)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  Streaming ribbons of magnetised plasma — coronal mass ejection
//  caught mid-flight, woven into curtains of aurora.

#include "_prelude.wgsl"
// zoom_params: x=RibbonCount, y=Twist, z=Speed, w=Glow

// Tuning gains for the 2026-11-15 ideas (1.0 = shipped look).
const STRI_GAIN: f32 = 1.0;    // Idea 1: flux-tube striations
const FLARE_GAIN: f32 = 1.0;   // Idea 2: reconnection flare

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0; var amp = 0.5; var pp = p;
  for (var i = 0u; i < 5u; i++) {
    v += amp * noise2(pp); pp *= 2.0; amp *= 0.5;
  }
  return v;
}

// Parametric ribbon centre-line. Idea 1: Parker spiral lag grows with |s|.
fn ribbonCentre(s: f32, t: f32, twist: f32, bass: f32, idx: f32) -> vec2<f32> {
  let phase = idx * 1.37 + t * 0.3;
  let rAbs = abs(s * 2.0 - 1.0) + 0.18;
  let parker = 0.55 * rAbs;
  let x = s * 2.0 - 1.0 + sin(s * 6.28 * twist + phase + parker) * 0.25 * (1.0 + bass * 0.5);
  let y = 0.5 * sin(s * 3.14159 + t * 0.5 + phase * 0.7 + parker * 0.35) * (1.0 + bass * 0.2);
  return vec2<f32>(x, y);
}

// The sheet-edge point at parameter s: centre-line point displaced along the forward-difference normal by the
// Kelvin-Helmholtz scallop (identical maths to HEAD's per-sample point; c1 is the centre at s + ds).
fn ribbonPoint(c0: vec2<f32>, c1: vec2<f32>, s: f32, ts: f32, width: f32, fi: f32) -> vec2<f32> {
  let tang = c1 - c0;
  let perp = vec2<f32>(-tang.y, tang.x) * inverseSqrt(max(dot(tang, tang), 1.0e-8));
  let kh = sin(s * 18.0 + ts * 3.2 + fi * 1.7) * width * 0.85;
  return c0 + perp * kh;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }
  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / vec2<f32>(dims);
  let t = u.config.x;

  let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let nRibbons  = i32(mix(3.0, 14.0, u.zoom_params.x));
  let twist     = mix(0.5, 4.0, u.zoom_params.y);
  let speed     = mix(0.1, 1.2, u.zoom_params.z);
  let glowPower = mix(0.5, 3.0, u.zoom_params.w) * (1.0 + mids * 0.3);

  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  p -= mouse * 0.3 * u.zoom_config.w;

  var col = vec3<f32>(0.0);
  let nSamples = 64;
  let ds = 1.0 / f32(nSamples);
  let ts = t * speed;
  var sumM = 0.0;
  var sumM2 = 0.0;

  for (var ri = 0; ri < nRibbons; ri++) {
    let fi = f32(ri);
    let hue = fract(fi / f32(nRibbons) + t * 0.04 + bass * 0.1);
    let ribbonCol = vec3<f32>(
      0.5 + 0.5 * cos(6.2832 * hue),
      0.5 + 0.5 * cos(6.2832 * (hue + 0.33)),
      0.5 + 0.5 * cos(6.2832 * (hue + 0.67))
    );
    let width = mix(0.01, 0.05, fract(fi * 0.618)) * (1.0 + bass * 0.4);
    // ── Rescue 1: nearest SEGMENT of the polyline, not the nearest of 64 points. A rolling window of three centres
    // (one new ribbonCentre per step) gives the segment P(s)->P(s+ds); at the sample points it equals HEAD exactly. ──
    var cA = ribbonCentre(0.0, ts, twist, bass, fi);
    var cB = ribbonCentre(ds, ts, twist, bass, fi);
    var pA = ribbonPoint(cA, cB, 0.0, ts, width, fi);
    var minD2 = 1e12;
    var bestS = 0.0;
    var minD2b = 1e12;   // runner-up: best distance among segments whose s is > 0.06 away from the winner's
    for (var si = 0; si < nSamples; si++) {
      let s = f32(si) * ds;
      let cC = ribbonCentre(s + 2.0 * ds, ts, twist, bass, fi);
      let pB = ribbonPoint(cB, cC, s + ds, ts, width, fi);
      let seg = pB - pA;
      let w = p - pA;
      let tt = clamp(dot(w, seg) / max(dot(seg, seg), 1.0e-8), 0.0, 1.0);
      let dv = w - seg * tt;
      let dd2 = dot(dv, dv);
      let sNew = s + tt * ds;
      let better = dd2 < minD2;
      // a far-away segment (or the old winner, when a far-away segment displaces it) can be the runner-up
      minD2b = select(minD2b, min(minD2b, select(dd2, minD2, better)), abs(sNew - bestS) > 0.06);
      minD2 = select(minD2, dd2, better);
      bestS = select(bestS, sNew, better);
      cB = cC;
      pA = pB;
    }
    let minDist = sqrt(minD2);
    // Signed across-sheet offset at the winning parameter, from the centre-line normal minus the scallop shift
    // (one extra pair of ribbonCentre calls per ribbon instead of per sample).
    let bc0 = ribbonCentre(bestS, ts, twist, bass, fi);
    let bt = ribbonCentre(bestS + ds, ts, twist, bass, fi) - bc0;
    let bestSide = (bt.x * (p.y - bc0.y) - bt.y * (p.x - bc0.x)) * inverseSqrt(max(dot(bt, bt), 1.0e-8))
        - sin(bestS * 18.0 + ts * 3.2 + fi * 1.7) * width * 0.85;
    let m = exp(-minDist * minDist / (width * width * 2.0));
    let mask = m * glowPower;
    sumM += m;
    sumM2 += m * m;
    let detail = fbm(p * 5.0 + vec2<f32>(t * 0.1, fi * 0.4));
    // ── Idea 1: field-aligned flux-tube striations (native) ──
    // Plasma fine structure follows the field, i.e. runs ALONG the ribbon: high frequency across the sheet
    // (signed side / width), low frequency along it (bestS), drifting with the flow. Mean-neutral (0.25 + 1.5*0.5).
    let sideN = bestSide / max(width, 1.0e-4);
    let strandA = noise2(vec2<f32>(bestS * 7.0 - ts * 1.2 + fi * 7.3, sideN * 2.3 + fi));
    let strandB = noise2(vec2<f32>(bestS * 15.0 - ts * 2.1 + fi * 3.1, sideN * 5.7));
    let strand = 0.65 * strandA + 0.35 * strandB;
    // Where the sheet folds back on itself the winning segment (hence bestS / side) flips between far-apart parameters and
    // the filaments would show a stair-stepped seam. Fade them to 1 where a far branch (|s - bestS| > 0.06) is within
    // 2.5 widths of the winner; 0.5 widths left the seam visible, because the runner-up's own identity also flips there.
    let unambiguous = smoothstep(0.0, 2.5 * width, sqrt(minD2b) - minDist);
    let striation = mix(1.0, mix(1.0, 0.25 + 1.5 * strand, unambiguous), STRI_GAIN);
    col += ribbonCol * mask * (0.7 + 0.3 * detail) * striation * (1.0 + treble * 0.2);
  }

  // ── Idea 2: reconnection flare where two ribbons cross (native) ──
  // Magnetised sheets that cross reconnect and heat: pairwise core overlap sum_{i<j} m_i m_j = (S^2 - sum m^2)/2
  // is ~0 on a lone ribbon and ~1 where two cores coincide, so it lights only the crossings.
  let overlap = 0.5 * (sumM * sumM - sumM2);
  let flare = smoothstep(0.28, 0.95, overlap) * FLARE_GAIN;
  // Falls off as (8 / ribbon count)^2 above 8 ribbons: with 14 sheets nearly every pixel overlaps two cores and the flare
  // washed thin ribbons white. (The saved default is ~7 ribbons, so the default look keeps its full flare.)
  let flareScale = pow(8.0 / max(f32(nRibbons), 8.0), 2.0);
  col += vec3<f32>(1.0, 0.78, 0.52) * flare * flareScale * glowPower * 0.6 * (1.0 + bass * 0.4);

  let streakY = fract(p.y * 8.0 + t * 0.15 + bass * 0.1);
  let streak = exp(-abs(streakY - 0.5) * 40.0) * 0.06;
  col += vec3<f32>(0.3, 0.6, 1.0) * streak;

  let mapped = acesToneMap(col * 1.05);
  let luma = dot(mapped, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luma * 0.9 + streak * 0.1, 0.0, 1.0);
  let depth = clamp(1.0 - length(p) * 0.4, 0.0, 1.0);
  let finalColor = vec4<f32>(mapped, alpha);

  textureStore(writeTexture,      coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, finalColor);
}
