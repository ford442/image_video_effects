// ═══════════════════════════════════════════════════════════════════
//  String Theory - Vibrating string visualizations with harmonics
//  Category: generative
//  Features: procedural, wave equation, interference patterns,
//    chromatic-aberration, audio-reactive, temporal-feedback, depth-aware, upgraded-rgba
//  Created: 2026-03-22
//  Updated: 2026-08-03 (Batch 34)
//  Upgraded: 2026-09-27, 2026-11-08
//  Ideas: stiff-string inharmonicity on the partials; bridge reflection of the pluck; Melde long-exposure envelope with arcsine dwell (sum of standing-partial amplitudes); fretting finger (held pointer pins a node, each side rings as a shorter string)
//  A packing: ACES display RGBA; texels (0,0) = sprung cursor (pos.xy, vel.xy) and (1,0) = (fract(lastTime), -, -, 0.7371 sentinel) are STATE, not pixels
//  2026-11-08 rescue: the sprung cursor lived in extraBuffer[133..138], which the host zeroes every
//    frame, so the "sprung" pluck was the raw pointer; it now persists in two A texels.
//  By: Agent 4A
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const SENT: f32 = 0.7371;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Evaluate all strings at a given position, returning color + total intensity in alpha
fn evalStrings(p: vec2<f32>, t: f32, fundamental: f32, harmonicRichness: i32, damping: f32, excitement: f32, bass: f32, aspect: f32, depth: f32, mouse: vec2<f32>, pressed: f32) -> vec4<f32> {
  var col = vec3<f32>(0.0);
  var totalIntensity = 0.0;
  for (var s: i32 = 0; s < 5; s++) {
    let angle = f32(s) * 0.314 + t * 0.02;
    let cA = cos(angle);
    let sA = sin(angle);
    let sc = vec2<f32>(aspect * 0.5, 0.5 + f32(s - 2) * 0.15);
    let local = p - sc;
    let sX = local.x * cA + local.y * sA;
    let sY = -local.x * sA + local.y * cA;
    let mouseOffset = mouse - sc;
    let mouseX = mouseOffset.x * cA + mouseOffset.y * sA;
    let mouseY = -mouseOffset.x * sA + mouseOffset.y * cA;
    let inStr = step(abs(sX), 1.5);
    let x = (sX + 1.5) / 3.0;
    var y = 0.0;
    var env = 0.0;
    var sCol = vec3<f32>(0.0);
    // ── Idea 4: fretting finger ──────────────────────────────────────
    // A held pointer on the string stops it: a node is pinned at the finger and
    // each side rings as its own, shorter string (spatial pattern re-fitted to
    // the segment, so its spatial pitch rises by the length ratio; the time phase is
    // left alone - scaling absolute time by a pointer-dependent factor re-phases
    // every partial as the finger drags).
    let fretW = pressed * exp(-abs(mouseY) * 10.0) * step(abs(mouseX), 1.5);
    let xf = clamp((mouseX + 1.5) / 3.0, 0.1, 0.9);
    let rightSide = x > xf;
    let xSeg = select(x / xf, (x - xf) / (1.0 - xf), rightSide);
    let xS = mix(x, xSeg, fretW);
    let pinFret = mix(1.0, sqrt(smoothstep(0.0, 0.03, abs(x - xf))), fretW);
    for (var h: i32 = 1; h <= harmonicRichness; h++) {
      let n = f32(h);
      let amp = 0.1 * (1.0 + bass * excitement) / n;
      let damp = pow(damping, n);
      // Idea 1 — stiff-string inharmonicity. Richness sharpens the upper partials.
      let stiffB = 0.004 * f32(harmonicRichness) / 10.0;
      let inharm = sqrt(1.0 + stiffB * n * n);
      let k = fundamental * n * inharm * 6.28318;
      let w = fundamental * n * inharm * 3.14159;
      y += 2.0 * amp * damp * sin(k * xS) * cos(w * t) * pinFret;
      // ── Idea 3: Melde envelope — power of this standing partial at x (root-sum-square below)
      let partialAmp = 2.0 * amp * damp * sin(k * xS) * pinFret;
      env += partialAmp * partialAmp;
      let hue = fract(n * 0.15 + t * 0.05);
      let c = 0.48;
      let hx = c * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
      let m = 0.36;
      let hi = clamp(i32(hue * 6.0), 0, 5);
      let rgb_table = array<vec3<f32>, 6>(
        vec3<f32>(c, hx, 0.0), vec3<f32>(hx, c, 0.0), vec3<f32>(0.0, c, hx),
        vec3<f32>(0.0, hx, c), vec3<f32>(hx, 0.0, c), vec3<f32>(c, 0.0, hx)
      );
      sCol += (rgb_table[hi] + vec3<f32>(m)) / n;
    }
    let travelAmp = 0.05 * excitement * (1.0 + bass * 2.0);
    y += travelAmp * sin(x * fundamental * 12.56636 - t * fundamental * 12.56636);
    let pluckProfile = exp(-abs(sX - mouseX) * 8.0);
    y += pluckProfile * clamp(mouseY, -0.3, 0.3) * excitement * mix(0.2, 0.75, pressed);
    // Idea 2 — bridge reflection. The pluck image travels back from the far end.
    let bridge = 1.5;
    let mirrored = 2.0 * bridge - mouseX;
    let travel = fract(t * max(fundamental, 0.001) * 0.35);
    let bounceX = mix(mouseX, mirrored, travel);
    y += exp(-abs(sX - bounceX) * 8.0) * clamp(mouseY, -0.3, 0.3) * excitement * mix(0.12, 0.4, pressed) * (1.0 - travel);
    env += travelAmp * travelAmp;
    let dist = abs(sY - y);
    let thick = (0.003 + 0.002 * excitement) * (0.6 + 0.4 * depth);
    let intensity = smoothstep(thick * 3.0, 0.0, dist);
    let core = smoothstep(thick, 0.0, dist);
    let glowFalloff = 50.0 * (0.4 + 0.6 * depth);
    let glow = exp(-dist * glowFalloff) * 0.3;
    // ── Idea 3: Melde long-exposure envelope with arcsine dwell ─────────
    // A long exposure of a vibrating string is a lens-shaped ghost whose edges
    // are brightest (a sinusoid dwells at its turning points: density ~ 1/sqrt(E^2 - y^2)).
    // E(x) is the root-sum-square of the standing-partial amplitudes already computed above
    // (independent partials swing ~sqrt(sum a^2), not the sum of peaks).
    let envE = max(sqrt(env) * 1.15, 0.004);
    let qy = sY / envE;
    let inside = 1.0 - smoothstep(0.9, 1.0, abs(qy));
    let dwell = inverseSqrt(max(1.0 - qy * qy, 0.12));
    let ghost = inside * dwell * 0.022 * smoothstep(0.0, 0.03, envE);
    col += (sCol * (intensity + glow) + vec3<f32>(1.0) * core * 0.5 + sCol * ghost) * inStr;
    totalIntensity += intensity * inStr;
    col += sCol * (sin(dist * 200.0 + t * 2.0) * 0.5 + 0.5) * intensity * 0.2 * inStr;
  }
  return vec4<f32>(col, totalIntensity);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = textureDimensions(writeTexture);
  if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }
  let pixel = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(dims);
  let uv = (vec2<f32>(pixel) + vec2<f32>(0.5)) / resolution;
  let t = u.config.x;
  let fundamental = mix(0.5, 3.0, u.zoom_params.x);
  let harmonicRichness = i32(mix(1.0, 10.0, u.zoom_params.y));
  let damping = mix(0.8, 0.99, u.zoom_params.z);
  let excitement = u.zoom_params.w;
  let bass = plasmaBuffer[0].x;
  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  var prev = textureLoad(dataTextureC, pixel, 0).rgb;
  prev = select(prev, vec3<f32>(0.0), (global_id.y == 0u) && (global_id.x < 2u));   // state texels carry no trail
  let aspect = resolution.x / resolution.y;

  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  // Sprung cursor state lives in two A texels (see header); sentinel guards the first frame / inherited C.
  let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
  let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
  let stateOk = abs(st1.w - SENT) < 0.001;
  var mouseUv = select(rawMouse, st0.xy, stateOk);
  var mouseVelocity = select(vec2<f32>(0.0), st0.zw, stateOk);
  // lastTime is stored as fract(t): A is rgba16float on the balanced / battery tiers (absolute time would
  // lose its 0.017 s resolution after ~1 minute).
  let springDt = select(0.016, clamp(fract(t - st1.x), 0.001, 0.05), stateOk);
  let springOmega = 8.0;
  mouseVelocity += ((rawMouse - mouseUv) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
  mouseUv += mouseVelocity * springDt;
  let mouse = vec2<f32>(mouseUv.x * aspect, mouseUv.y);
  let pressed = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let reliefContext = 0.6 + 0.4 * clamp(sourceDepth, 0.0, 1.0);

  // Chromatic aberration offset scaled by aspect
  let caStrength = 0.003 * (1.0 + bass) / aspect;
  let rResult = evalStrings(vec2<f32>((uv.x + caStrength) * aspect, uv.y), t, fundamental, harmonicRichness, damping, excitement, bass, aspect, reliefContext, mouse, pressed);
  let gResult = evalStrings(vec2<f32>(uv.x * aspect, uv.y), t, fundamental, harmonicRichness, damping, excitement, bass, aspect, reliefContext, mouse, pressed);
  let bResult = evalStrings(vec2<f32>((uv.x - caStrength) * aspect, uv.y), t, fundamental, harmonicRichness, damping, excitement, bass, aspect, reliefContext, mouse, pressed);
  var col = vec3<f32>(rResult.r, gResult.g, bResult.b);

  // Background acoustic resonance field
  let p = vec2<f32>(uv.x * aspect, uv.y);
  let resField = sin(p.x * 15.0 + t * 1.5) * sin(p.y * 12.0 - t) * 0.02 * (1.0 + bass);
  col += vec3<f32>(0.2, 0.15, 0.3) * abs(resField) * reliefContext;

  // Sympathetic resonance: all strings respond to bass
  let resonance = sin(p.x * 8.0 + t * 6.0) * bass * 0.05 * exp(-abs(p.y - 0.5) * 2.0);
  col += vec3<f32>(0.7, 0.6, 0.9) * abs(resonance) * reliefContext;

  // Interference between strings
  let interference = sin(p.x * 20.0 + t) * sin(p.y * 20.0 + t * 1.3);
  col += vec3<f32>(0.5, 0.3, 0.7) * interference * 0.05 * (1.0 + bass * excitement);

  // Energy glow
  let energyGlow = (1.0 - exp(-gResult.w * 1.5)) * (1.0 + bass * excitement);
  col += vec3<f32>(0.8, 0.6, 0.3) * energyGlow * 0.3;

  // Spectral bass bloom
  let bassBloom = exp(-length(uv - 0.5) * 3.0) * bass * 0.15;
  col += vec3<f32>(0.9, 0.5, 0.2) * bassBloom;

  // Harmonic overtones traveling wave (audio-excited)
  let overtoneWave = 0.03 * bass * sin(p.x * 40.0 - t * 8.0) * exp(-abs(p.y - 0.5));
  col += vec3<f32>(0.6, 0.8, 1.0) * abs(overtoneWave) * reliefContext;

  // Vignette
  let vignette = 1.0 - length(uv - 0.5) * 0.6;
  col *= vignette;

  // String cross-talk: nearby strings influence each other
  let crossTalk = sin(p.x * 12.0 + t * 3.0) * cos(p.y * 8.0 - t * 2.0) * 0.02 * bass;
  col += vec3<f32>(0.4, 0.5, 0.7) * abs(crossTalk) * reliefContext;

  // Higher-mode resonance visualization
  let modeResonance = sin(p.x * 30.0 - t * 5.0) * exp(-abs(p.y - 0.5) * 3.0) * 0.03 * bass;
  col += vec3<f32>(0.5, 0.8, 0.9) * abs(modeResonance) * reliefContext;

  // Harmonic decay trail visualization
  let decayTrail = exp(-gResult.w * 4.0) * 0.15 * (1.0 + bass * 0.5);
  col += vec3<f32>(0.9, 0.7, 0.4) * decayTrail * reliefContext;

  var clickResonance = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = t - ripple.z;
    if (age >= 0.0 && age < 1.6) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let ring = exp(-abs(length(delta) - age * 0.28) * 70.0) * exp(-age * 1.8);
      clickResonance = max(clickResonance, ring);
    }
  }
  col += vec3<f32>(0.35, 0.75, 1.2) * clickResonance * (0.7 + plasmaBuffer[0].z * 0.3);

  // Phase-locked amplitude modulation
  let phaseMod = sin(t * 0.7) * 0.5 + 0.5;
  col *= 0.9 + phaseMod * 0.1;

  // Bass-driven chromatic pulse
  let chromaPulse = 1.0 + bass * sin(t * 10.0) * 0.05;
  col *= chromaPulse;

  // Temporal feedback with decay
  let persistence = 0.92 - bass * 0.05;
  let temporal = prev * persistence;
  col = max(col, temporal * 0.4);

  // Depth falloff and tone mapping
  col *= reliefContext;
  col = acesToneMap(col * 1.2);

  let stringCoverage = 1.0 - exp(-gResult.w * 1.4);
  let alpha = clamp(stringCoverage + clickResonance * 0.25, 0.0, 0.96);
  let outDepth = clamp(stringCoverage * 0.92 + clickResonance * 0.08, 0.0, 1.0);
  let outColor = vec4<f32>(col, alpha);
  textureStore(writeTexture, pixel, outColor);
  textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  var aOut = outColor;
  if (global_id.y == 0u && global_id.x == 0u) { aOut = vec4<f32>(mouseUv, mouseVelocity); }
  if (global_id.y == 0u && global_id.x == 1u) { aOut = vec4<f32>(fract(t), 0.0, 0.0, SENT); }
  textureStore(dataTextureA, pixel, aOut);
}
