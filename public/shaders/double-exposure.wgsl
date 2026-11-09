// ═══════════════════════════════════════════════════════════════════
//  Double Exposure Warp
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-06, 2026-11-09
//  Ideas: exposure-2 image circle (cos⁴ vignetting, §12.2 A); shutter-open dwell (held pointer integrates the exact-C history in scene-referred light)
//  A packing: ACES display RGBA; texel (0,0) = (glide.x, glide.y, 7 marker, fract(time)) cursor-glide state (masked wherever C is read as colour)
//  Motion: glide-anchored secondary exposure warp + rotational ripple shockwaves
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=ZoomLevel, y=Rotation, z=Opacity, w=WarpStrength

const PI: f32 = 3.141592653589793;

// ── Rescue R1: cursor glide in A texel (0,0) ─────────────────────────
// extraBuffer[133..] is re-uploaded zeroed every frame, so HEAD's spring could never persist (every pixel fell
// back to the raw cursor). State = A(0,0) = (glide.x, glide.y, GLIDE_MARK, fract(time)); every pixel reads the same
// C texel and integrates the same step, only pixel (0,0) stores it. First-order glide (a velocity cannot be stored
// f16-safely). Replaces the dead critically-damped spring (omega 13) with rate 13.
const GLIDE_MARK: f32 = 7.0;
fn glideStep(st: vec4<f32>, raw: vec2<f32>, time: f32, rate: f32) -> vec2<f32> {
  let ok = abs(st.z - GLIDE_MARK) < 0.01 && st.w >= 0.0 && st.w <= 1.0;
  let dt = clamp(fract(time - st.w), 0.001, 0.05);
  let g = st.xy + (raw - st.xy) * (1.0 - exp(-rate * dt));
  let snapped = select(g, raw, length(raw - g) < 0.003);   // exact at rest even through f16 rounding
  return select(raw, snapped, ok);
}

// ── Rescue R2: engine FFT bin (extraBuffer[5 + bin], 0..1, read-only). plasmaBuffer[1..] is never uploaded. ──
fn fftBin(i: u32) -> f32 {
  let idx = 5u + i;
  if (idx >= arrayLength(&extraBuffer)) { return 0.0; }
  return extraBuffer[idx];
}

fn hash21(p: vec2<f32>) -> vec2<f32> {
  let n = sin(dot(p, vec2<f32>(127.1, 311.7)));
  return fract(vec2<f32>(n, n * 1.6180339887)) * 2.0 - 1.0;
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash21(i).x;
  let b = hash21(i + vec2<f32>(1.0, 0.0)).x;
  let c = hash21(i + vec2<f32>(0.0, 1.0)).x;
  let d = hash21(i + vec2<f32>(1.0, 1.0)).x;
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var a = 0.5;
  var s = 0.0;
  var q = p;
  for (var i = 0; i < 4; i = i + 1) {
    s += a * valueNoise(q);
    q = q * 2.02;
    a *= 0.5;
  }
  return s;
}

fn rotate2d(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Inverse of the Narkowicz fit above (positive root of (a-cx)y² + (b-dx)y - ex = 0), x clamped below the 1.033 asymptote.
// Lets the dwell integrate scene-referred light instead of re-tone-mapping the already tone-mapped history.
fn acesInverse(x: vec3<f32>) -> vec3<f32> {
  let xc = clamp(x, vec3<f32>(0.0), vec3<f32>(0.995));
  let qa = 2.51 - 2.43 * xc;
  let qb = 0.03 - 0.59 * xc;
  let disc = max(qb * qb + 4.0 * qa * 0.14 * xc, vec3<f32>(0.0));
  return (sqrt(disc) - qb) / (2.0 * qa);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  // Rescue R2: HEAD read plasmaBuffer[3].z / [7].y (never uploaded -> always 0). Live per-bin FFT instead:
  // binA (old voice 2) rides the chroma split, binB (old voice 6) rides the flash hue. Zero audio => HEAD's idle look.
  let binA = fftBin(2u);
  let binB = fftBin(19u);

  // ── Rescue R1: pivot glide (rate 13 = HEAD omega) ────────────────────
  let isCorner = gid.x == 0u && gid.y == 0u;
  let gState = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let glide = glideStep(gState, mouse, time, 13.0);

  // Four saved controls preserved
  let zoomLevel = mix(0.4, 2.8, u.zoom_params.x) * (1.0 + bass * 0.22);
  let rotationParam = (u.zoom_params.y - 0.5) * PI * 1.5;
  let opacity = mix(0.1, 0.95, u.zoom_params.z);
  let warpStrength = mix(0.0, 0.65, u.zoom_params.w);

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthParallax = mix(0.8, 1.25, depth);

  // Capped click ripple rotational shockwaves
  var rippleRotation = 0.0;
  var rippleFlash = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.2) {
      let d = length((uv - r.xy) * aspectVec);
      let ring = exp(-abs(d - age * 0.44) * 28.0) * exp(-age * 1.4);
      rippleRotation += ring * sin(age * 8.0) * 0.4;
      rippleFlash += ring;
    }
  }

  // Base exposure (layer 1)
  let c1 = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Transform secondary layer relative to the glided pivot
  var p = (uv - glide) * aspectVec;
  // Rescue R3: HEAD's time * (0.15 + mids * 0.2) let audio scale a growing phase (rotation jumped with every mids change).
  // The audio term is now a bounded wobble; identical to HEAD at mids = 0.
  let totalAngle = rotationParam + time * 0.15 + mids * 0.2 * sin(time * 0.7) + rippleRotation + select(0.0, 0.25, held);
  p = rotate2d(p, totalAngle);
  p = p / max(zoomLevel * depthParallax, 0.01);

  // Domain warp for second exposure
  let warpScale = 2.5 + warpStrength * 4.0;
  let wVal = fbm(p * warpScale + vec2<f32>(time * 0.15, -time * 0.1)) * warpStrength * 0.12;
  p += vec2<f32>(cos(time * 0.6 + wVal * 6.28), sin(time * 0.5 + wVal * 6.28)) * wVal;

  p.x = p.x / aspect;
  let uv2 = clamp(p + glide, vec2<f32>(0.0), vec2<f32>(1.0));

  // Sample secondary exposure with chromatic aberration
  let chromaOffset = (warpStrength * 0.008 + length(p) * 0.004) * (1.0 + treble * 0.7 + binA * 0.4);
  let r2 = textureSampleLevel(readTexture, u_sampler, clamp(uv2 + vec2<f32>(chromaOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g2 = textureSampleLevel(readTexture, u_sampler, uv2, 0.0).g;
  let b2 = textureSampleLevel(readTexture, u_sampler, clamp(uv2 - vec2<f32>(chromaOffset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let c2 = vec3<f32>(r2, g2, b2);

  // ── Idea 1: exposure-2 image circle (cos⁴ vignetting) ────────────────
  // Exposure 2 is a lens projection pivoted on the cursor: the optical axis passes through the pivot, focal length
  // f grows with the zoom, and off-axis light falls as cos⁴θ, θ = atan(r / f). cos⁴(atan(r/f)) = (f² / (f² + r²))²
  // exactly, so no trig. Exposure 2 is full strength on the axis and rolls off to 35 % at the frame edge (a "porthole").
  let rAxis = length((uv - glide) * aspectVec);
  let fLen = max(zoomLevel, 0.05) * 0.55;
  let cosT2 = (fLen * fLen) / (fLen * fLen + rAxis * rAxis);
  let ex2 = mix(0.35, 1.0, cosT2 * cosT2);

  // Cellular interference mask modulating exposure interaction
  let voroPattern = sin(uv.x * 14.0 + time) * cos(uv.y * 14.0 - time * 0.8) * 0.5 + 0.5;
  let layerMix = opacity * (0.75 + voroPattern * 0.25) * (1.0 + held_bonus(held));

  // Photographic Screen / Soft-Light exposure blend
  // Exposure 2 enters both blends through its image circle: screen adds less light, overlay's neutral grey is 0.5.
  let c2s = c2 * ex2;
  let c2o = mix(vec3<f32>(0.5), c2, ex2);
  let screenBlend = 1.0 - (1.0 - c1) * (1.0 - c2s * layerMix);
  let overlayBlend = mix(c1 * (c2o * 2.0), 1.0 - 2.0 * (1.0 - c1) * (1.0 - c2o), step(vec3<f32>(0.5), c1));
  var composite = mix(screenBlend, overlayBlend, 0.35);

  // Flash tint at ripple fronts
  let flashColor = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + time * 1.5 + binB * 2.0);
  composite += flashColor * rippleFlash * 0.35;

  // Exact previous frame history load from dataTextureC for ghost trails
  // Rescue R4: C(0,0) holds the glide state, never colour: pixel (0,0) uses the current value as its history.
  let hist = textureLoad(dataTextureC, coord, 0);
  let histRGB = select(hist.rgb, composite, isCorner);
  let feedbackWeight = mix(0.05, 0.25, layerMix);
  var hdr = mix(composite, histRGB, feedbackWeight);

  // ── Idea 2: shutter-open dwell (long exposure while the pointer is held) ──
  // A camera held open integrates light. While the pointer is held the history weight rises toward long-exposure
  // integration (0.25 + 0.75 * 0.78 = 0.83 at most, HEAD's weight on release), so the rotating exposure 2 smears into
  // trails. The extra history is read back to scene-referred light (acesInverse of the ACES-ed C) and EMA-ed in
  // that space, so the held steady state equals HEAD's fixed point (no brightness step at press or release) and
  // only the time constant changes. No new state: it is the exact C this file already loads.
  let histLin = select(acesInverse(hist.rgb), composite, isCorner);
  // C.a >= 0.7 once a frame has been written (semantic alpha), so the first frame after a shader switch has no dwell.
  hdr = mix(hdr, histLin, select(0.0, 0.78, held && hist.a > 0.5));

  let finalRGB = acesToneMap(hdr);
  let luma = dot(finalRGB, vec3<f32>(0.2126, 0.7152, 0.0722));
  let semanticAlpha = clamp(0.70 + luma * 0.25 + rippleFlash * 0.3, 0.0, 1.0);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, coord, outCol);
  // A: display RGBA, except texel (0,0) = glide state (R1). writeTexture keeps the real pixel there.
  textureStore(dataTextureA, coord, select(outCol, vec4<f32>(glide, GLIDE_MARK, fract(time)), isCorner));
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(mix(depth, 0.3 + luma * 0.5, 0.35), 0.0, 1.0), 0.0, 0.0, 0.0));
}

fn held_bonus(h: bool) -> f32 {
  return select(0.0, 0.2, h);
}
