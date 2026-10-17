// ═══════════════════════════════════════════════════════════════════
//  Hyper-Dimensional Bismuth-Matrix
//  Category: generative
//  Features: raymarched, KIFS, bismuth-crystal, hopper-steps,
//            iridescent, audio-reactive, mouse-driven, upgraded-rgba,
//            depth-aware, chromatic, volumetric-fog
//  Complexity: Very High
//  Created: 2026-06-28
//  Upgraded: 2026-10-17
//  Ideas: twin-boundary misfit where hopper≈KIFS; stair-riser rainbow film thickness;
//         crucible melt line (liquid bismuth plane the lattice grows out of, with a
//         hot meniscus where crystals pierce it); cooling-melt glow in hopper hollows;
//         spiral hopper twist (each nested step turns about the growth axis);
//         oxide-age ladder (film thickens with height above the melt)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash3(p: vec3<f32>) -> f32 {
  let q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  let q2 = q + dot(q, q.yzx + 33.33);
  return fract((q2.x + q2.y) * q2.z);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn rot3Y(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rot3X(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn rot3Z(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// ─── SDF Primitives ───
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
  let q = abs(p) - b;
  return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdBoxFrame(p: vec3<f32>, b: vec3<f32>, e: f32) -> f32 {
  let q = abs(p) - b;
  let w = abs(q) - e;
  return min(max(q.x, max(q.y, q.z)), 0.0) + length(max(w, vec3<f32>(0.0)));
}

fn opRep(p: vec3<f32>, c: vec3<f32>) -> vec3<f32> {
  return p - c * round(p / c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = sat(0.5 + 0.5 * (b - a) / k);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// ─── Hopper Crystal SDF (stepped bismuth) ───
fn sdHopperCrystal(p: vec3<f32>, size: f32, steps: i32) -> f32 {
  var d = sdBox(p, vec3<f32>(size));
  var s = size * 0.5;
  var pp = p;
  // Idea 5 — spiral hopper: every nested hollow turns a few degrees further
  // about the growth axis, so the stair walls wind like real bismuth hoppers
  let twist = rot3Y(0.21);
  for (var i: i32 = 0; i < steps; i = i + 1) {
    pp = twist * pp;
    let offset = vec3<f32>(s * 0.35, s * 0.25, s * 0.3);
    pp = pp - offset;
    let inner = sdBox(pp, vec3<f32>(s * 0.88, s * 0.92, s * 0.88));
    d = max(d, -inner); // Hollow stepped
    s = s * 0.65;
  }
  return d;
}

// ─── KIFS Bismuth ───
fn sdKIFSBismuth(p: vec3<f32>, time: f32, complexity: f32, growthRate: f32) -> f32 {
  var z = p;
  var dr = 1.0;
  let rot = rot3Y(time * growthRate * 0.2) * rot3X(time * growthRate * 0.15);

  for (var i: i32 = 0; i < 3; i = i + 1) {
    z = rot * z;
    z = abs(z);
    if (z.x + z.y + z.z < complexity) {
      z = z * 2.0 - vec3<f32>(complexity * 0.5);
      dr = dr * 2.0;
    }
  }
  let d = sdBox(z, vec3<f32>(0.5)) / dr;
  return d;
}

// ─── Scene Map ───
struct MapResult {
  d: f32,
  mat: f32,
  ao: f32,
  twin: f32,
  riser: f32,
  hollow: f32,
};

// Idea 3 — slow rise/fall of the crucible melt the lattice is pulled from
fn meltLevel(time: f32) -> f32 {
  return -2.2 + 0.25 * sin(time * 0.11);
}

fn map(p_in: vec3<f32>, time: f32, audio: f32, complexity: f32,
       growthRate: f32, gridDensity: f32, disruptionRadius: f32,
       mousePos: vec3<f32>) -> MapResult {
  var p = p_in;

  // Mouse disruption field - quantum scatter
  let md = p - mousePos;
  let mDist = length(md);
  if (mDist < disruptionRadius * 3.0) {
    let disrupt = (1.0 - mDist / (disruptionRadius * 3.0));
    // Smooth scatter: per-sample hash noise made the SDF white noise inside the
    // zone (the idle pointer sits on the lattice centre), so the view rendered
    // as a flat grey wash. A low-frequency wobble stays marchable.
    let wob = vec3<f32>(sin(p.y * 2.3 + time * 1.7),
                        sin(p.z * 2.1 + time * 1.3 + 1.7),
                        sin(p.x * 2.7 + time * 1.9 + 3.1));
    p = p + wob * disrupt * 0.3;
  }

  // Domain repetition grid
  let cellSize = 2.5 / gridDensity;
  let q = opRep(p, vec3<f32>(cellSize));
  let cellId = floor(p / cellSize);
  let cellHash = hash3(cellId);

  // Audio-reactive rotation
  let phase = time * growthRate + cellHash * 6.28 + audio * 2.0;
  let rotation = rot3Y(phase * 0.5) * rot3X(phase * 0.3) * rot3Z(phase * 0.2);
  let rq = rotation * q;

  // Hopper crystal in each cell
  let stepCount = i32(2.0 + complexity * 3.0);
  let crystalSize = cellSize * 0.3;
  let bismuth = sdHopperCrystal(rq, crystalSize, stepCount);

  // KIFS structure at center
  let kifs = sdKIFSBismuth(q, time + cellHash * 10.0, complexity, growthRate);

  // Blend: bismuth + KIFS
  var d = smin(bismuth, kifs, 0.12);
  // Idea 1 — twin-boundary misfit at the hopper/KIFS meeting plane
  let twin = 1.0 - sat(abs(bismuth - kifs) / 0.08);

  // Interlocking stair-step extrusions
  let stairPhase = time * growthRate + cellHash * 3.14;
  let stairOffset = vec3<f32>(
    floor(rq.x / (crystalSize * 0.3)) * crystalSize * 0.15,
    floor(rq.y / (crystalSize * 0.3)) * crystalSize * 0.15,
    floor(rq.z / (crystalSize * 0.3)) * crystalSize * 0.15
  );
  let stair = sdBox(rq - stairOffset, vec3<f32>(crystalSize * 0.08, crystalSize * 0.12, crystalSize * 0.08));
  d = smin(d, stair, 0.04);
  // Idea 2 — each hopper riser gets a distinct film-thickness phase
  let riser = fract(floor(rq.y / max(crystalSize * 0.3, 0.001)) * 0.17 + cellHash);

  // Frame edges
  let frame = sdBoxFrame(q, vec3<f32>(cellSize * 0.38), cellSize * 0.015);
  d = smin(d, frame, 0.03);

  // Material
  var mat = 1.0; // crystal
  if (mDist < disruptionRadius * 0.5) {
    mat = 0.5; // disrupted zone
  }

  // Idea 4 — hollowness: surface points deep inside the hopper's outer cube are
  // the drained cavity walls (weighted by the hopper being the nearest surface)
  let outer = sdBox(rq, vec3<f32>(crystalSize));
  let hollow = sat(-outer / (crystalSize * 0.6)) * sat(1.0 - (bismuth - d) / 0.05);

  // Idea 3 — liquid bismuth plane; crystals below it are submerged
  let dMelt = p_in.y - meltLevel(time);
  if (dMelt < d) {
    d = dMelt;
    mat = 2.0;
  }

  let ao = sat(0.6 + 0.4 * hash3(cellId + vec3<f32>(0.5)));

  return MapResult(d, mat, ao, twin, riser, hollow);
}

fn calcNormal(p: vec3<f32>, time: f32, audio: f32, complexity: f32,
              growthRate: f32, gridDensity: f32, disruptionRadius: f32,
              mousePos: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let m1 = map(p + e.xyy, time, audio, complexity, growthRate, gridDensity, disruptionRadius, mousePos);
  let m2 = map(p - e.xyy, time, audio, complexity, growthRate, gridDensity, disruptionRadius, mousePos);
  let m3 = map(p + e.yxy, time, audio, complexity, growthRate, gridDensity, disruptionRadius, mousePos);
  let m4 = map(p - e.yxy, time, audio, complexity, growthRate, gridDensity, disruptionRadius, mousePos);
  let m5 = map(p + e.yyx, time, audio, complexity, growthRate, gridDensity, disruptionRadius, mousePos);
  let m6 = map(p - e.yyx, time, audio, complexity, growthRate, gridDensity, disruptionRadius, mousePos);
  return normalize(vec3<f32>(m1.d - m2.d, m3.d - m4.d, m5.d - m6.d));
}

// ─── Iridescent thin-film interference ───
fn iridescent(nDotV: f32, shift: f32, audio: f32) -> vec3<f32> {
  let t = nDotV * 3.14159 + shift + audio * 2.0;
  return vec3<f32>(
    0.5 + 0.5 * cos(t + 0.0),
    0.5 + 0.5 * cos(t + 2.0),
    0.5 + 0.5 * cos(t + 4.0)
  );
}

// ─── ACES Tone Map ───
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
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
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // extraBuffer is re-uploaded every frame, so a stored envelope never
  // persisted (it read back 0 and raced the (0,0) writer). Stateless bass.
  let bassEnv = bass;

  // Parameters
  let complexity = mix(1.5, 5.0, clamp(u.zoom_params.x, 0.0, 1.0));
  let iridescence = mix(0.3, 2.0, clamp(u.zoom_params.y, 0.0, 1.0));
  let growthRate = mix(0.2, 1.5, clamp(u.zoom_params.z, 0.0, 1.0));
  let disruptionRadius = mix(0.5, 3.0, clamp(u.zoom_params.w, 0.0, 1.0));

  // Mouse in 3D - screen top = UP (uv.y grows downward, so flip Y)
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mouseUV = u.zoom_config.yz;
  let mouseY = 1.0 - mouseUV.y;
  let mousePos = vec3<f32>(
    (mouseUV.x * 2.0 - 1.0) * 3.0 * aspect,
    (1.0 - mouseUV.y * 2.0) * 3.0,
    0.0
  );

  // Camera - flying through crystal cavern
  let camDist = 4.0 + sin(time * 0.1) * 0.5;
  let camAng = time * 0.1 + mouseUV.x * 0.4;
  let camHeight = mouseY * 1.5 + sin(time * 0.2) * 0.3;
  let ro = vec3<f32>(cos(camAng) * camDist, camHeight, sin(camAng) * camDist);
  let ta = vec3<f32>(0.0, 0.0, 0.0);
  let ww = normalize(ta - ro);
  let uu = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), ww));
  let vv = cross(ww, uu);

  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  let mouseDown = u.zoom_config.w > 0.5;

  // Screen-space crystal disruption fronts alter the local SDF radius while
  // they are alive, then decay completely.
  let rippleCount = min(u32(u.config.y), 50u);
  var crystalShock = 0.0;
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age < 0.0 || age > 3.6) { continue; }
    let center = (ripple.xy - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
    let delta = p - center;
    let radius = age * (0.24 + growthRate * 0.22);
    let ring = (length(delta) - radius) * 20.0;
    crystalShock += exp(-ring * ring) * exp(-age * 0.78);
  }
  let effectiveDisruption = disruptionRadius * (1.0 + crystalShock * 1.2 + select(0.0, 0.65, mouseDown));
  // uv.y grows downward; negate so world +y (and the melt below) render upright
  let rd = normalize(p.x * uu - p.y * vv + 2.5 * ww);

  // Raymarch
  var t = 0.0;
  var col = vec3<f32>(0.0);
  var hit = false;
  var hitPos = vec3<f32>(0.0);
  var hitMat = 0.0;
  var hitAo = 1.0;
  var hitTwin = 0.0;
  var hitRiser = 0.0;
  var hitHollow = 0.0;
  var depth = 0.0;

  for (var i: i32 = 0; i < 120; i = i + 1) {
    let pos = ro + rd * t;
    let res = map(pos, time, bassEnv, complexity, growthRate, 1.5, effectiveDisruption, mousePos);
    if (res.d < 0.005) {
      hit = true;
      hitPos = pos;
      hitMat = res.mat;
      hitAo = res.ao;
      hitTwin = res.twin;
      hitRiser = res.riser;
      hitHollow = res.hollow;
      depth = t;
      break;
    }
    if (t > 30.0) { break; }
    t = t + res.d * 0.7;
  }

  if (hit) {
    let n = calcNormal(hitPos, time, bassEnv, complexity, growthRate, 1.5, effectiveDisruption, mousePos);
    let viewDir = -rd;
    let nDotV = sat(dot(n, viewDir));

    let lightDir = normalize(vec3<f32>(0.5, 0.8, 0.3));
    let lightDir2 = normalize(vec3<f32>(-0.3, 0.5, -0.7));
    let lightDir3 = normalize(mousePos - hitPos + vec3<f32>(0.0, 2.0, 0.0));

    let diff = sat(dot(n, lightDir));
    let diff2 = sat(dot(n, lightDir2)) * 0.5;
    let diff3 = sat(dot(n, lightDir3)) * 0.3;

    let hal = normalize(lightDir - rd);
    let spec = pow(sat(dot(n, hal)), 32.0);
    let hal2 = normalize(lightDir2 - rd);
    let spec2 = pow(sat(dot(n, hal2)), 64.0) * 0.5;

    let fresnel = pow(1.0 - nDotV, 5.0);

    let melt = meltLevel(time);
    // Idea 6 — oxide-age ladder: crystal higher above the melt left it earlier,
    // so its oxide film is thicker and its colour has marched further round
    // the gold→magenta→blue→green ladder
    let oxideAge = sat((hitPos.y - melt) / 4.5);
    if (hitMat > 1.5) {
      // Idea 3 — liquid bismuth: dark pinkish mirror with bass capillary rings
      let rel = hitPos.xz - vec2<f32>(mousePos.x, 0.0);
      let r = length(rel);
      let ripple = sin(r * 9.0 - time * 3.0) * (0.15 + bass * 0.6) / (1.0 + r * 0.4);
      let rdir = rel / max(r, 1e-3);
      let mn = normalize(vec3<f32>(rdir.x * ripple * 0.08, 1.0, rdir.y * ripple * 0.08));
      let mv = sat(dot(mn, viewDir));
      let mSpec = pow(sat(dot(mn, normalize(lightDir - rd))), 90.0) + pow(sat(dot(mn, normalize(lightDir2 - rd))), 60.0) * 0.5;
      let mFres = 0.06 + 0.94 * pow(1.0 - mv, 5.0);
      let sheen = iridescent(mv, time * 0.2 + 1.3, audio) * iridescence * 0.12;
      col = vec3<f32>(0.11, 0.09, 0.1) + sheen + vec3<f32>(0.9, 0.85, 0.95) * mSpec * 0.8 + vec3<f32>(0.25, 0.3, 0.4) * mFres * 0.5;
    } else if (hitMat < 0.75 && mouseDown) {
      // Disrupted zone - scattered crystalline chaos
      let chaosCol = iridescent(nDotV, time * 0.5 + bass * 3.0, mid) * 2.0;
      col = chaosCol * (0.5 + diff * 0.3) + vec3<f32>(0.8, 0.6, 0.4) * spec * 0.5;
    } else {
      // Bismuth crystal surface
      let ageShift = oxideAge * 3.4;
      let ired = iridescent(nDotV, time * 0.3 + complexity + ageShift, audio) * iridescence;
      let riserIred = iridescent(nDotV, time * 0.3 + hitRiser * 6.28 + ageShift, audio) * iridescence;
      let baseMetal = vec3<f32>(0.15, 0.18, 0.22);
      var metal = baseMetal + mix(ired, riserIred, 0.45) * 0.8;

      // Edge = more iridescent (stepped crystal edges)
      let edge = pow(1.0 - nDotV, 4.0);
      metal = metal + ired * edge * 0.5;
      // Idea 1 — twin-boundary misfit glow
      metal = metal + riserIred * hitTwin * 0.5;

      // Specular highlights (glass-like)
      let specCol = vec3<f32>(0.9, 0.95, 1.0) * (spec + spec2) * 0.6;

      // Rim
      let rim = vec3<f32>(0.5, 0.6, 0.7) * fresnel * 0.6;

      col = metal * (0.3 + diff * 0.5 + diff2 * 0.2 + diff3 * 0.15);
      col = col + specCol + rim;

      // Audio-reactive shimmer on crystal faces
      col = col + ired * bass * 0.3;
      col += iridescent(nDotV, time + crystalShock * 2.0, treble) * crystalShock * (0.7 + mid * 0.5);
    }

    if (hitMat < 1.5) {
      // Ambient occlusion
      col = col * (0.4 + 0.6 * hitAo);

      // Deep shadows in crevices (valleys between stair steps)
      let cavity = pow(1.0 - nDotV, 2.0) * 0.4;
      col = col * (1.0 - cavity);

      // Idea 3 — hot meniscus where the crystal pierces the melt
      let above = hitPos.y - melt;
      let meniscus = exp(-above * above * 60.0);
      col += vec3<f32>(1.0, 0.55, 0.2) * meniscus * (0.6 + bass * 0.8);

      // Idea 4 — residual melt still glowing in the drained hopper hollows,
      // hotter for crystals close to the crucible
      let heat = exp(-max(above, 0.0) * 0.45);
      col += vec3<f32>(1.0, 0.36, 0.08) * hitHollow * hitHollow * heat * (0.35 + bass * 0.6);
    }

    // Depth fog - ethereal glow in abyssal chasms
    col = mix(col, vec3<f32>(0.02, 0.03, 0.05), 1.0 - exp(-0.015 * depth));
  } else {
    // Background - void with distant crystal glow
    col = vec3<f32>(0.005, 0.008, 0.012);
    let voidGlow = sat(0.03 / (length(p) * 0.3 + 0.01));
    col = col + vec3<f32>(0.1, 0.15, 0.2) * voidGlow * (0.2 + audio * 0.1);
    depth = 30.0;
  }

  // Volumetric fog along ray (simplified)
  var fogAccum = vec3<f32>(0.0);
  let fogSteps = 16;
  let fogStep = 20.0 / f32(fogSteps);
  for (var i: i32 = 0; i < fogSteps; i = i + 1) {
    let ft = f32(i) * fogStep + hash21(vec2<f32>(f32(i32(gid.x) + i * 73), f32(i32(gid.y) + i * 137))) * fogStep;
    let fp = ro + rd * ft;
    let cellSize = 2.5 / 1.5;
    let q = opRep(fp, vec3<f32>(cellSize));
    let cellId = floor(fp / cellSize);
    let h = hash3(cellId);
    let fogD = length(q) - 0.3;
    let fog = sat(0.5 - fogD) * exp(-ft * 0.08) * 0.03;
    let fogCol = vec3<f32>(0.2, 0.3, 0.5) * fog * (0.1 + bass * 0.2);
    fogAccum = fogAccum + fogCol;
  }
  col = col + fogAccum;

  let crystalSpark = step(0.985, hash21(vec2<f32>(f32(gid.x), f32(gid.y)) + vec2<f32>(floor(time * 18.0)))) * treble;
  col += vec3<f32>(0.75, 0.9, 1.2) * crystalSpark * (0.4 + crystalShock);

  // Exact A/C display history and one ACES application on the current path.
  let currentDisplay = acesToneMap(col * 1.2);
  let prev = textureLoad(dataTextureC, coord, 0);
  col = mix(prev.rgb * 0.95, currentDisplay, 0.23 + bassEnv * 0.035);

  let finalDepth = sat(0.95 - depth * 0.03);
  let hitCoverage = select(0.0, 0.68 + finalDepth * 0.24, hit);
  let fogCoverage = clamp(length(fogAccum) * 1.8 + crystalShock * 0.28 + crystalSpark * 0.2, 0.0, 0.88);
  let alpha = max(max(hitCoverage, fogCoverage), prev.a * 0.92);

  textureStore(writeTexture, coord, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(col.r, col.g, col.b, alpha));
}
