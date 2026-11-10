// ═══════════════════════════════════════════════════════════════════
//  Data Scanner Gabor — Batch 67
//  fp128 scan phase, Gabor orientation bank, vertical packet,
//  capped click bursts, held widens bar, ACES + semantic alpha.
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Upgraded: 2026-11-10
//  Ideas: Gabor energy from the quadrature pair, DC-free, one shared tap loop (phase-invariant, no confetti); orientation needles from the four energies (dominant orientation + coherence)
//  A packing: ACES display RGBA (C read as colour at in_scan·0.1) — unchanged
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

struct Fp128 {
  base: f32,
  mant: f32,
}

fn fp128(x: f32) -> Fp128 { return Fp128(x, 0.0); }
fn fp128_sum(a: Fp128, b: Fp128) -> Fp128 {
  let s = a.base + b.base;
  let e = (a.base - s) + b.base + a.mant + b.mant;
  let t = s + e;
  return Fp128(t, e - (t - s));
}
fn fp128_mul(a: Fp128, b: Fp128) -> Fp128 {
  let p = a.base * b.base;
  let e = a.base * b.mant + a.mant * b.base;
  let t = p + e;
  return Fp128(t, e - (t - p));
}
fn fp128_val(x: Fp128) -> f32 { return x.base + x.mant; }

const TAU: f32 = 6.28318530718;
// Tuning constants: ENERGY_GAIN scales
// the amplitude estimate into 0..1; NEEDLE_GAIN is the needle brightness.
const ENERGY_GAIN: f32 = 6.0;
const NEEDLE_GAIN: f32 = 1.0;
const LUMA: vec3<f32> = vec3<f32>(0.299, 0.587, 0.114);

// ── Idea 1: Gabor energy from the quadrature pair ──────────────────────
// HEAD summed only the cosine (even) phase per orientation: a signed value that
// flips with the local stripe phase, so its hue read as confetti. The pair
// (even, odd) gives a phase-invariant energy, and the even kernel is made
// zero-mean so flat bright areas do not leak into the response (the odd kernel
// is antisymmetric, already zero-mean). The four orientations share ONE tap
// loop (HEAD re-fetched the same 169 texels per orientation): the gaussian is
// isotropic, so only the phase differs, advanced per dx by a rotor.
struct Bank {
  even: vec4<f32>,   // DC-removed cosine-phase response, orientations 0..3
  odd: vec4<f32>,    // sine-phase response
  wsum: f32,         // kernel weight sum (amplitude normaliser)
}

fn gaborBank(pixel: vec2<i32>, maxP: vec2<i32>, rot: f32, freq: f32, sigma: f32) -> Bank {
  let maxRadius = min(i32(ceil(sigma * 3.0)), 6);
  let ang = vec4<f32>(0.0, 0.785398, 1.570796, 2.356194) + vec4<f32>(rot);
  let ct = cos(ang);
  let st = sin(ang);
  let kk = TAU * freq;
  let stepAng = kk * ct;
  let rc = cos(stepAng);
  let rs = sin(stepAng);
  let inv2s = 1.0 / (2.0 * sigma * sigma + 0.001);
  var re = vec4<f32>(0.0);
  var im = vec4<f32>(0.0);
  var sWC = vec4<f32>(0.0);
  var sW = 0.0;
  var sWL = 0.0;
  for (var dy = -maxRadius; dy <= maxRadius; dy++) {
    let ph0 = kk * (st * f32(dy) - ct * f32(maxRadius));
    var c = cos(ph0);
    var s = sin(ph0);
    for (var dx = -maxRadius; dx <= maxRadius; dx++) {
      let g = exp(-f32(dx * dx + dy * dy) * inv2s);
      let luma = dot(textureLoad(readTexture, clamp(pixel + vec2<i32>(dx, dy), vec2<i32>(0), maxP), 0).rgb, LUMA);
      let wl = g * luma;
      re += wl * c;
      im += wl * s;
      sWC += g * c;
      sW += g;
      sWL += wl;
      let cn = c * rc - s * rs;
      s = s * rc + c * rs;
      c = cn;
    }
  }
  let dc = sWC / max(sW, 1e-4);
  return Bank(re - dc * sWL, im, sW);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(gid.xy);
  let maxP = vec2<i32>(resolution) - vec2<i32>(1);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let time = u.config.x;
  let held = u.zoom_config.w > 0.5;
  let aspect = resolution.x / resolution.y;

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let freq = mix(0.05, 0.3, u.zoom_params.x);
  let sigma = mix(1.5, 4.0, u.zoom_params.y);
  let responseScale = mix(0.5, 3.0, u.zoom_params.z);
  let scanWidth = mix(0.05, 0.25, u.zoom_params.w) * select(1.0, 1.35, held);

  let mouse = u.zoom_config.yz;
  let scanPhase = fp128_sum(fp128(mouse.x), fp128_mul(fp128(sin(time * (1.5 + bass))), fp128(0.015 * mids)));
  let scan_x = fp128_val(scanPhase);
  let dist = abs(uv.x - scan_x);
  let in_scan = smoothstep(scanWidth, scanWidth - 0.01, dist);

  let packet = pow(max(0.0, 1.0 - abs(uv.y - fract(time * (1.0 + bass * 2.0))) * 16.0), 5.0);

  // The photo outside the bar is dimmed to 0.4. The dim is applied as a continuous
  // function of in_scan (HEAD dimmed only where in_scan == 0, so the bar's soft edge
  // started from the UNDIMMED photo and showed up as a bright seam).
  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb * mix(0.4, 1.0, in_scan);

  if (in_scan > 0.0) {
    let rot = time * 0.12 + mids * 0.4;
    let bank = gaborBank(pixel, maxP, rot, freq, sigma);
    let angles = vec4<f32>(0.0, 0.785398, 1.570796, 2.356194) + vec4<f32>(rot);

    // ── Idea 1: Gabor energy (quadrature) ─────────────────────────────
    // amplitude of the local stripe in luma units, soft-saturated; Gabor Response
    // keeps its role as the gain. Hue = orientation (the four HEAD palettes), a small
    // phase wobble keeps the stripes readable; brightness = energy.
    let energy = sqrt(bank.even * bank.even + bank.odd * bank.odd);
    let amp = 2.0 * energy / max(bank.wsum, 1e-3);
    let E = vec4<f32>(1.0) - exp(-amp * responseScale * ENERGY_GAIN);
    let wob = bank.even / (energy + vec4<f32>(1e-4));
    let pal = vec3<f32>(0.5);
    // HEAD's four palette offsets coincide at a fixed index (0° and 135° are both cyan),
    // so each orientation gets its own index offset: cyan / orange / violet / lime.
    let tOff = vec4<f32>(0.0, 0.15, 0.05, 0.75);
    var analyzed = palette(0.5 + tOff.x + 0.10 * wob.x, pal, pal, vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67)) * E.x;
    analyzed += palette(0.5 + tOff.y + 0.10 * wob.y, pal, pal, vec3<f32>(1.0), vec3<f32>(0.33, 0.67, 0.0)) * E.y;
    analyzed += palette(0.5 + tOff.z + 0.10 * wob.z, pal, pal, vec3<f32>(1.0), vec3<f32>(0.67, 0.0, 0.33)) * E.z;
    analyzed += palette(0.5 + tOff.w + 0.10 * wob.w, pal, pal, vec3<f32>(1.0), vec3<f32>(0.0, 0.67, 0.33)) * E.w;
    let sumE = E.x + E.y + E.z + E.w;
    analyzed = analyzed * 1.3 / (1.0 + 0.6 * sumE) + color * 0.18;

    let grid = step(0.95, fract(uv * 40.0).x) + step(0.95, fract(uv * 40.0).y);
    analyzed = max(analyzed, vec3<f32>(0.0, 0.5, 0.0) * grid);

    // ── Idea 2: orientation needles ───────────────────────────────────
    // The four energies are an orientation field HEAD threw away. Doubled-angle sum
    // gives the dominant stripe orientation and its coherence; every 1/40 grid cell
    // gets a short tick along the stripe tangent, drawn by the pixels whose offset from
    // the cell centre is parallel to their own orientation. Length scales with coherence.
    let V = vec2<f32>(dot(E, cos(2.0 * angles)), dot(E, sin(2.0 * angles)));
    let thetaStar = 0.5 * atan2(V.y, V.x);                       // wave-vector direction (dx, dy)
    let coh = length(V) / max(sumE, 1e-3);
    let tang = vec2<f32>(-sin(thetaStar), cos(thetaStar));       // along the stripe
    let norm = vec2<f32>(cos(thetaStar), sin(thetaStar));
    let cellPx = resolution / 40.0;
    let offPx = (fract(uv * 40.0) - vec2<f32>(0.5)) * cellPx;
    let along = dot(offPx, tang);
    let across = dot(offPx, norm);
    let cellMin = min(cellPx.x, cellPx.y);
    let halfLen = 0.46 * cellMin * mix(0.45, 1.0, coh);
    let halfW = max(0.8, 0.09 * cellMin);
    let tick = (1.0 - smoothstep(halfW - 0.5, halfW + 0.5, abs(across))) * (1.0 - smoothstep(halfLen * 0.75, halfLen, abs(along)));
    let needle = tick * smoothstep(0.18, 0.45, coh) * smoothstep(0.08, 0.30, sumE) * NEEDLE_GAIN;
    let needleCol = (vec3<f32>(0.5) + vec3<f32>(0.5) * cos(TAU * (vec3<f32>(thetaStar / 3.14159265) + vec3<f32>(0.0, 0.33, 0.67)))) * 1.4 + vec3<f32>(0.25);
    analyzed = analyzed + needleCol * needle;

    let border = smoothstep(scanWidth - 0.005, scanWidth, dist) * (1.0 - smoothstep(scanWidth, scanWidth + 0.005, dist));
    analyzed += vec3<f32>(1.0) * border * (4.0 + treble);
    analyzed += vec3<f32>(0.2, 0.95, 0.85) * packet * 0.35;

    color = mix(color, analyzed, in_scan * 0.9);
  }

  var clickBurst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.3) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      clickBurst += smoothstep(0.025, 0.0, abs(rDist - age * 0.36)) * exp(-age * 1.7);
    }
  }
  color += vec3<f32>(0.35, 1.0, 0.9) * clickBurst * 0.3;

  let prev = textureLoad(dataTextureC, pixel, 0);
  color = mix(color, prev.rgb * 0.88, in_scan * 0.1);

  // Eight bands across the bar, read from the three audio bands (plasmaBuffer is one
  // vec4; HEAD indexed [band + 1], out of range): low third bass, mid mids, high treble.
  let band = min(u32(uv.x * 8.0), 7u);
  let bandAudio = select(select(treble, mids, band < 5u), bass, band < 2u);
  color += vec3<f32>(0.03, 0.08, 0.12) * bandAudio * in_scan * 0.12;

  color = acesToneMap(max(color, vec3<f32>(0.0)));
  let lum = dot(color, LUMA);
  let alpha = clamp(mix(0.35 + lum * 0.3, 0.95, in_scan) + clickBurst * 0.1 + packet * 0.08, 0.06, 0.98);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
