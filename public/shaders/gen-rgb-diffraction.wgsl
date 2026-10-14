// ═══════════════════════════════════════════════════════════════════
//  RGB Diffraction
//  Category: generative
//  Features: audio-reactive, mouse-driven, psychedelic, procedural, temporal, chromatic, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: single-slit diffraction envelope over the multi-slit fringes; blaze-angle steering of principal maxima by mouse; Talbot self-imaging replicas; order-selective grating lobes; hexagonal diffraction grating; zero-order central bright spot
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

  // Add a global hue shimmer
  let shimHue = fract(time * speed * 0.04 + treble * 0.2);
  let shimRgb = hsv2rgb(vec3<f32>(shimHue, 0.4, 1.0));
  color = color + shimRgb * 0.08;

  // Idea 3 — Talbot self-imaging: near-field recurrence bands where fringe
  // packets replicate at periodic radial intervals.
  let talbotPhase = fract(axisRad * (freq * 0.9) - time * speed * 0.08);
  let talbot = exp(-pow((talbotPhase - 0.5) * 8.0, 2.0)) * exp(-axisRad * 1.6);
  color += hsv2rgb(vec3<f32>(fract(shimHue + axisRad * 0.12), 0.75, 1.0)) * talbot * (0.22 + mids * 0.25);

  // Idea 2: Zero-order central bright spot (intense bloom at origin)
  let zeroOrder = exp(-axisRad * 40.0) * 2.5 * (1.0 + bass);
  color += vec3<f32>(1.0, 0.9, 0.8) * zeroOrder;

  // Idea 4 — order-selective grating lobes with rolloff by order index.
  var lobes = 0.0;
  for (var m = 1; m <= 4; m = m + 1) {
    let mf = f32(m);
    let rm = mf * (0.08 + 0.02 * chromAb) * (1.1 + 0.4 / max(freq, 1.0));
    lobes += exp(-pow((axisRad - rm) * 24.0, 2.0)) / (1.0 + mf * 0.8);
  }
  color += hsv2rgb(vec3<f32>(fract(shimHue + 0.27), 0.65, 1.0)) * lobes * (0.18 + treble * 0.22);

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
