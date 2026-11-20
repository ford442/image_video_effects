// ═══════════════════════════════════════════════════════════════════
//  Strange Field Flow
//  Category: generative
//  Features: audio-reactive, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-23
//  Upgraded: 2026-09-15, 2026-11-20
//  Ideas: Lyapunov stretch tint from log|Δstep|; Pickover stalks min(|x|,|y|) on this orbit; fold count as material — soft axis-crossing count of the orbit shifts hue (§12.2E); trap-hit iteration tints the stalks (§12.2E)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  A 2D strange-attractor-inspired vector field where each pixel
//  evaluates a modified Clifford / Peter de Jong attractor map and
//  paints streaks along the local flow direction. The attractor
//  coefficients pulse to audio, producing vivid acid-neon whorls
//  that morph continuously. Temporal persistence burns trails.

#include "_prelude.wgsl"
// zoom_params: x=Drift Speed, y=Chaos Blend, z=Orbit Density, w=Trail Persistence

const TAU: f32 = 6.283185307179586;
const ITERS: i32 = 8;

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn loadC(uv: vec2<f32>, dims: vec2<u32>) -> vec4<f32> {
  let maxC = vec2<i32>(dims) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(uv * vec2<f32>(dims)), vec2<i32>(0), maxC);
  return textureLoad(dataTextureC, coord, 0);
}

fn deJongStep(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
  let x = sin(a * p.y) - cos(b * p.x);
  let y = sin(c * p.x) - cos(d * p.y);
  return vec2<f32>(x, y);
}

fn cliffordStep(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
  let x = sin(a * p.y) + c * cos(a * p.x);
  let y = sin(b * p.x) + d * cos(b * p.y);
  return vec2<f32>(x, y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res    = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coord  = vec2<i32>(global_id.xy);
  let dimsC  = textureDimensions(dataTextureC);
  let uv     = vec2<f32>(global_id.xy) / res;
  let time   = u.config.x;
  let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let speed    = mix(0.15, 1.8, u.zoom_params.x);
  let chaos    = mix(0.0,  1.0, u.zoom_params.y);
  let density  = mix(1.0,  3.5, u.zoom_params.z);
  let feedback = u.zoom_params.w;

  let t = time * speed;
  let a = 1.7  + 0.9 * sin(t * 0.13) + bass   * 0.6;
  let b = -1.3 + 0.8 * cos(t * 0.17) + mids   * 0.5;
  let c = -1.8 + 0.7 * sin(t * 0.11) + treble * 0.4;
  let d = 1.5  + 0.9 * cos(t * 0.19) + bass   * 0.3;

  let scale = 2.5;
  var q = (uv - 0.5) * 2.0 * scale;

  var density_acc = 0.0;
  var orbit_hue   = 0.0;
  var lyap_acc    = 0.0;
  var pickover    = 10.0;
  var folds       = 0.0;  // Idea 3: soft count of axis crossings along this orbit
  var trapIter    = 0.0;  // Idea 4: iterate at which the Pickover trap was closest
  var pt = q;

  for (var i: i32 = 0; i < ITERS; i = i + 1) {
    let prevPt = pt;
    let pJ = deJongStep(pt, a, b, c, d);
    let pC = cliffordStep(pt, a, b, c, d);
    pt = mix(pJ, pC, chaos);

    let stepLen = length(pt - prevPt);
    lyap_acc = lyap_acc + log(max(stepLen, 1.0e-4));
    // ── Idea 3: fold count as material (§12.2E) ─────────────────────
    // The orbit's symbolic itinerary: each step that carries a coordinate
    // across an axis is one fold of the map. Soft (smoothstep, not step) so
    // the cell edges of the folding skeleton do not alias.
    let xing = vec2<f32>(1.0) - smoothstep(vec2<f32>(-0.12), vec2<f32>(0.12), pt * prevPt);
    folds = folds + xing.x + xing.y;

    // ── Idea 4: orbit-trap hit time (§12.2E) ────────────────────────
    // HEAD kept only the min distance; promote *which iterate* made it.
    let trapNow = min(abs(pt.x), abs(pt.y));
    trapIter = mix(trapIter, f32(i), f32(trapNow < pickover));
    pickover = min(pickover, trapNow);

    let orbitUV = pt / (scale * 2.0) + 0.5;
    let delta   = abs(uv - orbitUV);
    let w = exp(-length(delta) * 30.0 * (1.0 + mids));
    density_acc = density_acc + w;
    orbit_hue   = orbit_hue + w * fract(f32(i) / f32(ITERS) + time * speed * 0.08);
  }

  density_acc = density_acc / f32(ITERS);
  let normHue = select(0.0, orbit_hue / max(density_acc * f32(ITERS), 0.001), density_acc > 0.001);
  let lyap = lyap_acc / f32(ITERS);
  let stretch = clamp((lyap + 0.4) * 1.1, 0.0, 1.0);
  let stalks = exp(-pickover * 9.0);

  let foldHue = folds * 0.045;  // Idea 3: cells that fold alike share a hue family
  let hue = fract(normHue + time * speed * 0.05 + length(q) * 0.04 + stretch * 0.18 + foldHue);
  let sat = 0.88 + treble * 0.12;
  let val = density_acc * density * (1.0 + bass * 0.6) + stalks * 0.55;
  var color = hsv2rgb(vec3<f32>(hue, sat, 1.0)) * val;
  color = mix(color, vec3<f32>(0.15, 0.55, 1.0) * val, stretch * 0.35);
  // Idea 4: stalks keep their warm base but lean toward the hue of the
  // iterate that grazed the axis (early = near the pixel, late = deep orbit).
  let trapTint = hsv2rgb(vec3<f32>(fract(0.08 + trapIter / f32(ITERS) * 0.8 + time * speed * 0.03), 0.6, 1.0));
  let stalkCol = mix(vec3<f32>(1.0, 0.85, 0.55), trapTint, 0.55);
  color = color + stalkCol * stalks * (0.35 + treble * 0.4);

  var histUV = uv;
  let pullStrength = 0.003 + speed * 0.002;
  histUV = mix(histUV, vec2<f32>(0.5), pullStrength);
  let histP = (histUV - 0.5) * 2.0;
  let hRot  = 0.008 * speed;
  let hc = cos(hRot); let hs = sin(hRot);
  let rHistP = vec2<f32>(histP.x * hc - histP.y * hs, histP.x * hs + histP.y * hc);
  histUV = clamp(rHistP * 0.5 + 0.5, vec2<f32>(0.0), vec2<f32>(1.0));

  let prev  = loadC(histUV, dimsC).rgb;
  let fbMix = mix(0.1, 0.82, feedback);
  color = mix(color, prev * 0.91, fbMix);

  let cStr = 0.003 + bass * 0.005;
  let cDir = normalize(uv - vec2<f32>(0.5) + 0.001);
  let prevR = loadC(clamp(uv + cDir * cStr * (1.0 + mids), vec2<f32>(0.0), vec2<f32>(1.0)), dimsC).r;
  let prevG = loadC(clamp(uv + cDir * cStr * (0.5 + treble), vec2<f32>(0.0), vec2<f32>(1.0)), dimsC).g;
  let prevB = loadC(clamp(uv - cDir * cStr * (0.8 + bass * 0.5), vec2<f32>(0.0), vec2<f32>(1.0)), dimsC).b;
  color = vec3<f32>(
    mix(color.r, prevR * 0.9, 0.02 + treble * 0.01),
    mix(color.g, prevG * 0.9, 0.02 + bass * 0.01),
    mix(color.b, prevB * 0.9, 0.02 + mids * 0.01)
  );

  let vign  = 1.0 - smoothstep(0.5, 1.1, length(q / scale));
  color = color * vign;
  color = clamp(color, vec3<f32>(0.0), vec3<f32>(4.0));
  let mapped = acesToneMap(color * 1.05);

  let depth = clamp(density_acc * 0.5 + stalks * 0.3, 0.0, 1.0);
  let alpha = clamp(length(mapped) * 0.5 + stalks * 0.25, 0.0, 1.0);
  let outCol = vec4<f32>(mapped, alpha);

  textureStore(writeTexture,      coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, outCol);
}
