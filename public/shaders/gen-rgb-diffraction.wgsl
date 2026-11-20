// ═══════════════════════════════════════════════════════════════════
//  RGB Diffraction
//  Category: generative
//  Features: audio-reactive, mouse-driven, psychedelic, procedural, temporal, chromatic, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10, 2026-11-20
//  Ideas: single-slit diffraction envelope over the multi-slit fringes; blaze-angle steering of principal maxima by mouse; Talbot self-imaging replicas; order-selective grating lobes; hexagonal diffraction grating; zero-order central bright spot; chromatic Airy rings around the zero-order spot (§12.2F Airy disc); order-dependent spectral dispersion of the grating lobes (grating equation m·λ = d·sinθ, §12.2F)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  Simulates a diffraction grating: multiple virtual slits produce
//  sinusoidal interference fringes whose spatial frequency, tilt
//  and phase are modulated by audio. Separate red/green/blue path
//  lengths create vivid spectral splitting. Rotational symmetry
//  applied 6-fold produces a kaleidoscopic star burst.

#include "_prelude.wgsl"

const TAU: f32 = 6.283185307179586;
const SLITS: i32 = 6;
const SYMMETRY: i32 = 6;

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Bessel J1 (Abramowitz & Stegun 9.4.4 for x<=3, 9.4.6 above), |err| < 4e-8 on 0..16.
// The 4-term power series is only good to x~3; the Airy rings below need x up to ~14.
fn besselJ1(x: f32) -> f32 {
  let xs = max(abs(x), 1e-3);
  let t = (xs / 3.0) * (xs / 3.0);
  let jLo = xs * (0.5 + t * (-0.56249985 + t * (0.21093573 + t * (-0.03954289 + t * (0.00443319 + t * (-0.00031761 + t * 0.00001109))))));
  let xh = max(xs, 3.0);
  let u = 3.0 / xh;
  let f1 = 0.79788456 + u * (0.00000156 + u * (0.01659667 + u * (0.00017105 + u * (-0.00249511 + u * (0.00113653 - u * 0.00020033)))));
  let th = xh - 2.35619449 + u * (0.12499612 + u * (0.00005650 + u * (-0.00637879 + u * (0.00074348 + u * (0.00079824 - u * 0.00029166)))));
  let jHi = f1 * cos(th) * inverseSqrt(xh);
  return select(jHi, jLo, xs <= 3.0);
}

// Airy field amplitude |2 J1(x)/x| of a circular aperture (1 at x=0, first zero 3.8317).
fn airyAmp(x: f32) -> f32 {
  let xs = max(abs(x), 1e-3);
  return abs(2.0 * besselJ1(xs) / xs);
}

// Apply k-fold rotational symmetry to a 2D point
fn applySymmetry(q: vec2<f32>, k: i32) -> vec2<f32> {
  let sectors = f32(k);
  let angle   = atan2(q.y, q.x);
  let r       = length(q);
  let secAngle = TAU / sectors;
  let sector   = floor(angle / secAngle);
  let localA   = angle - sector * secAngle;
  // Mirror alternate sectors
  let foldA = select(localA, secAngle - localA, localA > secAngle * 0.5);
  return vec2<f32>(cos(foldA), sin(foldA)) * r;
}

// Diffraction from a single slit at position slitPos on axis axisDir
fn slitIntensity(p: vec2<f32>, slitPos: f32, axisDir: vec2<f32>, freq: f32, phase: f32, lambda: f32) -> f32 {
  let proj   = dot(p, axisDir) - slitPos;
  let wave   = 0.5 + 0.5 * cos(proj * freq * TAU + phase);
  // Envelope: sinc-like falloff from slit center
  let dist   = abs(dot(p, vec2<f32>(-axisDir.y, axisDir.x)));
  let envArg = dist * freq * 0.5 * lambda;
  let sinc   = select(1.0, sin(envArg) / envArg, abs(envArg) > 0.001);
  return wave * sinc * sinc;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res    = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coord  = vec2<i32>(global_id.xy);
  let uv     = vec2<f32>(global_id.xy) / res;
  let time   = u.config.x;
  let aspect = res.x / max(res.y, 1.0);
  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let speed    = mix(0.2,  2.5, u.zoom_params.x);
  let freq     = mix(4.0, 22.0, u.zoom_params.y);
  let chromAb  = mix(0.8,  2.2, u.zoom_params.z); // wavelength spread
  let brightness = mix(0.6, 2.0, u.zoom_params.w);

  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
  p = applySymmetry(p, SYMMETRY);
  let radClean = length(p); // aperture-clean radius (before the hex grating mask jitters it)
  
  // Idea 1: hexagonal diffraction grating mask
  let hexMask = 0.8 + 0.2 * sin(p.x * 50.0) * sin((p.x * 0.5 + p.y * 0.866) * 50.0) * sin((p.x * 0.5 - p.y * 0.866) * 50.0);
  p *= hexMask;

  // Wavelengths for R G B (relative)
  let lambdaR = 1.0 * chromAb;
  let lambdaG = 0.82 * chromAb;
  let lambdaB = 0.68 * chromAb;

  var r = 0.0;
  var g = 0.0;
  var b = 0.0;

  // Chromatic offsets modulated by audio bands
  let chromOffsetR = vec2<f32>(bass * 0.02, 0.0);
  let chromOffsetG = vec2<f32>(0.0, mids * 0.02);
  let chromOffsetB = vec2<f32>(-treble * 0.02, treble * 0.02);

  // Idea 2 — blaze-angle steering: a phase ramp across the aperture steers the
  // principal maxima off-axis, exactly like a blazed grating. The ramp vector
  // follows the pointer so dragging sweeps the burst sideways.
  let mouseUv = u.zoom_config.yz;
  let blazeVec = (mouseUv - vec2<f32>(0.5)) * TAU * 0.5;
  let blazePhase = dot(p, blazeVec);

  for (var si: i32 = 0; si < SLITS; si = si + 1) {
    let sf      = f32(si);
    let slitAngle = sf / f32(SLITS) * TAU + time * speed * 0.05;
    let axis    = vec2<f32>(cos(slitAngle), sin(slitAngle));
    let slitPos = (sf - f32(SLITS) * 0.5) * 0.18;
    let phase   = time * speed * (0.6 + sf * 0.23) + bass * TAU * 0.4 + blazePhase;

    r = r + slitIntensity(p + chromOffsetR, slitPos, axis, freq * lambdaR, phase, lambdaR);
    g = g + slitIntensity(p + chromOffsetG, slitPos, axis, freq * lambdaG, phase + 0.3, lambdaG);
    b = b + slitIntensity(p + chromOffsetB, slitPos, axis, freq * lambdaB, phase + 0.6, lambdaB);
  }

  // Normalize and boost
  let norm    = 1.0 / max(f32(SLITS) * 0.6, 1.0);
  var color   = vec3<f32>(r, g, b) * norm * brightness * (1.0 + mids * 0.4);

  // Idea 1 — single-slit diffraction envelope: in a real grating the fine
  // multi-slit fringes sit inside one broad sinc envelope centered on the
  // optical axis. Multiplying by it gives the burst a physical center-to-edge
  // falloff instead of uniform fringe energy to the corners.
  let axisRad = length(p);
  let envArg = axisRad * freq * 0.10;
  let envSinc = select(1.0, sin(envArg) / envArg, abs(envArg) > 0.001);
  color = color * (envSinc * envSinc);

  // Wavelength ratios shared by the two chromatic ideas (5 and 6). R sits at λR/λG, B at λB/λG;
  // chromatic_spread (chromAb) widens how far R and B depart from green, so the slider keeps
  // its role of "wavelength spread".
  let spreadK = mix(0.5, 1.6, clamp((chromAb - 0.8) / 1.4, 0.0, 1.0));
  let lamRel = vec3<f32>(1.0 + (lambdaR / lambdaG - 1.0) * spreadK, 1.0, 1.0 + (lambdaB / lambdaG - 1.0) * spreadK);

  // ── Idea 5: chromatic Airy rings (§12.2F Airy disc). The beam leaves a circular aperture, so
  // the field carries its Airy pattern; ring radius scales with λ, so red rings sit outside green
  // outside blue. Multiplicative half (here): the dark rings (zeros at x = 3.83, 7.02, 10.17)
  // dim each channel's fringes at its own radius, coloured gaps that fade with radius. The
  // central lobe is untouched. Amplitude |2J1(x)/x| is used (not its square) because that is the
  // compressive response a saturated exposure shows; intensity rings (1.75 %, 0.4 %) would vanish.
  var airyRGB = vec3<f32>(0.0);
  if (radClean < 1.1) {
    let airyX = radClean * (3.8317059 / 0.085) / lamRel;
    let amp = vec3<f32>(airyAmp(airyX.x), airyAmp(airyX.y), airyAmp(airyX.z));
    let ringDepth = 0.6 * exp(-radClean * 4.0);
    color = color * mix(vec3<f32>(1.0 - ringDepth), vec3<f32>(1.0), clamp(amp * 7.5, vec3<f32>(0.0), vec3<f32>(1.0)));
    // additive half (applied at the zero-order spot below): rings start at the first dark ring,
    // where the amplitude is 0, so there is no seam with the HEAD central spot.
    airyRGB = amp * step(vec3<f32>(3.8317059), airyX);
  }

  // Add a global hue shimmer
  let shimHue = fract(time * speed * 0.04 + treble * 0.2);
  let shimRgb = hsv2rgb(vec3<f32>(shimHue, 0.4, 1.0));
  color = color + shimRgb * 0.08;

  // Idea 3 — Talbot self-imaging: near-field recurrence bands where fringe
  // packets replicate at periodic radial intervals.
  let talbotPhase = fract(axisRad * (freq * 0.9) - time * speed * 0.08);
  let talbotZ = (talbotPhase - 0.5) * 8.0; // rescue: squared directly, pow(negative, 2.0) is undefined
  let talbot = exp(-talbotZ * talbotZ) * exp(-axisRad * 1.6);
  color += hsv2rgb(vec3<f32>(fract(shimHue + axisRad * 0.12), 0.75, 1.0)) * talbot * (0.22 + mids * 0.25);

  // Idea 2: Zero-order central bright spot (intense bloom at origin)
  let zeroOrder = exp(-axisRad * 40.0) * 2.5 * (1.0 + bass);
  color += vec3<f32>(1.0, 0.9, 0.8) * zeroOrder;

  // ── Idea 5 (additive half): the bright Airy rings ride on the zero-order spot. airyRGB was
  // computed with the aperture envelope above; it scales with the brightness (exposure) slider.
  color += airyRGB * exp(-radClean * 3.0) * 2.0 * brightness * (1.0 + bass * 0.8);

  // Idea 4 — order-selective grating lobes with rolloff by order index.
  // ── Idea 6: order-dependent spectral dispersion. Grating equation m·λ = d·sinθ: order m of
  // wavelength λ lands at radius ∝ m·λ, so R/G/B lobes split by an amount that grows with m and
  // neighbouring orders overlap (m=3 red meets m=4 blue). The HEAD tinted lobe is the green
  // (reference-wavelength) order and is kept verbatim; R and B are the same lobe at rm·λR/λG and
  // rm·λB/λG, added as the order's red outer and blue inner edges.
  var lobes = vec3<f32>(0.0);
  for (var m = 1; m <= 4; m = m + 1) {
    let mf = f32(m);
    let rm = mf * (0.08 + 0.02 * chromAb) * (1.1 + 0.4 / max(freq, 1.0));
    let dl = (vec3<f32>(axisRad) - rm * lamRel) * 24.0; // rescue: explicit square, no pow(negative, 2.0)
    lobes += exp(-dl * dl) / (1.0 + mf * 0.8);
  }
  color += hsv2rgb(vec3<f32>(fract(shimHue + 0.27), 0.65, 1.0)) * lobes.y * (0.18 + treble * 0.22);
  color += vec3<f32>(lobes.x, 0.0, lobes.z) * (0.30 + treble * 0.30);

  // Vignette
  let vign  = 1.0 - smoothstep(0.6, 1.2, length(p * 0.5));
  color = color * vign;
  color = acesToneMap(color);

  // ═══ Temporal feedback (exact load: C is rgba32float history) ═══
  let prev = textureLoad(dataTextureC, coord, 0);
  color = mix(color, prev.rgb * 0.9, 0.03 + bass * 0.01);

  let depth = clamp((r + g + b) * norm * 0.4, 0.0, 1.0);
  let alpha = clamp(length(color) * 0.6, 0.0, 1.0);

  textureStore(writeTexture,      coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, vec4<f32>(color, alpha));
}
