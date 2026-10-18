// ═══════════════════════════════════════════════════════════════════
//  Chronos Monolith Resonator
//  Category: generative
//  Features: raymarched, KIFS, dark-matter, temporal-plasma, cosmic,
//            audio-reactive, mouse-driven, sub-surface-scattering, upgraded-rgba,
//            depth-aware, aces-tone-map, volumetric-ribbons
//  Complexity: Very High
//  Created: 2026-06-28
//  Upgraded: 2026-10-17
//  Ideas: Chladni node lines on obsidian faces; ribbon time-echo wakes; fracture core-leak; fold seams; braid knots;
//         ribbon spill-light painting the obsidian faces; core standing-wave nodal shells in the volume
//  A packing: HDR display RGB + semantic alpha (C read back as colour history); ACES on writeTexture only
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ─── Math Helpers ───
fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash3(p: vec3<f32>) -> f32 {
  var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  q = q + dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn rot3X(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn rot3Y(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rot3Z(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// ─── SDF ───
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
  let q = abs(p) - b;
  return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
  return length(p) - r;
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = sat(0.5 + 0.5 * (b - a) / k);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// ─── Noise ───
fn noise3D(p: vec3<f32>) -> f32 {
  let i = floor(p);
  var f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  let n = i.x + i.y * 157.0 + i.z * 113.0;
  return mix(
    mix(mix(hash3(vec3<f32>(n)), hash3(vec3<f32>(n + 1.0)), f.x),
        mix(hash3(vec3<f32>(n + 157.0)), hash3(vec3<f32>(n + 158.0)), f.x), f.y),
    mix(mix(hash3(vec3<f32>(n + 113.0)), hash3(vec3<f32>(n + 114.0)), f.x),
        mix(hash3(vec3<f32>(n + 270.0)), hash3(vec3<f32>(n + 271.0)), f.x), f.y),
    f.z
  );
}

fn fbm(p: vec3<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    v = v + a * noise3D(pp);
    pp = pp * 2.03;
    a = a * 0.5;
  }
  return v;
}

// ─── ACES Tone Map ───
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ─── KIFS Monolith ───
fn sdKIFSMonolith(p: vec3<f32>, time: f32, complexity: f32) -> f32 {
  var z = p;
  var dr = 1.0;
  let foldLimit = 1.0 + complexity * 0.5;
  
  for (var i: i32 = 0; i < 3; i = i + 1) {
    z = abs(z);
    if (z.x + z.y + z.z < foldLimit) {
      z = z * 2.0 - vec3<f32>(foldLimit * 0.5);
      dr = dr * 2.0;
    }
    let rot = rot3Y(time * 0.1 + f32(i) * 1.0) * rot3X(time * 0.07 + f32(i) * 0.7);
    z = rot * z;
  }
  let d = sdBox(z, vec3<f32>(0.5)) / dr;
  return d;
}

// ─── Scene Map ───
struct MapResult {
  d: f32,
  mat: f32,    // 0 = monolith, 1 = ribbon, 2 = inner core, 3 = fracture
  glow: f32,
};

fn map(p_in: vec3<f32>, time: f32, audio: f32, complexity: f32,
       plasmaDensity: f32, coreResonance: f32, mousePos: vec3<f32>) -> MapResult {
  var p = p_in;

  // Mouse gravity well
  let md = p - mousePos;
  let mDist = length(md);
  if (mDist < 2.5) {
    let g = (1.0 - mDist / 2.5) * 0.3;
    p = p + normalize(md) * g;
  }

  // Audio-reactive gravitational distortion
  let grav = sin(p.x * 2.0 + time * 3.0) * sin(p.y * 2.0 + time * 2.5) * audio * 0.05;
  p = p + vec3<f32>(grav, grav * 0.7, grav * 0.5);

  // Monolith body
  let monolith = sdKIFSMonolith(p, time, complexity);

  // Fractures that shift over time
  let fractureNoise = fbm(p * 3.0 + vec3<f32>(time * 0.2, time * 0.15, time * 0.1));
  // fbm lies in [0,1), so the old `fractureNoise < 0.0` test never fired and the
  // fracture material (and its core-leak) was unreachable: cracks are the thin
  // iso-band where the drifting noise crosses its midpoint.
  let isFractured = select(0.0, 1.0, abs(fractureNoise - 0.5) < 0.022);

  // Inner crystal core (visible through fractures)
  let core = sdSphere(p, 0.8 + sin(time * 0.5) * 0.1);
  let coreGlow = (1.0 - sat(core / 0.3)) * coreResonance;

  // Temporal plasma ribbons - orbiting around monolith
  let orbitSpeed = time * 0.5 + audio * 0.3;
  let ribbons = ribbonField(p, orbitSpeed, audio);

  // Combine scene
  var d = smin(monolith, ribbons, 0.1);
  
  // Inner core is "inside" the monolith
  let coreDist = max(monolith, core);
  d = min(d, coreDist);

  // Determine material
  var mat = 0.0; // monolith
  var glow = 0.0;

  if (ribbons < monolith && ribbons < coreDist) {
    mat = 1.0; // ribbon
    glow = plasmaDensity * (1.0 + audio * 0.5);
  } else if (core < 0.0 && monolith < 0.1) {
    mat = 2.0; // inner core
    glow = coreGlow * 2.0;
  } else if (isFractured > 0.5 && monolith < 0.05) {
    mat = 3.0; // fracture
    glow = coreGlow * 0.5;
  }

  return MapResult(d, mat, glow);
}

// The three orbit capsules at a given orbit phase (map uses the live phase, idea 2 earlier ones).
fn ribbonTrio(p: vec3<f32>, orbitSpeed: f32, audio: f32) -> vec3<f32> {
  let ribbon1 = sdCapsule(
    p,
    vec3<f32>(cos(orbitSpeed) * 1.5, sin(orbitSpeed * 1.3) * 0.5, sin(orbitSpeed) * 1.5),
    vec3<f32>(cos(orbitSpeed + 1.0) * 1.8, sin(orbitSpeed * 1.3 + 2.0) * 0.8, sin(orbitSpeed + 1.0) * 1.8),
    0.05 + audio * 0.02
  );
  let ribbon2 = sdCapsule(
    p,
    vec3<f32>(sin(orbitSpeed * 0.7) * 2.0, cos(orbitSpeed * 1.1) * 1.0, cos(orbitSpeed * 0.7) * 2.0),
    vec3<f32>(sin(orbitSpeed * 0.7 + 1.5) * 2.2, cos(orbitSpeed * 1.1 + 2.5) * 1.3, cos(orbitSpeed * 0.7 + 1.5) * 2.2),
    0.04 + audio * 0.015
  );
  let ribbon3 = sdCapsule(
    p,
    vec3<f32>(cos(orbitSpeed * 0.4 + 3.0) * 1.2, sin(orbitSpeed * 0.6) * 1.5, sin(orbitSpeed * 0.4 + 3.0) * 1.2),
    vec3<f32>(cos(orbitSpeed * 0.4 + 4.0) * 1.5, sin(orbitSpeed * 0.6 + 2.0) * 1.8, sin(orbitSpeed * 0.4 + 4.0) * 1.5),
    0.03 + audio * 0.01
  );
  return vec3<f32>(ribbon1, ribbon2, ribbon3);
}

fn ribbonField(p: vec3<f32>, orbitSpeed: f32, audio: f32) -> f32 {
  let ribbons = ribbonTrio(p, orbitSpeed, audio);
  return min(ribbons.x, min(ribbons.y, ribbons.z));
}

fn calcNormal(p: vec3<f32>, time: f32, audio: f32, complexity: f32,
              plasmaDensity: f32, coreResonance: f32, mousePos: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let m1 = map(p + e.xyy, time, audio, complexity, plasmaDensity, coreResonance, mousePos);
  let m2 = map(p - e.xyy, time, audio, complexity, plasmaDensity, coreResonance, mousePos);
  let m3 = map(p + e.yxy, time, audio, complexity, plasmaDensity, coreResonance, mousePos);
  let m4 = map(p - e.yxy, time, audio, complexity, plasmaDensity, coreResonance, mousePos);
  let m5 = map(p + e.yyx, time, audio, complexity, plasmaDensity, coreResonance, mousePos);
  let m6 = map(p - e.yyx, time, audio, complexity, plasmaDensity, coreResonance, mousePos);
  return normalize(vec3<f32>(m1.d - m2.d, m3.d - m4.d, m5.d - m6.d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let audio = plasmaBuffer[0].x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let temporalFlow = mix(0.1, 1.5, clamp(u.zoom_params.x, 0.0, 1.0));
  let plasmaDensity = mix(0.0, 1.0, clamp(u.zoom_params.y, 0.0, 1.0));
  let monolithComplexity = mix(1.0, 5.0, clamp(u.zoom_params.z, 0.0, 1.0));
  let coreResonance = mix(0.0, 1.0, clamp(u.zoom_params.w, 0.0, 1.0));

  // Mouse in 3D
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mouseUV = u.zoom_config.yz;
  let mouseY = 1.0 - mouseUV.y;  // Flip Y: screen top = up (uv.y grows downward)
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  var shock = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 3.0) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      let ring = abs(length(delta) - age * (0.18 + temporalFlow * 0.08));
      shock += (1.0 - smoothstep(0.0, 0.028, ring)) * (1.0 - age / 3.0);
    }
  }
  shock = min(shock, 2.0);
  let mousePos = vec3<f32>(
    (mouseUV.x * 2.0 - 1.0) * 3.0 * aspect,
    (1.0 - mouseUV.y * 2.0) * 3.0,  // 3D position: screen top = +Y (up)
    0.0
  );

  // Camera - orbiting the monolith
  let camDist = 5.0 + sin(time * 0.1) * 0.5 - held * 0.65 + shock * 0.18;
  let camAng = time * 0.15 * temporalFlow + mouseUV.x * 0.5;
  let camHeight = sin(time * 0.08) * 0.5 + mouseY * 0.3;
  let ro = vec3<f32>(cos(camAng) * camDist, camHeight, sin(camAng) * camDist);
  let ta = vec3<f32>(0.0, 0.0, 0.0);
  let ww = normalize(ta - ro);
  let uu = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), ww));
  let vv = cross(ww, uu);

  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  // uv.y grows downward; negate so world +y (the lit, AO-bright side) is up
  let rd = normalize(p.x * uu - p.y * vv + 2.5 * ww);

  // Raymarch
  var t = 0.0;
  var col = vec3<f32>(0.0);
  var hit = false;
  var hitPos = vec3<f32>(0.0);
  var hitMat = 0.0;
  var hitGlow = 0.0;
  var depth = 0.0;

  for (var i: i32 = 0; i < 100; i = i + 1) {
    let pos = ro + rd * t;
    let res = map(pos, time, audio, monolithComplexity, plasmaDensity, coreResonance, mousePos);

    if (res.d < 0.005) {
      hit = true;
      hitPos = pos;
      hitMat = res.mat;
      hitGlow = res.glow;
      depth = t;
      break;
    }

    if (t > 30.0) { break; }
    t = t + res.d * 0.7;
  }

  if (hit) {
    let n = calcNormal(hitPos, time, audio, monolithComplexity, plasmaDensity, coreResonance, mousePos);
    let viewDir = -rd;
    let nDotV = sat(dot(n, viewDir));

    let lightDir = normalize(vec3<f32>(0.5, 0.8, 0.3));
    let diff = sat(dot(n, lightDir));
    let spec = pow(sat(dot(reflect(-lightDir, n), viewDir)), 64.0);

    if (hitMat < 0.5) {
      // Monolith - obsidian dark matter
      let obsidian = vec3<f32>(0.02, 0.015, 0.025);
      let sharpSpec = pow(sat(dot(reflect(-lightDir, n), viewDir)), 128.0);
      col = obsidian * (0.2 + diff * 0.3) + vec3<f32>(0.4, 0.35, 0.5) * sharpSpec * 0.6;
      
      // Subsurface core glow through fractures
      col = col + vec3<f32>(0.1, 0.05, 0.2) * hitGlow * 0.5;
      
      // Fresnel edge
      let fresnel = pow(1.0 - nDotV, 4.0);
      col = col + vec3<f32>(0.05, 0.04, 0.08) * fresnel * 0.3;

      // Idea 1 — Chladni node lines: a standing-wave plate pattern on whichever face the normal picks
      let an = abs(n);
      var face = hitPos.xy;
      if (an.x >= an.y && an.x >= an.z) { face = hitPos.yz; }
      else if (an.y >= an.z) { face = hitPos.xz; }
      let modeN = 2.0 + floor(monolithComplexity);
      let modeM = modeN + 1.0 + floor(bass * 2.0);
      let fk = face * 2.4 + vec2<f32>(sin(time * 0.13), cos(time * 0.11)) * 0.15;
      let plate = cos(modeN * fk.x) * cos(modeM * fk.y) - cos(modeM * fk.x) * cos(modeN * fk.y);
      let nodal = 1.0 - smoothstep(0.0, 0.07 + bass * 0.04, abs(plate));
      col = col + vec3<f32>(0.35, 0.55, 1.0) * nodal * (coreResonance * 0.5 + bass * 0.45 + shock * 0.3);
      // Idea: fold seam — crease where the absolute sum meets the KIFS fold limit.
      let foldLimit = 1.0 + monolithComplexity * 0.5;
      let foldSum = abs(hitPos.x) + abs(hitPos.y) + abs(hitPos.z);
      let seam = exp(-abs(foldSum - foldLimit) * 9.0);
      col = col + vec3<f32>(0.55, 0.72, 1.0) * seam * (0.28 + coreResonance * 0.55);
      // Idea 6 — ribbon spill-light: each orbiting plasma ribbon is an emitter, so the
      // obsidian it sweeps past picks up its hue (cosine-weighted toward the ribbon)
      let liveOrbitS = time * 0.5 + audio * 0.3;
      let trioS = ribbonTrio(hitPos, liveOrbitS, audio);
      let spillPhase = hitPos.x * 2.0 + time * 2.0;
      let spillCol = vec3<f32>(0.2 + 0.3 * sin(spillPhase), 0.3 + 0.4 * sin(spillPhase + 2.09), 0.5 + 0.3 * sin(spillPhase + 4.18));
      let spillFacing = 0.35 + 0.65 * sat(dot(n, normalize(hitPos)) + 0.5);
      let spill = exp(-trioS.x * 3.5) + exp(-trioS.y * 3.5) * 0.8 + exp(-trioS.z * 3.5) * 0.6;
      col = col + max(spillCol, vec3<f32>(0.0)) * spill * spillFacing * plasmaDensity * (1.2 + audio * 0.6);
    } else if (hitMat < 1.5) {
      // Temporal plasma ribbon - cyan, violet, gold
      let ribbonPhase = hitPos.x * 2.0 + time * 2.0;
      var ribbonCol = vec3<f32>(
        0.2 + 0.3 * sin(ribbonPhase + 0.0),
        0.3 + 0.4 * sin(ribbonPhase + 2.09),
        0.5 + 0.3 * sin(ribbonPhase + 4.18)
      );
      ribbonCol = ribbonCol * (1.0 + hitGlow * 2.0 + audio * 0.5);
      
      let ribbonSpec = pow(sat(dot(reflect(-lightDir, n), viewDir)), 16.0);
      col = ribbonCol * (0.4 + diff * 0.4) + vec3<f32>(0.5, 0.7, 1.0) * ribbonSpec * 0.4;
      col = col + vec3<f32>(0.3, 0.2, 0.5) * hitGlow * 0.3;
    } else if (hitMat < 2.5) {
      // Inner crystal core - hyper-refractive
      let coreCol = vec3<f32>(0.1, 0.3, 0.5) * (1.0 + hitGlow * 3.0);
      let coreSpec = pow(sat(dot(reflect(-lightDir, n), viewDir)), 256.0);
      col = coreCol * (0.5 + diff * 0.5) + vec3<f32>(0.6, 0.8, 1.0) * coreSpec * 0.8;
      col = col + vec3<f32>(0.2, 0.5, 0.8) * hitGlow * 0.5;
    } else {
      // Fracture - revealing core
      let fractureCol = vec3<f32>(0.15, 0.05, 0.2) * (0.5 + hitGlow * 2.0);
      col = fractureCol + vec3<f32>(0.3, 0.2, 0.5) * spec * 0.3;
      // Idea 3 — fracture core-leak: cracks nearer the inner core spill its light
      let coreNear = exp(-max(length(hitPos) - 0.8, 0.0) * 2.5);
      col = col + vec3<f32>(0.2, 0.5, 0.8) * coreNear * (0.25 + coreResonance * 1.4) * (0.8 + mids * 0.4);
    }

    // Ambient occlusion
    let ao = sat(0.5 + 0.5 * n.y);
    col = col * (0.4 + 0.6 * ao);
  } else {
    // Cosmic void background
    col = vec3<f32>(0.005, 0.008, 0.015);
    // Stars
    let starNoise = hash21(floor((uv + vec2<f32>(time * 0.01, 0.0)) * 300.0));
    let stars = step(0.998, starNoise) * (0.5 + 0.5 * sin(time * 10.0 + starNoise * 50.0));
    col = col + vec3<f32>(0.8, 0.85, 1.0) * stars * (0.3 + treble * 0.3);
    depth = 30.0;
  }

  // Volumetric ribbon glow
  var volGlow = vec3<f32>(0.0);
  for (var i: i32 = 0; i < 20; i = i + 1) {
    let vt = f32(i) * 1.0 + hash21(vec2<f32>(f32(i32(gid.x) + i * 73), f32(i32(gid.y) + i * 137))) * 0.5;
    if (vt > depth) { break; }
    let vPos = ro + rd * vt;
    let vRes = map(vPos, time, audio, monolithComplexity, plasmaDensity, coreResonance, mousePos);
    if (vRes.mat > 0.5 && vRes.mat < 1.5) {
      let falloff = exp(-vt * 0.1);
      let ribbonPhase = vPos.x * 2.0 + time * 2.0;
      let vCol = vec3<f32>(
        0.1 + 0.15 * sin(ribbonPhase + 0.0),
        0.15 + 0.2 * sin(ribbonPhase + 2.09),
        0.25 + 0.15 * sin(ribbonPhase + 4.18)
      );
      volGlow = volGlow + vCol * falloff * 0.02 * (0.5 + audio * 0.5);
    }
    // Idea 2 — ribbon time-echo: the same ribbons at earlier orbit phases leave fading wakes
    let liveOrbit = time * 0.5 + audio * 0.3;
    for (var k: i32 = 1; k <= 3; k = k + 1) {
      let lag = f32(k) * (0.22 + temporalFlow * 0.1);
      let dEcho = ribbonField(vPos, liveOrbit - lag, audio);
      let echoPhase = vPos.x * 2.0 + (time - lag * 2.0) * 2.0;
      let eCol = vec3<f32>(0.1 + 0.1 * sin(echoPhase), 0.15 + 0.12 * sin(echoPhase + 2.09), 0.3 + 0.1 * sin(echoPhase + 4.18));
      volGlow = volGlow + eCol * exp(-dEcho * 9.0) * exp(-vt * 0.1) * plasmaDensity * 0.035 / f32(k);
    }
    // Idea: braid knot — gold where two of the live ribbons pass close.
    let trio = ribbonTrio(vPos, liveOrbit, audio);
    let knot = exp(-trio.x * 8.0) * exp(-trio.y * 8.0)
      + exp(-trio.y * 8.0) * exp(-trio.z * 8.0)
      + exp(-trio.z * 8.0) * exp(-trio.x * 8.0);
    volGlow = volGlow + vec3<f32>(1.0, 0.82, 0.35) * knot * plasmaDensity * 0.09;
  }

  // Idea 7 — core standing-wave nodal shells: the resonating core's spherical
  // standing wave has fixed node radii; resonance dust settles there as thin
  // shells. Solved per ray (impact parameter), so each shell gets crisp limb
  // brightening instead of march speckle; shells behind the monolith are occluded.
  let tMid = dot(-ro, rd);
  let bImp = length(cross(ro, rd));
  let shellGap = 0.46 - monolithComplexity * 0.03;
  let breathe = 0.6 + 0.4 * abs(cos(time * temporalFlow * 3.0));
  var shellGlow = 0.0;
  for (var sn: i32 = 0; sn < 4; sn = sn + 1) {
    let R = 1.05 + f32(sn) * shellGap;
    if (bImp < R) {
      let h = sqrt(R * R - bImp * bImp);
      let limb = min(R / max(h, 1e-3), 7.0) / (1.0 + f32(sn) * 0.6);
      shellGlow += limb * (select(0.0, 1.0, tMid - h < depth) + select(0.0, 1.0, tMid + h < depth));
    }
  }
  volGlow = volGlow + vec3<f32>(0.25, 0.42, 1.0) * shellGlow * coreResonance * breathe * (0.07 + bass * 0.04);
  col = col + volGlow;

  // Screen-space resonator harmonics make click energy legible across the void.
  let radial = length((uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0));
  let harmonic = pow(0.5 + 0.5 * cos(radial * (58.0 + monolithComplexity * 7.0) - time * temporalFlow * 8.0), 16.0);
  col += vec3<f32>(0.18, 0.55, 1.0) * harmonic * (coreResonance * 0.18 + shock * 0.55 + treble * 0.08);
  col += vec3<f32>(0.7, 0.2, 1.0) * exp(-length((uv - mouseUV) * vec2<f32>(aspect, 1.0)) * 8.0) * held * (0.25 + mids * 0.35);

  // Temporal persistence
  let prev = textureLoad(dataTextureC, coord, 0);
  let hdr = clamp(mix(col, prev.rgb * 0.92, 0.03), vec3<f32>(0.0), vec3<f32>(8.0));

  // Tone map (display only; A keeps HDR history)
  let display = acesToneMap(hdr * 1.3);

  let hitSignal = select(0.0, 1.0, hit);
  let alpha = clamp(hitSignal * 0.72 + length(volGlow) * 0.9 + harmonic * coreResonance * 0.18 + shock * 0.25, 0.02, 1.0);
  let finalDepth = sat(0.95 - depth * 0.03);

  textureStore(writeTexture, coord, vec4<f32>(display, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(hdr, alpha));
}
