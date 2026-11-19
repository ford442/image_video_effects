// ═══════════════════════════════════════════════════════════════════
//  Phosphorescent Jellyfish
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, chromatic, depth-aware, upgraded-rgba
//  Complexity: High
//  Description: Glowing jellyfish with trailing tentacle bioluminescence.
//               Bass pulses the bell contraction, mids create tentacle wave
//               motion, treble adds individual photophore sparkles.
//               Mouse attracts the jellyfish swarm (while pressed);
//               clicks startle the nearest jelly into a jet-propulsion dart.
//  Created: 2026-05-30
//  Upgraded: 2026-11-19 (prev 2026-07-22)
//  Ideas: contraction velum; manubrium
//  A packing: HDR display RGB + alpha (ACES on writeTexture only)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265;
// Maximum HDR stack allowed before tonemapping; anything above is
// scaled down along its own hue vector so saturated cyans/violets
// keep their color instead of clipping to white.
const HDR_CEILING: f32 = 2.0;

fn hash21(p: vec2<f32>) -> f32 {
  var q = fract(p * vec2<f32>(123.34, 456.21));
  q += dot(q, q + 45.32);
  return fract(q.x * q.y);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
  return fract(sin(q) * 43758.5453);
}

// Jellyfish bell SDF — hemisphere with flattened bottom
fn sdBell(p: vec2<f32>, radius: f32, pulse: f32) -> f32 {
  let r = radius * (1.0 + pulse * 0.15);
  let d = length(p);
  let bell = d - r;
  let bottom = p.y + r * 0.3;
  return max(bell, bottom);
}

// Tentacle glow field
fn tentacleGlow(p: vec2<f32>, origin: vec2<f32>, time: f32, waveStrength: f32, count: f32) -> f32 {
  let rel = p - origin;
  let dist = length(rel);
  var glow = 0.0;
  let tCount = max(count, 3.0);
  for (var i: i32 = 0; i < 8; i++) {
    if (f32(i) >= tCount) { break; }
    let fi = f32(i);
    let jHash = hash22(vec2<f32>(origin.x + fi * 7.3, origin.y + fi * 13.1));
    let tAngle = (fi / tCount) * PI * 2.0 + jHash.x * 0.5;
    let wave = sin(dist * 8.0 - time * 3.0 + tAngle * 3.0 + jHash.y * 6.28318) * waveStrength * 0.3;
    let tentacleX = sin(tAngle) * (dist * 0.5 + 0.1) + wave;
    let tentacleY = -cos(tAngle) * (dist * 0.5 + 0.1) + abs(wave) * 0.5;
    let tPos = vec2<f32>(tentacleX, tentacleY);
    let tDist = length(rel - tPos);
    glow += exp(-tDist * tDist * 80.0) * 0.5;
  }
  return glow;
}

// Hue-preserving clamp: scale the whole color vector down when its
// brightest channel exceeds the HDR ceiling, so hue and saturation
// survive where a per-channel clamp would wash to white.
fn huePreserveClamp(c: vec3<f32>, ceiling: f32) -> vec3<f32> {
  let peak = max(c.r, max(c.g, c.b));
  if (peak > ceiling) {
    return c * (ceiling / peak);
  }
  return c;
}

// ACES filmic tonemap (Narkowicz fit) — rolls the tamed HDR glow off
// smoothly so stacked bells/tentacles stay luminous without blowout.
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv01 = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let uv = (uv01 - 0.5) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let mousePos = vec2<f32>(mouse.x * aspect, mouse.y);
  // Mouse button state gates the swarm attraction (jet-propulsion startle).
  let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Slider params drive this shader's real constants:
  //   x → swarm population, y → bell radius,
  //   z → feedback trail persistence, w → HDR glow intensity.
  let swarmCount  = mix(1.0, 5.0, u.zoom_params.x);
  let bellSize    = mix(0.08, 0.2, u.zoom_params.y);
  let trailPersistence = mix(0.85, 0.99, u.zoom_params.z);
  let glowIntensity    = mix(0.5, 3.0, u.zoom_params.w);

  var col = vec3<f32>(0.0);
  var alpha = 0.0;
  var depthVal = 0.0;

  // Deep abyss background
  let abyss = vec3<f32>(0.01, 0.02, 0.05) * (1.0 - length(uv) * 0.5);
  col = abyss;

  let nJelly = i32(clamp(swarmCount, 1.0, 5.0));

  // ─── Pass 1: base orbital positions (needed for "nearest jelly" tests) ───
  var basePos: array<vec2<f32>, 5>;
  for (var j: i32 = 0; j < 5; j++) {
    if (j >= nJelly) { break; }
    let fj = f32(j);
    let jHash = hash22(vec2<f32>(fj, fj * 3.7));
    let orbitRadius = 0.2 + jHash.x * 0.3;
    let orbitSpeed = 0.3 + jHash.y * 0.4;
    let angle = time * orbitSpeed + fj * 1.25;
    basePos[j] = vec2<f32>(cos(angle) * orbitRadius, sin(angle) * orbitRadius * 0.6);
  }

  // Highest valid per-band spectrum index (plasmaBuffer[0] is the global mix).
  let bandMax = max(arrayLength(&plasmaBuffer), 1u) - 1u;

  // ─── Pass 2: per-jelly glow accumulation ───
  for (var j: i32 = 0; j < nJelly; j++) {
    let fj = f32(j);
    let jHash = hash22(vec2<f32>(fj, fj * 3.7));
    var jPos = basePos[j];

    // Mouse attraction — only while the button is held; the swarm
    // drifts free otherwise. Epsilon guard keeps normalize() safe.
    let toMouse = mousePos - jPos;
    let distToMouse = length(toMouse);
    jPos += normalize(toMouse + vec2<f32>(0.001)) * (1.0 / (1.0 + distToMouse * 3.0)) * 0.15 * mouseDown;

    // Jet propulsion dart: each click ripple startles the single nearest
    // jellyfish, kicking it AWAY from the click with a decaying impulse.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
      let rp = u.ripples[i];
      let age = time - rp.z;
      if (age < 0.0 || age > 1.2) { continue; }
      let rpPos = (rp.xy - 0.5) * vec2<f32>(aspect, 1.0);
      let myDist = length(basePos[j] - rpPos);
      var isNearest = true;
      for (var k: i32 = 0; k < 5; k++) {
        if (k >= nJelly) { break; }
        if (length(basePos[k] - rpPos) < myDist - 0.0001) { isNearest = false; }
      }
      if (isNearest) {
        let awayDir = normalize(basePos[j] - rpPos + vec2<f32>(0.001));
        let kick = 1.0 - age / 1.2;
        jPos += awayDir * kick * kick * 0.35;
      }
    }

    // Per-jelly spectrum: jelly j pulses to its own FFT band.
    let band = plasmaBuffer[min(u32(j) + 1u, bandMax)];
    let bandLow = band.x;
    let bandMid = band.y;
    let bandHigh = band.z;

    // Band-driven bell pulse (own frequency instead of global bass)
    let pulse = sin(time * 3.0 + fj) * bandLow * 0.5;
    let size = bellSize * (0.8 + jHash.y * 0.4);

    // Bell distance and glow
    let bellDist = sdBell(uv - jPos, size, pulse);
    let bellGlow = exp(-bellDist * bellDist * 200.0) * glowIntensity;

    // ── Idea 1: contraction velum — the lower margin lights while the bell squeezes ──
    let pBell = uv - jPos;
    let radNow = size * (1.0 + pulse * 0.15);
    let squeeze = clamp(-cos(time * 3.0 + fj), 0.0, 1.0);
    let margin = exp(-abs(length(pBell) - radNow) * 36.0) * smoothstep(0.15, -0.45, pBell.y / max(radNow, 0.02));
    let velum = margin * squeeze * (0.45 + bandLow) * glowIntensity;

    // ── Idea 2: manubrium — short oral arm under the dome, not another tentacle ──
    let manuRel = pBell - vec2<f32>(0.0, -radNow * 0.42);
    let manu = exp(-dot(manuRel, manuRel) / max(radNow * radNow * 0.06, 1e-4)) * glowIntensity * (0.28 + squeeze * 0.4);

    // Photophore sparkles driven by this jelly's high band
    let sparkleUV = floor((uv - jPos) * 40.0 + time * 10.0 * bandHigh);
    let sparkle = step(0.97, hash21(sparkleUV)) * bandHigh * 2.0;
    let sparkleGlow = exp(-bellDist * bellDist * 100.0) * sparkle * glowIntensity;

    // Tentacle bioluminescence driven by this jelly's mid band
    let tentGlow = tentacleGlow(uv, jPos, time + fj, bandMid, 4.0 + jHash.x * 4.0) * glowIntensity;

    // Per-jellyfish hue (cyan → violet)
    let hue = fj / 5.0 + 0.55;
    let bellCol = vec3<f32>(
      0.5 + 0.5 * cos(6.28318 * (hue + 0.0)),
      0.5 + 0.5 * cos(6.28318 * (hue + 0.33)),
      0.5 + 0.5 * cos(6.28318 * (hue + 0.67))
    );

    col += bellCol * bellGlow * 0.8;
    col += bellCol * sparkleGlow;
    col += bellCol * tentGlow * 0.6;
    col += bellCol * velum;
    col += bellCol * manu * 0.7;
    alpha += bellGlow + tentGlow * 0.5 + sparkleGlow + velum * 0.8 + manu * 0.45;
    depthVal = max(depthVal, bellGlow + tentGlow);
  }

  // ═══ Chromatic dispersion on temporal feedback (HDR domain) ═══
  let cStr = 0.004 + bass * 0.006;
  let cDir = normalize(uv01 - vec2<f32>(0.5) + vec2<f32>(0.001));

  // Exact C loads. The chroma offset is a pixel step so rgba32float history is not filtered.
  let pix = vec2<i32>(global_id.xy);
  let resI = vec2<i32>(i32(resolution.x), i32(resolution.y)) - vec2<i32>(1);
  let offR = cDir * cStr * (1.0 + mids) * resolution;
  let offG = cDir * cStr * (0.7 + bass * 0.5) * resolution;
  let offB = -cDir * cStr * (1.2 + treble) * resolution;
  let prevR = textureLoad(dataTextureC, clamp(pix + vec2<i32>(offR), vec2<i32>(0), resI), 0).r;
  let prevG = textureLoad(dataTextureC, clamp(pix + vec2<i32>(offG), vec2<i32>(0), resI), 0).g;
  let prevB = textureLoad(dataTextureC, clamp(pix + vec2<i32>(offB), vec2<i32>(0), resI), 0).b;
  var prevCol = vec3<f32>(prevR, prevG, prevB);

  // Temporal feedback blend — persistence mapping untouched by design;
  // the convergent 3-tap loop keeps its steady-state gain <= 0.33.
  col = mix(col, prevCol * trailPersistence, 0.2 + bass * 0.05);

  // Chromatic dispersion on current frame elements
  let dispersed = vec3<f32>(
    col.r + mids * 0.05,
    col.g + bass * 0.03,
    col.b + treble * 0.08
  );
  col = mix(col, dispersed, 0.3);

  // HDR state feeds the feedback buffer so the trail keeps its energy;
  // tonemapping happens only on the display path below.
  let hdrCol = col;

  // ═══ HDR taming: hue-preserving clamp at ~2.0, then ACES ═══
  var displayCol = huePreserveClamp(hdrCol, HDR_CEILING);
  displayCol = acesToneMap(displayCol);

  let luma = dot(displayCol, vec3<f32>(0.2126, 0.7152, 0.0722));
  alpha = clamp(alpha + luma * 0.15, 0.0, 1.0);
  depthVal = clamp(depthVal, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(displayCol, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(hdrCol, alpha));
}
