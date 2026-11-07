// ═══════════════════════════════════════════════════════════════════
//  Quasicrystal Iridescence
//  Category: advanced-hybrid
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Very High
//  Created: 2026-04-18
//  Upgraded: 2026-09-15, 2026-11-01
//  Ideas: phason strain along k-perp; Ammann lattice lines from the n-fold sum; gravity drainage of the film (thin top, thick bottom); black-film fade below ~140 nm. REPAIR: the thin-film mix weight was <= 0.0017 at HEAD (film invisible); now a 25 % base layer rising to 85 % at the edge
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  Penrose tiling-inspired patterns with 5-fold symmetry enhanced by
//  thin-film iridescence. Quasicrystal depth drives film thickness,
//  producing soap-bubble spectral colors across the aperiodic tiling.

#include "_prelude.wgsl"
// zoom_params: x=Symmetry, y=Pattern Density, z=Color Cycle, w=Projection Angle

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Idea 1 — phason: offset each wavevector along its perpendicular.
fn quasicrystal(uv: vec2<f32>, n: i32, t: f32, angle: f32, phason: f32) -> f32 {
  var value = 0.0;
  let pi = 3.14159265359;
  for (var i: i32 = 0; i < n; i++) {
    let theta = angle + pi * 2.0 * f32(i) / f32(n);
    let k = vec2<f32>(cos(theta), sin(theta));
    let kPerp = vec2<f32>(-k.y, k.x);
    let q = uv + kPerp * phason * (f32(i) - f32(n) * 0.5);
    value += cos(dot(q, k) * 10.0 + t);
  }
  return value / f32(n);
}

fn rot2(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
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
  for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 20.0) {
    let phase = opd / lambda;
    // 2026-11 Idea 2: black film. Below ~lambda/4 the two reflections cancel, so a film thinner than ~140 nm
    // goes dark (smoothstep 40 -> 140 nm) instead of staying bright as HEAD's cos^2 does at zero thickness.
    let interference = (cos(phase * 6.28318530718) * 0.5 + 0.5) * smoothstep(40.0, 140.0, thicknessNm);
    color += wavelengthToRGB(lambda) * interference;
    sampleCount = sampleCount + 1.0;
  }
  return color / max(sampleCount, 1.0);
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let t = u.config.x;
  let coord = vec2<i32>(global_id.xy);

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let symmetry = i32(mix(5.0, 13.0, u.zoom_params.x));
  let patternDensity = mix(3.0, 15.0, u.zoom_params.y);
  let colorCycle = u.zoom_params.z;
  let projAngle = mix(0.0, 6.28318, u.zoom_params.w);

  let aspect = resolution.x / max(resolution.y, 1.0);
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * patternDensity;
  p = rot2(t * 0.05 + projAngle) * p;

  let phason = 0.08 * sin(t * 0.17 + mids * 1.4);
  let qc = quasicrystal(p, symmetry, t * 0.2, projAngle, phason);
  let threshold = 0.2;
  let pattern = smoothstep(-threshold, threshold, qc);

  let qc2 = quasicrystal(p * 1.5 + 0.5, symmetry, t * 0.15, projAngle + 0.1, phason * 0.7);
  let pattern2 = smoothstep(-threshold * 0.5, threshold * 0.5, qc2);

  // HEAD dual-maps the same sliders onto film (keep verbatim).
  let filmThicknessBase = mix(200.0, 800.0, u.zoom_params.x) * (1.0 + bass * 0.25);
  let filmIOR = mix(1.2, 2.4, u.zoom_params.y);
  let intensity = mix(0.3, 1.5, u.zoom_params.z);
  let turbulence = mix(0.0, 1.0, u.zoom_params.w);

  let toCenter = uv - vec2<f32>(0.5);
  let dist = length(toCenter);
  let cosTheta = sqrt(max(1.0 - dist * dist * 0.5, 0.01));

  let noiseVal = hash12(uv * 12.0 + t * 0.1) * 0.5 + hash12(uv * 25.0 - t * 0.15) * 0.25;

  let depth = pattern * 0.5 + pattern2 * 0.3;
  // 2026-11 Idea 1: gravity drainage. A soap film drains, so it is thin at the top and thick at the bottom
  // (uv.y = 0 is the top of the frame): thickness x mix(0.72, 1.28, uv.y).
  var thickness = filmThicknessBase * (0.7 + depth * 0.6 + noiseVal * turbulence) * mix(0.72, 1.28, uv.y);

  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;
  let mouseDist = length(uv - mousePos);
  let mouseInfluence = exp(-mouseDist * mouseDist * 800.0) * select(0.0, 1.0, isMouseDown);
  thickness += mouseInfluence * 300.0 * sin(t * 3.0 + mouseDist * 30.0);

  let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * intensity;

  // Repair (floor): HEAD mixed the film in with weight fresnel * 0.7 where fresnel = (1 - cosTheta)^3 and cosTheta =
  // sqrt(1 - dist^2 / 2) never drops below 0.87, so the weight was at most 0.0017 across the frame: the thin-film
  // colour this shader is named for was invisible (and so would be the two ideas below). The viewing angle now
  // reaches grazing at the frame edge (cos = sqrt(1 - 2 dist^2)), and the film is a 25 % base layer rising toward
  // the edge (max 0.85). cosTheta for the film's optical path difference is unchanged.
  let cosThetaWide = sqrt(max(1.0 - dist * dist * 2.0, 0.02));
  let fresnel = pow(1.0 - cosThetaWide, 3.0);
  let filmWeight = clamp(0.25 + 0.55 * fresnel, 0.0, 0.85);

  let m = fract(qc + qc2 + t * colorCycle * 0.05);
  let gold = vec3<f32>(1.0, 0.84, 0.0);
  let silver = vec3<f32>(0.75, 0.75, 0.75);
  let bronze = vec3<f32>(0.8, 0.5, 0.2);
  var baseCol = mix(gold, silver, clamp(m * 3.0, 0.0, 1.0));
  baseCol = mix(baseCol, mix(silver, bronze, clamp((m - 0.33) * 3.0, 0.0, 1.0)), step(0.33, m));
  baseCol = mix(baseCol, mix(bronze, gold, clamp((m - 0.66) * 3.0, 0.0, 1.0)), step(0.66, m));

  let edge = abs(qc);
  let edgeMask = smoothstep(0.05, 0.0, edge);
  baseCol = baseCol + vec3<f32>(1.0, 0.95, 0.8) * edgeMask * 0.4;

  var outColor = mix(baseCol, iridescent, filmWeight);

  // Idea 2 — Ammann lattice lines perpendicular to each k.
  var ammann = 0.0;
  let pi = 3.14159265359;
  for (var i: i32 = 0; i < symmetry; i++) {
    let theta = projAngle + pi * 2.0 * f32(i) / f32(symmetry);
    let k = vec2<f32>(cos(theta), sin(theta));
    let stripes = abs(fract(dot(p, k) * 2.4 + phason * 0.5) - 0.5);
    ammann += smoothstep(0.07, 0.0, stripes);
  }
  ammann = ammann / max(f32(symmetry), 1.0);
  outColor = outColor + vec3<f32>(1.0, 0.96, 0.82) * ammann * (0.12 + treble * 0.18);

  let shimmer = sin(p.x * 20.0 + t) * sin(p.y * 20.0 + t * 1.3);
  outColor = outColor + vec3<f32>(0.1) * shimmer * 0.05;

  let mapped = acesToneMap(outColor * (1.05 + bass * 0.08));
  let vignette = 1.0 - length(uv - 0.5) * 0.5;
  let finalRGB = mapped * vignette;
  let alpha = clamp(edgeMask * 0.45 + fresnel * 0.35 + ammann * 0.2 + depth * 0.15, 0.05, 1.0);
  let outCol = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, outCol);
}
