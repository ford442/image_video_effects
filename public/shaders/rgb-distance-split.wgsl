// ═══════════════════════════════════════════════════════════════════
//  RGB Distance Split
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba, spectral-dispersion,
//            diffraction-orders, ACES
//  Ideas:    1. spectral lateral colour — 7 wavelength taps, each pushed along the split
//               axis in proportion to (λ − 550 nm), so the fringe is a rainbow, not 3 copies
//            2. ±1st-order diffraction ghosts — faint grating copies far from the cursor,
//               where red diffracts further than blue (the opposite of a prism)
//  Complexity: Medium
//  Upgraded: 2026-05-23
//
//  Distance-based RGB separation with wavelength-dependent Beer-Lambert alpha.
//  Red (650nm): lowest absorption; Blue (450nm): highest absorption.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══════════════════════════════════════════════════════════════
//  SPECTRAL PHYSICS CONSTANTS
// ═══════════════════════════════════════════════════════════════
const WAVELENGTH_RED:    f32 = 650.0;  // nm
const WAVELENGTH_GREEN:  f32 = 550.0;  // nm
const WAVELENGTH_BLUE:   f32 = 450.0;  // nm

// ═══════════════════════════════════════════════════════════════
//  WAVELENGTH-DEPENDENT ALPHA
// ═══════════════════════════════════════════════════════════════
fn calculateChannelAlpha(thickness: f32, wavelength: f32) -> f32 {
    let lambda_norm = (800.0 - wavelength) / 400.0;
    let absorption = mix(0.3, 1.0, lambda_norm);
    return exp(-thickness * absorption);
}

// Smooth visible-spectrum approximation (400–700 nm).
fn wavelengthRGB(lambda: f32) -> vec3<f32> {
    let x = clamp((lambda - 400.0) / 300.0, 0.0, 1.0);
    let r = smoothstep(0.45, 0.75, x) + smoothstep(0.15, 0.0, x) * 0.1;
    let g = 1.0 - smoothstep(0.0, 0.35, abs(x - 0.5));
    let b = 1.0 - smoothstep(0.1, 0.5, x);
    return vec3<f32>(r, g, b);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) { return; }
  var uv = vec2<f32>(global_id.xy) / resolution;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  var mousePos = u.zoom_config.yz;

  // Bass widens the chromatic split; mids rotate the dispersion angle
  let strength = u.zoom_params.x * 0.1 * (1.0 + bass * 0.5);
  let angleOffset = u.zoom_params.y * 6.28 + mids * 0.5;
  let blur = u.zoom_params.z;
  let deadzone = u.zoom_params.w;

  // Calculate vector from mouse to current pixel
  let aspect = resolution.x / resolution.y;
  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

  // Direction, aspect-corrected like the distance and mapped back to uv.
  var dir = vec2<f32>(0.0, 0.0);
  if (dist > 0.001) {
      dir = normalize(vec2<f32>(dVec.x * aspect, dVec.y)) * vec2<f32>(1.0 / aspect, 1.0);
  }

  // Calculate separation amount based on distance
  let effectFactor = smoothstep(deadzone, 1.0, dist);

  let separation = dir * strength * effectFactor;

  // Rotate separation vector by angleOffset
  let c = cos(angleOffset);
  let s = sin(angleOffset);
  let rotSeparation = vec2<f32>(
      separation.x * c - separation.y * s,
      separation.x * s + separation.y * c
  );

  // Idea 1: spectral lateral colour. Seven wavelengths each take their own
  // offset along the split axis, k = (λ − 550)/100: ±1 at 650/450 nm (HEAD's
  // R and B extremes, ±1.5 at 700/400 nm). Each channel is normalised by its spectral weight, so
  // grey stays grey and the fringe spreads into a rainbow. Blur adds a trailing
  // tap per wavelength.
  let bOffset = rotSeparation * blur * 0.5;
  let doBlur = select(0.0, 1.0, blur > 0.0);
  var spec = vec3<f32>(0.0);
  var wsum = vec3<f32>(0.0);
  for (var i = 0; i < 7; i = i + 1) {
      let lambda = 400.0 + f32(i) * 50.0;
      let k = (lambda - 550.0) / 100.0;
      let tapUV = clamp(uv + rotSeparation * k, vec2<f32>(0.0), vec2<f32>(1.0));
      var c = textureSampleLevel(readTexture, u_sampler, tapUV, 0.0).rgb;
      let cb = textureSampleLevel(readTexture, u_sampler, clamp(tapUV + bOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
      c = mix(c, (c + cb) * 0.5, doBlur);
      let w = wavelengthRGB(lambda);
      spec += c * w;
      wsum += w;
  }
  spec = spec / max(wsum, vec3<f32>(1e-3));
  var r = spec.r;
  var g = spec.g;
  var b = spec.b;

  // Idea 2: ±1st-order diffraction ghosts. Far from the cursor, a grating
  // throws faint copies either side along the split axis. Grating angle grows
  // with wavelength, so red lands furthest out and blue nearest, the reverse of
  // the prism fringe above.
  let gratingD = strength * 2.5 * effectFactor;
  let orderAmp = 0.16 * effectFactor * effectFactor;
  var ghost = vec3<f32>(0.0);
  let lam = vec3<f32>(WAVELENGTH_RED, WAVELENGTH_GREEN, WAVELENGTH_BLUE) / 550.0;
  let gdir = normalize(rotSeparation + vec2<f32>(1e-6));
  for (var o = -1; o <= 1; o = o + 2) {
      let sgn = f32(o);
      ghost.r += textureSampleLevel(readTexture, u_sampler, clamp(uv + gdir * gratingD * lam.r * sgn, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
      ghost.g += textureSampleLevel(readTexture, u_sampler, clamp(uv + gdir * gratingD * lam.g * sgn, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
      ghost.b += textureSampleLevel(readTexture, u_sampler, clamp(uv + gdir * gratingD * lam.b * sgn, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  }
  r += ghost.r * orderAmp;
  g += ghost.g * orderAmp;
  b += ghost.b * orderAmp;

  // ═══════════════════════════════════════════════════════════════
  //  WAVELENGTH-DEPENDENT ALPHA
  //  Thickness derived from separation distance
  // ═══════════════════════════════════════════════════════════════
  let separationLength = length(rotSeparation);
  let dispersionThickness = separationLength * 20.0 + effectFactor * 2.0;
  
  let alphaR = calculateChannelAlpha(dispersionThickness, WAVELENGTH_RED);
  let alphaG = calculateChannelAlpha(dispersionThickness, WAVELENGTH_GREEN);
  let alphaB = calculateChannelAlpha(dispersionThickness, WAVELENGTH_BLUE);
  
  let luminanceWeights = vec3<f32>(0.299, 0.587, 0.114);
  // Beer-Lambert now sets alpha (transmission) and only a light tint on the
  // colour. HEAD multiplied colour by it, leaving the frame at 10-35%.
  let finalAlpha = mix(1.0, dot(vec3<f32>(alphaR, alphaG, alphaB), luminanceWeights), 0.5);
  let tint = mix(vec3<f32>(1.0), vec3<f32>(alphaR, alphaG, alphaB), 0.15);
  let finalColor = aces(vec3<f32>(r, g, b) * tint);

  let finalOut = vec4<f32>(finalColor, clamp(finalAlpha, 0.0, 1.0));
  let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, coord, finalOut);
  textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalOut);
}
