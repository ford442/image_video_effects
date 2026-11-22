// ═══════════════════════════════════════════════════════════════════
//  audio-reactive-rgb-dispersion
//  Category: post-processing
//  Features: audio-reactive, fft-bins, frequency-coupled, chromatic-aberration
//  Complexity: Medium
//  Created: 2026-05-23
//  By: copilot / P6 audio bridge
//  Upgraded: 2026-10-05, 2026-11-01, 2026-11-22
//  Ideas: bandwidth rainbow (spectral spread → 5-tap wavelength smear); lateral vs transverse CA by band balance; Cauchy tap spacing (§12.2F); edge-weighted falloff; highlight-gated blue defocus (longitudinal CA / purple fringing); r³ lateral CA profile (Brown–Conrady k₁, §12.2B)
//  A packing: display RGBA (passthrough grade, no ACES)
//
//  Chromatic (RGB) dispersion whose offset magnitudes and direction are
//  driven by the spectral centroid computed from the live FFT bin array.
//
//    Spectral centroid = Σ(bin_i × freq_i) / Σ(bin_i)
//      (weighted average frequency, normalised to [0, 1])
//
//  Low centroid (bass-heavy music) → tight, warm dispersion (slight red push).
//  High centroid (treble-heavy)    → wide, cool dispersion (strong cyan push).
//
//  2026-11-22: blue defocuses into the dark side of clipped highlights
//  (purple fringing), and the radial (bass) CA follows a real lens's r³ growth.
//  Rescue (2026-11-22): linear fringe / edge probe were uv-space offsets, so
//  on a non-square canvas the fringe was anisotropic (16:9: vertical 0.56×
//  horizontal); now px offsets are equal in every direction. Square: unchanged.
//
//  extraBuffer layout (relevant slots):
//    [0]  bass,  [1] mid,  [2] treble
//    [5..132] FFT bins 0..127 (normalised 0–1)
//
//  Parameters:
//    param1 (zoom_params.x) : Dispersion Scale  (0=none, 1=max ~3% of width)
//    param2 (zoom_params.y) : Angle Offset       (additional rotation, 0–1→0–2π)
//    param3 (zoom_params.z) : Edge Falloff       (1=radial falloff, 0=uniform)
//    param4 (zoom_params.w) : Original Blend     (0=full effect, 1=original)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Scale, y=AngleOffset, z=Falloff, w=OrigBlend

// ── helpers ──────────────────────────────────────────────────────────────────

fn fftBin(idx: u32) -> f32 {
  let slot = idx + 5u;
  if (slot >= arrayLength(&extraBuffer)) { return 0.0; }
  return clamp(extraBuffer[slot], 0.0, 1.0);
}

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

struct Spectrum {
  centroid: f32,   // 0 = bass, 1 = treble (0.5 on silence)
  energy:   f32,   // mean bin magnitude
  spread:   f32,   // spectral bandwidth (2nd central moment, sqrt), 0..~0.5
  balance:  f32,   // bass share of (bass + treble) band energy, 0..1
};

/// One pass over bins [0..127]: centroid, energy, spread and band balance.
/// (HEAD ran two separate 128-bin loops per pixel.)
fn analyseSpectrum() -> Spectrum {
  var weightedSum = 0.0;
  var weightedSq  = 0.0;
  var totalPower  = 0.0;
  var bassPower   = 0.0;
  var treblePower = 0.0;
  for (var i = 0u; i < 128u; i++) {
    let mag  = fftBin(i);
    let freq = f32(i) / 127.0;   // normalised frequency 0..1
    weightedSum += mag * freq;
    weightedSq  += mag * freq * freq;
    totalPower  += mag;
    if (i < 16u) { bassPower += mag; }
    if (i >= 48u) { treblePower += mag; }
  }
  var sp: Spectrum;
  sp.energy = totalPower / 128.0;
  if (totalPower < 0.001) {   // silence fallback
    sp.centroid = 0.5;
    sp.spread = 0.0;
    sp.balance = 0.0;
    return sp;
  }
  let c = clamp(weightedSum / totalPower, 0.0, 1.0);
  sp.centroid = c;
  sp.spread = sqrt(max(weightedSq / totalPower - c * c, 0.0));
  // per-bin means so the 16 bass bins and 80 treble bins compare fairly
  let bassMean = bassPower / 16.0;
  let trebleMean = treblePower / 80.0;
  sp.balance = bassMean / max(bassMean + trebleMean, 1e-4);
  return sp;
}

/// Idea 1 helper: wavelength position λ (0 = red end, 1 = blue end) → offset
/// scalar along the dispersion axis. λ=0 lands on HEAD's red offset, λ=0.5 on
/// the anchored green (0), λ=1 on HEAD's blue offset.
fn wavelengthOffset(lambda: f32, redAmt: f32, blueAmt: f32) -> f32 {
  if (lambda < 0.5) { return redAmt * (1.0 - 2.0 * lambda); }
  return -blueAmt * (2.0 * lambda - 1.0);
}

/// Idea 1 helper: channel response of a wavelength tap (Gaussian around the
/// channel's centre wavelength, width w). Normalised per channel by the caller.
fn channelResponse(lambda: f32, w: f32) -> vec3<f32> {
  let d = vec3<f32>(lambda) - vec3<f32>(0.0, 0.5, 1.0);
  return exp(-(d * d) / (2.0 * w * w));
}

// ── Idea: Cauchy tap spacing (§12.2F)
// n(λ) = 1 + B/λ². Endpoints stay on the red and blue offsets the smear
// already used; interior taps bunch toward the red, the way glass does.
fn cauchyLambda(lambda: f32) -> f32 {
  let lam = mix(0.650, 0.450, clamp(lambda, 0.0, 1.0));
  let n = 1.0 + 0.012 / max(lam * lam, 1e-4);
  let nR = 1.0 + 0.012 / (0.650 * 0.650);
  let nB = 1.0 + 0.012 / (0.450 * 0.450);
  return clamp((n - nR) / max(nB - nR, 1e-4), 0.0, 1.0);
}

// ── main ─────────────────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.z, u.config.w);
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

  let uv     = (vec2<f32>(global_id.xy) + 0.5) / res;
  let centre = vec2<f32>(0.5);

  // ── Audio analysis (single loop) ─────────────────────────────────
  let spec     = analyseSpectrum();
  let centroid = spec.centroid;   // 0=bass, 1=treble
  let energy   = spec.energy;     // overall loudness

  // ── Parameters ──────────────────────────────────────────────────
  // Scale: higher centroid → wider dispersion
  let maxOffset  = mix(0.0, 0.03, u.zoom_params.x);
  let dispersion = maxOffset * energy * (0.3 + centroid * 0.7);

  // Dispersion direction rotates with centroid + user angle offset
  let angleBase   = centroid * 3.14159;              // 0 (bass) → π (treble)
  let angleOffset = u.zoom_params.y * 6.28318;       // full circle
  let angle       = angleBase + angleOffset;

  let dir = vec2<f32>(cos(angle), sin(angle));

  // Radial falloff: effects stronger at edges, gentler at centre.
  // ── Idea 2: edge-weighted falloff
  // Local contrast along the dispersion direction joins the radius, so a
  // prism split prefers edges. falloff = 0 stays uniform.
  let falloff     = u.zoom_params.z;
  let radialDist  = length(uv - centre) * 2.0;       // 0 at centre, 1 at edge midpoints, ~1.41 at corners
  // Rescue (2026-11-22): the probe is 1.5 px along `dir` in screen space
  // (HEAD used 1.5/min(res) in uv, which is anisotropic when res.x != res.y).
  let foot = vec2<f32>(1.5) / max(res, vec2<f32>(1.0));
  let edgeA = textureSampleLevel(readTexture, u_sampler, clamp(uv + dir * foot, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
  let edgeB = textureSampleLevel(readTexture, u_sampler, clamp(uv - dir * foot, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
  let edge = clamp(abs(dot(edgeA - edgeB, vec3<f32>(0.2126, 0.7152, 0.0722))) * 4.0, 0.0, 1.0);
  let radialScale = mix(1.0, mix(radialDist, max(radialDist, edge), 0.7), falloff);

  // Idea 2: Lateral vs transverse — treble keeps HEAD's linear shift along the
  // centroid direction (transverse); bass energy drives a radial, lens-like
  // lateral CA that grows from the frame centre. The two geometries mix by
  // band balance, so a kick drum blooms outward while hats slide sideways.
  // Rescue (2026-11-22): uv offsets scaled so the px fringe is the same in every
  // direction (y scaled by W/H: = HEAD's horizontal size; (1,1) on square).
  let aspect     = vec2<f32>(1.0, res.x / max(res.y, 1.0));
  let axisLinear = dir * aspect * radialScale;
  // ── Idea 2026-11-22 B: r³ lateral CA profile (Brown–Conrady k₁, §12.2B) ─
  // Lateral CA is linear in field radius only to first order; a real lens adds
  // an r³ term, so corners fringe far more than the centre. |axisRadial| =
  // r·(0.35 + 0.65 r²): HEAD's value at r = 1 (edge midpoints), ~½ at r = 0.5,
  // ~1.65× in the corners. Only the radial (bass) branch changes.
  let radialVec  = (uv - centre) * 2.0;              // |.| = radialDist, points outward
  let axisRadial = radialVec * (0.35 + 0.65 * dot(radialVec, radialVec));
  // Shaped so ordinary (bass-heavy, balance ~0.7-0.85) mixes stay mostly linear and
  // the angle slider keeps its grip; only a bass-dominated hit goes half radial.
  let radialMix  = smoothstep(0.6, 0.95, spec.balance) * 0.6;
  let axis       = mix(axisLinear, axisRadial, radialMix);

  // R and B are displaced in opposite directions along the axis; G is the
  // stable anchor at the undisplaced UV (no net hue shift at rest).
  let redAmt  = dispersion * (1.0 - centroid * 0.5); // red: broader at low centroid
  let blueAmt = dispersion * (0.5 + centroid * 0.5); // blue: broader at high centroid

  // Idea 1: Bandwidth rainbow — 5 wavelength taps from the red end to the blue
  // end of the axis. Tonal music (narrow spread) → each channel reads only its
  // own tap = HEAD's two crisp fringes; broadband/noisy music widens every
  // channel's response across neighbouring taps → a rainbow smear.
  // Per-channel weights are normalised, so the smear conserves energy.
  let bandwidth = smoothstep(0.08, 0.3, spec.spread);
  let respW = mix(0.06, 0.32, bandwidth);
  var acc  = vec3<f32>(0.0);
  var wsum = vec3<f32>(0.0);
  // Idea 2026-11-22 A (purple fringing): keep blue's own tap and the brightest
  // tap in reach (the tap luma HEAD threw away).
  var centreB = 0.0;
  var hiLuma  = 0.0;
  // Undisplaced sample stays the blend anchor. Cauchy moves the interior
  // taps, so the green anchor is no longer "tap k == 2".
  let anchor = textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
  for (var k = 0; k < 5; k++) {
    let lambda = f32(k) * 0.25;
    let spaced = cauchyLambda(lambda);
    let tapUV  = clamp(uv + axis * wavelengthOffset(spaced, redAmt, blueAmt), vec2<f32>(0.001), vec2<f32>(0.999));
    let tap    = textureSampleLevel(readTexture, u_sampler, tapUV, 0.0);
    let resp   = channelResponse(lambda, respW);
    acc  += tap.rgb * resp;
    wsum += resp;
    centreB = select(centreB, tap.b, k == 4);          // k = 4 is the blue end (λ = 1)
    hiLuma  = max(hiLuma, luma(tap.rgb));
  }
  var smeared = acc / max(wsum, vec3<f32>(1e-4));
  // ── Idea 2026-11-22 A: highlight-gated blue defocus (longitudinal CA) ───
  // Lateral CA (everything above) is only half of a lens's chromatic error: the
  // blue focal plane also differs from green's, so a clipped highlight leaks a
  // blue-violet halo onto the DARK side of its edge. The halo needs its own reach
  // (the 5 taps only span ~1–3 px): 4 blue-only taps, symmetric about blue's own
  // displaced position, at ±0.8 and ±1.8 × the tap span along the same axis.
  // Gate = a bright tap (≥ 0.6..0.9 luma) in reach AND brighter than this pixel
  // by 0.35..0.75 (dark side only). dispersion = 0 → span 0 → no halo (silence
  // stays an exact pass-through); no highlight → identical to HEAD.
  let spanS  = redAmt + blueAmt;
  let blueC  = uv + axis * wavelengthOffset(1.0, redAmt, blueAmt);
  var wideB  = centreB;
  var wideW  = 1.0;
  var reachL = hiLuma;
  for (var j = 0; j < 4; j++) {
    let m  = select(select(-1.8, -0.8, j == 1), select(0.8, 1.8, j == 3), j >= 2);
    let wj = select(0.3, 0.7, j == 1 || j == 2);
    let t  = textureSampleLevel(readTexture, u_sampler, clamp(blueC + axis * (spanS * m), vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).rgb;
    wideB  += t.b * wj;
    wideW  += wj;
    reachL  = max(reachL, luma(t));
  }
  let fringeGate = smoothstep(0.6, 0.9, reachL) * smoothstep(0.35, 0.75, reachL - luma(anchor.rgb));
  smeared.b = mix(smeared.b, wideB / wideW, fringeGate);

  let dispersed = vec4<f32>(smeared, anchor.a);      // semantic alpha = input alpha
  let output    = mix(dispersed, anchor, u.zoom_params.w);

  textureStore(writeTexture, global_id.xy, output);

  // Pass-through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 1.0));

  textureStore(dataTextureA, global_id.xy, output);
}
