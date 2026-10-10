// ═══════════════════════════════════════════════════════════════════
//  Ethereal Glass-Flora Terrarium
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-10-10
//  Ideas: condensation droplet beads on terrarium glass shell; dew meniscus highlights on leaf-tip normals;
//         2nd pass (2026-10-10): capillary nectar lumen — a real inner capsule SDF in every
//         stem with travelling emissive packets, accumulated through the glass (revives the
//         near-zero Nectar Glow); spectral dispersion fringes — the per-channel refracted
//         directions rr/rg/rb now sample a per-channel background haze; also fixed a
//         pow(negative, 2.0) NaN in the background haze that persisted in history
//  A packing: ACES display RGBA in A
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

fn rot2D(a: f32) -> mat2x2<f32> {
  let c = cos(a); let s = sin(a);
  return mat2x2<f32>(c, -s, s, c);
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

// ─── Noise ───
fn valueNoise3D(p: vec3<f32>) -> f32 {
  let i = floor(p);
  var f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  var n = 0.0;
  for (var k: i32 = 0; k <= 1; k = k + 1) {
    for (var j: i32 = 0; j <= 1; j = j + 1) {
      for (var i0: i32 = 0; i0 <= 1; i0 = i0 + 1) {
        let h = hash3(i + vec3<f32>(f32(i0), f32(j), f32(k)));
        n = n + h * abs(1.0 - f32(i0) - f.x) * abs(1.0 - f32(j) - f.y) * abs(1.0 - f32(k) - f.z);
      }
    }
  }
  return n;
}

fn fbm3(p: vec3<f32>, octaves: i32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * valueNoise3D(pp);
    pp = pp * 2.0;
    a = a * 0.5;
  }
  return v;
}

// ─── SDF Primitives ───
fn sdSphere(p: vec3<f32>, r: f32) -> f32 { return length(p) - r; }

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

// ─── Refraction ───
fn refractRay(I: vec3<f32>, N: vec3<f32>, eta: f32) -> vec3<f32> {
  let cosi = dot(I, N);
  let cost2 = 1.0 - eta * eta * (1.0 - cosi * cosi);
  if (cost2 < 0.0) { return reflect(I, N); }
  return eta * I - (eta * cosi + sqrt(cost2)) * N;
}

fn fresnel(cosi: f32, eta: f32) -> f32 {
  var et = eta;
  if (cosi > 0.0) { et = 1.0 / eta; }
  let sin2t = et * et * (1.0 - cosi * cosi);
  if (sin2t > 1.0) { return 1.0; }
  let cost = sqrt(1.0 - sin2t);
  let rs = (et * abs(cosi) - cost) / (et * abs(cosi) + cost);
  let rp = (abs(cosi) - et * cost) / (abs(cosi) + et * cost);
  return 0.5 * (rs * rs + rp * rp);
}

// ─── ACES Tone Map ───
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Native idea 1: condensation droplet beads on the terrarium glass shell.
fn condensationDroplets(p: vec3<f32>, t: f32) -> f32 {
  let shellDist = abs(length(p) - 4.0);
  let onShell = smoothstep(0.12, 0.0, shellDist);
  let sph = normalize(p + vec3<f32>(0.0001));
  let dropGrid = vec2<f32>(atan2(sph.z, sph.x) * 8.0, sph.y * 14.0);
  let dropId = floor(dropGrid);
  let dropFract = fract(dropGrid) - vec2<f32>(0.5);
  let dropSeed = hash21(dropId);
  let dropR = 0.22 * (0.45 + dropSeed * 0.55);
  let drop = smoothstep(dropR, dropR * 0.55, length(dropFract)) * step(0.62, dropSeed);
  let slide = 0.5 + 0.5 * sin(t * 0.4 + dropSeed * 12.0);
  return onShell * drop * slide;
}

// Native idea 2: dew meniscus highlights on upward-facing leaf-tip normals.
fn dewMeniscus(n: vec3<f32>, p: vec3<f32>, t: f32) -> f32 {
  let tipUp = smoothstep(0.25, 0.82, n.y) * smoothstep(0.15, 0.75, p.y);
  let meniscus = pow(max(dot(n, normalize(vec3<f32>(0.15, 1.0, 0.08))), 0.0), 10.0);
  let bead = 0.5 + 0.5 * sin(p.x * 42.0 + p.z * 36.0 + t * 0.6);
  return tipUp * meniscus * bead;
}

// Shared by glassBranch and the lumen: the branch-local bent space.
fn branchBend(p: vec3<f32>, fi: f32) -> vec3<f32> {
  let bend = vec3<f32>(sin(p.y * 1.5 + fi * 3.0) * 0.2, 0.0, cos(p.y * 1.2 + fi * 2.5) * 0.15);
  return p + bend;
}

// Idea 2nd-pass A: capillary nectar lumen. A thin capsule SDF running down the inside of the
// stem (radius 0.022 < stem 0.06). Returns a soft emission density: tight halo around the
// lumen axis times travelling packets of nectar that climb the stem (faster on bass).
fn lumenBranch(bp: vec3<f32>, fi: f32, time: f32, bass: f32) -> f32 {
  let ld = sdCapsule(bp, vec3<f32>(0.0, -0.6, 0.0), vec3<f32>(0.0, 0.6, 0.0), 0.022);
  let phase = bp.y * 7.0 - time * (1.8 + bass * 2.0) + fi * 2.3;
  let packet = pow(0.5 + 0.5 * sin(phase), 3.0); // base in [0,1]
  return exp(-max(ld, 0.0) * 22.0) * (0.25 + 0.75 * packet);
}

// ─── Glass Flora Branch (L-system approximated via folding) ───
fn glassBranch(p: vec3<f32>, seed: f32, time: f32, audio: f32, floraDensity: f32) -> f32 {
  let fi = seed;
  // Bend toward mouse area (subtle)
  var bp = branchBend(p, fi);

  // Main stem
  let stem = sdCapsule(bp, vec3<f32>(0.0, -0.6, 0.0), vec3<f32>(0.0, 0.6, 0.0), 0.06 + audio * 0.01);

  // Branch nodes (spherical joints)
  var joints = 8.0;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    let ni = f32(i);
    let nodePos = vec3<f32>(sin(fi + ni * 2.1) * 0.2, -0.3 + ni * 0.4, cos(fi + ni * 1.7) * 0.2);
    let node = sdSphere(bp - nodePos, 0.08 + audio * 0.02);
    joints = smin(joints, node, 0.05);
  }

  // Petals (unfolding based on beat)
  var petals = 8.0;
  let beat = sin(time * 3.0 + fi * 5.0) * 0.5 + 0.5;
  let unfold = mix(0.3, 1.0, beat) * floraDensity;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    let pi = f32(i);
    let petalAngle = pi * 1.57 + fi * 3.0;
    let petalPos = vec3<f32>(cos(petalAngle) * 0.3 * unfold, 0.4 + sin(pi + time * 0.5) * 0.1, sin(petalAngle) * 0.3 * unfold);
    let petal = sdSphere(bp - petalPos, 0.1 * unfold + audio * 0.02);
    petals = smin(petals, petal, 0.08);
  }

  return smin(smin(stem, joints, 0.05), petals, 0.06);
}

// Mouse gravity well - flora bends toward cursor (shared by map and lumenField)
fn gravityWarp(p_in: vec3<f32>, time: f32, mousePos: vec3<f32>) -> vec3<f32> {
  var p = p_in;
  let md = p - mousePos;
  let mDist = length(md);
  let gravityRadius = 3.0;
  if (mDist < gravityRadius) {
    let bend = (1.0 - mDist / gravityRadius) * 0.2;
    p = p + normalize(md) * bend * sin(mDist * 3.0 + time);
  }
  return p;
}

// Idea 2nd-pass A: strongest nectar-lumen emission density over all flora at p.
// Only evaluated in the glass interior march (not in the main march / normals).
fn lumenField(p_in: vec3<f32>, time: f32, bass: f32, floraDensity: f32, mousePos: vec3<f32>) -> f32 {
  let p = gravityWarp(p_in, time, mousePos);
  var dens = 0.0;
  let numFlora = i32(floraDensity * 3.0 + 2.0);
  for (var i: i32 = 0; i < numFlora; i = i + 1) {
    let fi = f32(i);
    let pos = vec3<f32>(sin(fi * 2.7) * 1.5, -0.5 + fi * 0.3, cos(fi * 1.9) * 1.5);
    let bp = branchBend(p - pos, fi + 0.5);
    dens = max(dens, lumenBranch(bp, fi + 0.5, time, bass));
  }
  return dens;
}

// Idea 2nd-pass B: background haze as a function of direction, so refracted/dispersed
// rays can each look up their own colour. rd-direction call reproduces the old miss colour.
fn bgHaze(dir: vec3<f32>, time: f32, bass: f32) -> vec3<f32> {
  let s = sin(dir.x * 3.0 + time * 0.2) * sin(dir.y * 2.5 + time * 0.15);
  let haze = s * s; // was pow(s, 2.0): NaN for s < 0, which then persisted in history
  return vec3<f32>(0.01, 0.02, 0.015) + vec3<f32>(0.05, 0.1, 0.08) * haze * (0.1 + bass * 0.1);
}

// ─── Scene Map ───
struct MapResult {
  d: f32,
  mat: f32,
  glow: f32,
};

fn map(p_in: vec3<f32>, time: f32, audio: f32, bass: f32, floraDensity: f32,
       nectarGlow: f32, refractionIdx: f32, mousePos: vec3<f32>) -> MapResult {
  let p = gravityWarp(p_in, time, mousePos);

  // Multiple glass flora instances
  var flora = 8.0;
  let numFlora = i32(floraDensity * 3.0 + 2.0);
  for (var i: i32 = 0; i < numFlora; i = i + 1) {
    let fi = f32(i);
    let pos = vec3<f32>(sin(fi * 2.7) * 1.5, -0.5 + fi * 0.3, cos(fi * 1.9) * 1.5);
    let branch = glassBranch(p - pos, fi + 0.5, time, audio, floraDensity);
    flora = smin(flora, branch, 0.15);
  }

  // Terrarium container (subtle glass sphere)
  let container = sdSphere(p, 4.0) - 0.02;

  // Pollen particles (SDF spheres)
  var pollen = 8.0;
  let numPollen = 12;
  for (var i: i32 = 0; i < numPollen; i = i + 1) {
    let pi = f32(i);
    let pt = time * 0.3 + pi * 1.3;
    var pPos = vec3<f32>(sin(pt * 0.7 + pi * 2.0) * 1.2, sin(pt * 0.5 + pi) * 0.8, cos(pt * 0.6 + pi * 1.5) * 1.2);
    // Swarm toward mouse
    let pToMouse = mousePos - pPos;
    let pMouseDist = length(pToMouse);
    if (pMouseDist < 1.5) {
      pPos = pPos + normalize(pToMouse) * (1.5 - pMouseDist) * 0.3;
    }
    let pd = sdSphere(p - pPos, 0.03 + bass * 0.01);
    if (pd < pollen) { pollen = pd; }
  }

  // Combine
  let d = smin(flora, pollen, 0.05);
  var mat = 1.0; // glass flora
  var glow = 0.0;

  if (pollen < flora - 0.01) {
    mat = 2.0; // pollen
    glow = 0.5 + bass;
  } else {
    // Nectar flow glow along stems
    let nectar = sat(0.0 - flora) * 2.0;
    let flow = sin(p.y * 5.0 - time * 2.0 + bass * 3.0) * 0.5 + 0.5;
    glow = nectar * flow * nectarGlow;
  }

  return MapResult(d, mat, glow);
}

fn calcNormal(p: vec3<f32>, time: f32, audio: f32, bass: f32, floraDensity: f32,
              nectarGlow: f32, refractionIdx: f32, mousePos: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let m1 = map(p + e.xyy, time, audio, bass, floraDensity, nectarGlow, refractionIdx, mousePos);
  let m2 = map(p - e.xyy, time, audio, bass, floraDensity, nectarGlow, refractionIdx, mousePos);
  let m3 = map(p + e.yxy, time, audio, bass, floraDensity, nectarGlow, refractionIdx, mousePos);
  let m4 = map(p - e.yxy, time, audio, bass, floraDensity, nectarGlow, refractionIdx, mousePos);
  let m5 = map(p + e.yyx, time, audio, bass, floraDensity, nectarGlow, refractionIdx, mousePos);
  let m6 = map(p - e.yyx, time, audio, bass, floraDensity, nectarGlow, refractionIdx, mousePos);
  return normalize(vec3<f32>(m1.d - m2.d, m3.d - m4.d, m5.d - m6.d));
}

// ─── Chromatic Raymarch ───
fn raymarchChromatic(ro: vec3<f32>, rd: vec3<f32>, time: f32, audio: f32, bass: f32, mids: f32,
                     treble: f32, floraDensity: f32, nectarGlow: f32, refractionIdx: f32,
                     mousePos: vec3<f32>) -> vec4<f32> {
  var t = 0.0;
  var col = vec3<f32>(0.0);
  var alpha = 0.0;
  var hit = false;
  var hitGlow = 0.0;
  var hitMat = 0.0;

  let etaBase = refractionIdx;
  let chromaticSpread = 0.08 + treble * 0.05;
  let etaR = 1.0 / (etaBase - chromaticSpread);
  let etaG = 1.0 / etaBase;
  let etaB = 1.0 / (etaBase + chromaticSpread);

  for (var i: i32 = 0; i < 80; i = i + 1) {
    let p = ro + rd * t;
    let res = map(p, time, audio, bass, floraDensity, nectarGlow, refractionIdx, mousePos);
    let d = res.d;

    if (d < 0.003) {
      hit = true;
      hitGlow = res.glow;
      hitMat = res.mat;
      let n = calcNormal(p, time, audio, bass, floraDensity, nectarGlow, refractionIdx, mousePos);
      let cosi = dot(-rd, n);

      if (hitMat < 1.5) {
        // Glass flora with chromatic refraction
        let f = fresnel(cosi, etaBase);

        let rr = refractRay(rd, n, etaR);
        let rg = refractRay(rd, n, etaG);
        let rb = refractRay(rd, n, etaB);

        // Interior sample (simplified)
        var innerCol = vec3<f32>(0.0);
        let innerSteps = 12;
        var it = 0.05;
        var lumen = 0.0; // Idea 2nd-pass A: nectar emission accumulated through the glass
        for (var j: i32 = 0; j < innerSteps; j = j + 1) {
          let ip = p + rg * it;
          let ires = map(ip, time, audio, bass, floraDensity, nectarGlow, refractionIdx, mousePos);
          lumen = lumen + lumenField(ip, time, bass, floraDensity, mousePos) * 0.1;
          if (ires.d > 0.0) {
            innerCol = vec3<f32>(0.02, 0.04, 0.03) * (1.0 + 0.3 * sin(ip.y * 2.0 + time));
            innerCol = innerCol + vec3<f32>(0.0, 1.0, 0.8) * ires.glow * 0.5;
            break;
          }
          it = it + 0.08;
        }

        // Idea 2nd-pass A: lumen light seen through the stem wall (teal, magenta kick on bass)
        innerCol = innerCol + (vec3<f32>(0.0, 0.9, 0.7) + vec3<f32>(0.8, 0.0, 0.6) * bass) * lumen * nectarGlow * 2.0;

        // Idea 2nd-pass B: spectral dispersion — each channel sees the background through its
        // own refracted direction (rr/rb were computed but unused), so edges fringe.
        // The green-ray haze is added once; the per-channel difference (the fringe) is amplified.
        let hazeG = bgHaze(rg, time, bass);
        let dispersed = vec3<f32>(bgHaze(rr, time, bass).r, hazeG.g, bgHaze(rb, time, bass).b);
        innerCol = max(innerCol + hazeG + (dispersed - hazeG) * 30.0, vec3<f32>(0.0));

        // Nectar emissive glow
        let nectarCol = vec3<f32>(0.0, 0.9, 0.7) * hitGlow * 3.0
                      + vec3<f32>(0.8, 0.0, 0.6) * hitGlow * bass * 2.0;

        // Reflection
        let reflDir = reflect(rd, n);
        let reflCol = vec3<f32>(0.05, 0.08, 0.06) + vec3<f32>(0.1, 0.15, 0.1) * max(reflDir.y, 0.0);

        col.r = mix(innerCol.r * 0.9 + nectarCol.r, reflCol.r, f);
        col.g = mix(innerCol.g * 1.0 + nectarCol.g, reflCol.g, f);
        col.b = mix(innerCol.b * 1.1 + nectarCol.b, reflCol.b, f);

        // Chromatic edge tint
        let edgeTint = vec3<f32>(
          0.5 + 0.5 * cos(cosi * 6.0 + 0.0),
          0.5 + 0.5 * cos(cosi * 6.0 + 2.1),
          0.5 + 0.5 * cos(cosi * 6.0 + 4.2)
        );
        col = col + edgeTint * f * 0.25;

        let dew = dewMeniscus(n, p, time);
        col += vec3<f32>(0.85, 1.0, 0.95) * dew * (0.35 + treble * 0.4);

        alpha = sat(0.3 + f * 0.7 + dew * 0.15);
      } else {
        // Pollen - bright emissive spheres
        let pollenCol = vec3<f32>(0.9, 0.8, 0.4) * (1.0 + treble * 2.0);
        col = pollenCol + vec3<f32>(0.5, 0.3, 0.1) * bass * 0.5;
        alpha = 0.9;
      }
      break;
    }

    if (t > 25.0) { break; }
    t = t + d * 0.7;

    // Volumetric fog glow inside terrarium
    if (res.glow > 0.01 && t < 15.0) {
      let fogCol = vec3<f32>(0.0, 0.15, 0.1) * res.glow * 0.02 * exp(-t * 0.1);
      col = col + fogCol;
    }
  }

  if (!hit) {
    // Terrarium background with soft atmospheric haze
    col = bgHaze(rd, time, bass);
    alpha = 0.0;
  }

  // Condensation beads on the outer terrarium glass shell.
  let shellProbe = ro + rd * 7.8;
  let condense = condensationDroplets(shellProbe, time);
  col += vec3<f32>(0.75, 0.92, 1.0) * condense * (0.2 + mids * 0.15);
  alpha = sat(alpha + condense * 0.12);

  return vec4<f32>(col, alpha);
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

  // Parameters from zoom_params
  let floraDensity = mix(1.0, 10.0, clamp(u.zoom_params.x, 0.0, 1.0)) / 10.0;
  let nectarGlow = mix(0.0, 5.0, clamp(u.zoom_params.y, 0.0, 1.0)) / 5.0;
  let refractionIdx = mix(1.0, 2.5, clamp(u.zoom_params.z, 0.0, 1.0));
  let timeWarp = mix(0.1, 3.0, clamp(u.zoom_params.w, 0.0, 1.0));

  // Mouse handling: screen top = UP in 3D
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mouseUV = u.zoom_config.yz;
  let mouseY = mouseUV.y; // Flip Y
  let mousePos = vec3<f32>(
    (mouseUV.x * 2.0 - 1.0) * 3.0 * aspect,
    (mouseUV.y * 2.0 - 1.0) * 3.0,
    0.0
  );

  // Camera (inside terrarium looking at flora)
  let camDist = 3.5 + sin(time * 0.1 * timeWarp) * 0.3;
  let camAng = time * 0.12 * timeWarp + mouseUV.x * 0.4;
  let camHeight = sin(time * 0.08 * timeWarp) * 0.3 + mouseY * 0.4;
  let ro = vec3<f32>(cos(camAng) * camDist, camHeight, sin(camAng) * camDist);
  let ta = vec3<f32>(0.0, 0.0, 0.0);
  let ww = normalize(ta - ro);
  let uu = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), ww));
  let vv = cross(ww, uu);

  // Ray direction
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  let rd = normalize(p.x * uu + p.y * vv + 2.5 * ww);

  // Raymarch with chromatic dispersion
  let result = raymarchChromatic(ro, rd, time, audio, bass, mids, treble, floraDensity, nectarGlow, refractionIdx, mousePos);
  var col = result.rgb;
  var alpha = result.a;

  // Atmospheric fog inside terrarium
  let fog = exp(-alpha * 0.2);
  let fogCol = vec3<f32>(0.01, 0.03, 0.02) * (1.0 + bass * 0.1);
  col = mix(fogCol, col, fog);

  // Audio-reactive enhancements
  col = col + vec3<f32>(0.0, 0.15, 0.1) * bass * 0.15;
  col = col + vec3<f32>(0.1, 0.0, 0.08) * mids * 0.1;

  // Temporal persistence
  let prev = textureLoad(dataTextureC, coord, 0);
  col = mix(col, prev.rgb * 0.94, 0.03);

  // Tone map
  col = acesToneMap(col * 1.3);

  let finalAlpha = sat(max(alpha, prev.a * 0.92));
  let finalDepth = sat(0.95 - alpha * 0.4 + nectarGlow * 0.02);

  textureStore(writeTexture, coord, vec4<f32>(col, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(col.r, col.g, col.b, finalAlpha));
}
