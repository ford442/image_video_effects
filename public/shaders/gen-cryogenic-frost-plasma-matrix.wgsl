// ═══════════════════════════════════════════════════════════════════
//  Cryogenic Frost-Plasma Matrix
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            volumetric-fog, KIFS-fractal, thermal-plasma, ice-refractive,
//            upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-19
//  Ideas: rime-plate terracing across frozen shells; plasma-tongue lick fronts around hot fracture edges;
//         crossed-polar grain mosaic from the KIFS fold signature (§12.2E fold count as material);
//         plasma core refracted through the ice per channel (§12.2F Cauchy dispersion)
//  A packing: HDR colour in A (C feedback mixes pre-ACES); ACES only on writeTexture
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// ═══════════════════════════════════════════════════════════════
//  CONSTANTS  (workgroup-size = 16×16×1 in .json)
// ═══════════════════════════════════════════════════════════════
const PI            : f32 = 3.14159265358979323846;
const MAX_STEPS     : i32 = 80;
const MAX_DIST      : f32 = 40.0;
const SURF_DIST     : f32 = 0.0015;
// Idea 6: ice Cauchy index n(λ) = A + B/λ² (λ in nm). Real ice has B ≈ 3.2e3 nm²;
// B is exaggerated ×6 so the red/blue fringe resolves at canvas scale.
const ICE_CAUCHY_A  : f32 = 1.3036;
const ICE_CAUCHY_B  : f32 = 19200.0;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══════════════════════════════════════════════════════════════
//  MATH HELPERS
// ═══════════════════════════════════════════════════════════════
fn rot(a: f32) -> mat2x2<f32> {
  let c = cos(a); let s = sin(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> f32 {
  var q = fract(p * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

fn noise3(p: vec3<f32>) -> f32 {
  let i = floor(p);
  var f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  let n = i.x + i.y * 57.0 + i.z * 113.0;
  return mix(
    mix(mix(hash3(i + vec3<f32>(0,0,0)), hash3(i + vec3<f32>(1,0,0)), f.x),
        mix(hash3(i + vec3<f32>(0,1,0)), hash3(i + vec3<f32>(1,1,0)), f.x), f.y),
    mix(mix(hash3(i + vec3<f32>(0,0,1)), hash3(i + vec3<f32>(1,0,1)), f.x),
        mix(hash3(i + vec3<f32>(0,1,1)), hash3(i + vec3<f32>(1,1,1)), f.x), f.y),
    f.z);
}

fn fbm(p: vec3<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for(var i = 0; i < 5; i++) {
    v += a * noise3(pp);
    pp = pp * 2.03 + vec3<f32>(1.7, 3.1, 5.3);
    a *= 0.5;
  }
  return v;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

// ═══════════════════════════════════════════════════════════════
//  KIFS FRACTAL
// ═══════════════════════════════════════════════════════════════
// Returns (distance, fold signature). The signature is Idea 5's grain identity.
// HEAD ran z = abs(z) before the x+y<0 mirror tests, so they could never fire and
// the "fractal" was the solid cube z = abs(z)*s - (s-1) fills; its length(z)/dr
// distance was then ~0 everywhere inside, which is the salt-and-pepper hit mask.
// The Sierpinski-tetrahedron folds now act (abs removed) and the bound is the
// standard (|z| - 1.5)/dr for that attractor.
fn kIFS(p: vec3<f32>, time: f32, complexity: f32) -> vec2<f32> {
  var z = p;
  var dr = 1.0;
  let scale = mix(2.0, 2.5, complexity);
  let iterations = i32(mix(4.0, 8.0, complexity));
  var folds = 0.0;

  for(var i = 0; i < iterations; i++) {
    // Only the first three generations name a grain, so grains stay facet-sized.
    let w = select(0.0, f32(i * 8 + 1), i < 3);
    if(z.x + z.y < 0.0) { let t = -z.y; z.y = -z.x; z.x = t; folds += 1.0 * w; }
    if(z.x + z.z < 0.0) { let t = -z.z; z.z = -z.x; z.x = t; folds += 2.0 * w; }
    if(z.y + z.z < 0.0) { let t = -z.z; z.z = -z.y; z.y = t; folds += 4.0 * w; }
    z = z * scale - vec3<f32>(1.0, 1.0, 1.0) * (scale - 1.0);
    dr = dr * scale;
  }
  return vec2<f32>((length(z) - 1.5) / abs(dr), folds);
}

// ═══════════════════════════════════════════════════════════════
//  SDF SCENE
// ═══════════════════════════════════════════════════════════════
struct MapResult {
  d: f32,
  mat: f32,   // 0 = ice, 1 = plasma
  glow: f32,
  iceD: f32,
  plasmaD: f32,
  folds: f32,
};

// Idea 1 — hoarfrost dendrites along the same abs-fold seams the KIFS uses.
fn hoarfrostDendrites(p: vec3<f32>, fracture: f32) -> f32 {
  var z = p;
  var feather = 0.0;
  for (var i = 0; i < 4; i = i + 1) {
    z = abs(z);
    let seam = min(abs(z.x - z.y), min(abs(z.x - z.z), abs(z.y - z.z)));
    let branch = exp(-seam * mix(48.0, 14.0, clamp(fracture, 0.0, 1.0)));
    feather = max(feather, branch * (1.0 - f32(i) * 0.2));
    z = z * 2.15 - vec3<f32>(1.05, 0.92, 1.12);
  }
  return feather * clamp(fracture, 0.0, 1.0);
}

fn map(p: vec3<f32>, time: f32, fracture: f32, plasmaHeat: f32,
       iceDensity: f32, audio: f32) -> MapResult {
  // Domain distortion from audio
  let warp = fbm(p * 0.5 + time * 0.1) * fracture * audio;
  let pp = p + vec3<f32>(warp, warp * 0.7, warp * 0.3);

  // KIFS ice structure
  let kRes = kIFS(pp * iceDensity, time, 0.6);
  let kDist = kRes.x / iceDensity * 0.85;

  // Plasma core inside
  let plasmaDist = length(pp * 0.4) - 0.3 * plasmaHeat;
  let plasmaGlow = 1.0 / (1.0 + plasmaDist * plasmaDist * 10.0);

  // Combine: ice shell with plasma interior
  let totalDist = smin(kDist, plasmaDist + 0.5, 0.3);

  var mat = 0.0;
  if(plasmaDist < kDist) { mat = 1.0; }

  return MapResult(totalDist, mat, plasmaGlow * plasmaHeat, kDist, plasmaDist, kRes.y);
}

fn calcNormal(p: vec3<f32>, time: f32, fracture: f32, plasmaHeat: f32,
              iceDensity: f32, audio: f32) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let m1 = map(p + e.xyy, time, fracture, plasmaHeat, iceDensity, audio).d;
  let m2 = map(p - e.xyy, time, fracture, plasmaHeat, iceDensity, audio).d;
  let m3 = map(p + e.yxy, time, fracture, plasmaHeat, iceDensity, audio).d;
  let m4 = map(p - e.yxy, time, fracture, plasmaHeat, iceDensity, audio).d;
  let m5 = map(p + e.yyx, time, fracture, plasmaHeat, iceDensity, audio).d;
  let m6 = map(p - e.yyx, time, fracture, plasmaHeat, iceDensity, audio).d;
  return normalize(vec3<f32>(m1-m2, m3-m4, m5-m6));
}

// ═══════════════════════════════════════════════════════════════
//  VOLUMETRIC FOG
// ═══════════════════════════════════════════════════════════════
fn fogDensity(p: vec3<f32>, time: f32, fogThickness: f32) -> f32 {
  let n = fbm(p * 0.3 + time * 0.05);
  return fogThickness * n * exp(-length(p) * 0.05);
}

// ═══════════════════════════════════════════════════════════════
//  MAIN
// ═══════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.z, u.config.w);
  let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
  if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

  var uv = (fragCoord - 0.5 * res) / res.y;
  uv.y = -uv.y; // row 0 is the top of the canvas
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Named controls use their JSON ranges directly.
  let fracture = clamp(u.zoom_params.x, 0.0, 1.0);
  let plasmaHeat = clamp(u.zoom_params.y, 0.0, 2.0);
  let iceDensity = clamp(u.zoom_params.z, 0.1, 3.0);
  let fogThickness = clamp(u.zoom_params.w, 0.0, 1.0);

  // HEAD smoothed bass through extraBuffer[133], which is re-uploaded as zero every
  // frame (and raced across threads), so it only ever delivered 0.08·bass.
  let bassSmooth = bass;

  let uv01 = (fragCoord + 0.5) / res;
  let aspect = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  var shock = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.8) {
      let front = abs(length((uv01 - ripple.xy) * aspect) - age * 0.22);
      shock += (1.0 - smoothstep(0.0, 0.028, front)) * (1.0 - age / 2.8);
    }
  }
  shock = min(shock, 2.0);
  let fractureReactive = fracture * (1.0 + bassSmooth * 0.65) + shock * 0.45;
  let plasmaReactive = plasmaHeat * (1.0 + mid * 0.35) + shock * 0.3;

  // Camera
  let mouseUV = u.zoom_config.yz;
  let mouseY = 1.0 - mouseUV.y;  // Flip Y: screen top = up
  let camAng = time * 0.1 + mouseUV.x * 0.5;
  let camDist = 3.4 - held * 0.6 + shock * 0.2;
  let ro = vec3<f32>(
    cos(camAng) * camDist,
    1.0 + mouseY * 1.6,
    sin(camAng) * camDist
  );
  let ta = vec3<f32>(0.0, 0.0, 0.0);
  let ww = normalize(ta - ro);
  let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
  let vv = cross(uu, ww);
  let rd = normalize(ww + uu * uv.x + vv * uv.y);

  // Raymarch
  var t = 0.0;
  var d = 0.0;
  var mat = 0.0;
  var glow = 0.0;
  var hit = false;
  // Idea 2 — sublimation sheath: vapor where the ice shell and plasma core meet.
  var sublimationSheath = 0.0;

  for(var i = 0; i < MAX_STEPS; i++) {
    let p = ro + rd * t;
    let res = map(p, time, fractureReactive, plasmaReactive, iceDensity, bassSmooth);
    d = res.d;
    mat = res.mat;
    glow = res.glow;
    let seam = abs(res.iceD - res.plasmaD);
    sublimationSheath += exp(-seam * (10.0 + fogThickness * 28.0)) * fogThickness * 0.035;
    if(d < SURF_DIST * max(t, 1.0)) { hit = true; break; }
    if(t > MAX_DIST) { break; }
    t += d * 0.8;
  }

  // Volumetric fog along ray
  var fogAccum = vec3<f32>(0.0);
  var fogT = 0.0;
  for(var i = 0; i < 16; i++) {
    let fp = ro + rd * fogT;
    let fd = fogDensity(fp, time, fogThickness);
    let fogCol = vec3<f32>(0.6, 0.8, 1.0) * fd * 0.1;
    fogAccum += fogCol * (1.0 - fogAccum.x);
    fogT += 0.5;
    if(fogT > min(t, MAX_DIST)) { break; }
  }

  // Shading
  var col = vec3<f32>(0.0);
  // Idea 6 helper: plasma core radius in world units (plasmaDist = 0.4|p| - 0.3·heat).
  let coreR = 0.75 * plasmaReactive;
  let plasmaTint = mix(vec3<f32>(1.0, 0.2, 0.8), vec3<f32>(1.0, 0.8, 0.1), clamp(bassSmooth * 0.8, 0.0, 1.0));
  if(hit) {
    let p = ro + rd * t;
    let mres = map(p, time, fractureReactive, plasmaReactive, iceDensity, bassSmooth);
    let n = calcNormal(p, time, fractureReactive, plasmaReactive, iceDensity, bassSmooth);

    // Lighting
    let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
    let diff = max(dot(n, lightDir), 0.0);
    let spec = pow(max(dot(reflect(-lightDir, n), -rd), 0.0), 64.0);
    let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

    if(mat < 0.5) {
      // Ice material
      let iceCol = vec3<f32>(0.7, 0.9, 1.0);
      let refractCol = vec3<f32>(0.3, 0.7, 0.9) * fbm(p * 2.0);
      col = iceCol * (diff * 0.5 + 0.3) + spec * vec3<f32>(1.0) * 0.5 + refractCol * fresnel;
      let frostFeather = hoarfrostDendrites(p * iceDensity, fracture);
      col += vec3<f32>(0.82, 0.94, 1.0) * frostFeather * (0.55 + fresnel);
      // Idea 3: rime-plate terracing on frozen shells.
      let plate = 0.5 + 0.5 * sin(length(p) * 26.0 + fbm(p * 4.0) * 5.0 - time * 0.6);
      col += vec3<f32>(0.68, 0.9, 1.0) * pow(max(plate, 0.0), 6.0) * (0.22 + fracture * 0.2);
      // ── Idea 5: crossed-polar grain mosaic (§12.2E fold count as material).
      // The fold signature names the grain; it sets the c-axis angle φ and the
      // retardation Γ (nm). Between crossed polarisers a birefringent grain passes
      // I(λ) = sin²(2φ)·sin²(πΓ/λ), the Michel-Lévy interference colour. Fracture and
      // bass add strain birefringence.
      let grainA = fract(mres.folds * 0.6180340);
      let grainB = fract(mres.folds * 0.3819660 + 0.37);
      let phi = grainA * PI;
      let gammaNm = (260.0 + 980.0 * grainB) * (1.0 + fractureReactive * 0.35);
      let lambda = vec3<f32>(650.0, 550.0, 450.0);
      let retard = sin(PI * gammaNm / lambda);
      let mosaic = sin(2.0 * phi) * sin(2.0 * phi) * retard * retard;
      col = mix(col, mosaic * (0.45 + diff * 0.9) + spec * 0.4, 0.7);

      // ── Idea 6: the plasma core seen through the ice (§12.2F Cauchy dispersion).
      // Each channel refracts with its own n(λ); the closest approach of the
      // refracted ray to the core lights that channel, so the core shows in the
      // facets as a lensed ghost with a red-inside / blue-outside fringe.
      let nIce = vec3<f32>(ICE_CAUCHY_A) + ICE_CAUCHY_B / (lambda * lambda);
      var seen = vec3<f32>(0.0);
      for (var c = 0; c < 3; c = c + 1) {
        let rr = refract(rd, n, 1.0 / nIce[c]);
        let sAlong = max(-dot(p, rr), 0.0);
        let miss = length(p + rr * sAlong);
        seen[c] = exp(-max(miss - coreR * 0.55, 0.0) * 5.0) * step(0.001, sAlong);
      }
      col += plasmaTint * seen * (1.0 - fresnel) * (0.35 + plasmaHeat * 0.55);
    } else {
      // Plasma material
      let plasmaCol = mix(
        vec3<f32>(1.0, 0.2, 0.8),
        vec3<f32>(1.0, 0.8, 0.1),
        glow * bassSmooth
      );
      col = plasmaCol * (diff * 0.8 + 0.5) + spec * vec3<f32>(1.0, 0.9, 0.7) * 0.8;
      col += glow * vec3<f32>(2.0, 0.5, 1.0) * plasmaReactive;
      // Idea 4: plasma tongues licking around fracture edges.
      let tongue = pow(max(sin(atan2(p.y, p.x) * 8.0 + time * 3.4 + p.z * 2.0), 0.0), 5.0);
      let seamHot = exp(-abs(mres.iceD - mres.plasmaD) * 7.0);
      col += vec3<f32>(1.0, 0.46, 0.12) * tongue * seamHot * (0.22 + plasmaHeat * 0.3);
    }

    // Distance fade
    col *= exp(-t * 0.03);

  } else {
    // Idea 6, undeviated: rays slipping through the tetrahedral gaps see the core directly.
    let sAlong = max(-dot(ro, rd), 0.0);
    let miss = length(ro + rd * sAlong);
    col = plasmaTint * exp(-max(miss - coreR * 0.55, 0.0) * 5.0) * (0.35 + plasmaHeat * 0.55);
    col += vec3<f32>(0.004, 0.012, 0.03); // frozen void
  }

  // Add fog and the ice/plasma sublimation sheath
  col = mix(col, fogAccum, clamp(length(fogAccum), 0.0, 1.0));
  col += vec3<f32>(0.45, 0.82, 1.0) * sublimationSheath;

  // Audio flash
  col += vec3<f32>(0.1, 0.3, 0.5) * bassSmooth * bassSmooth * 0.2;
  col += vec3<f32>(0.2, 0.75, 1.0) * shock * (0.35 + treble * 0.8);
  col += vec3<f32>(1.0, 0.22, 0.75) * held * exp(-length((uv01 - u.zoom_config.yz) * aspect) * 7.0) * (0.2 + mid * 0.4);

  // Exact temporal feedback in HDR, then ACES display mapping.
  let prevCol = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
  col = mix(prevCol, col, 0.3);
  let mapped = acesToneMap(max(col, vec3<f32>(0.0)) * 1.15);
  let fogEnergy = clamp(length(fogAccum), 0.0, 1.0);
  // Semantic alpha: the frozen void is an opaque-ish medium (HEAD's 0.03 miss alpha
  // composited the whole frame as a pale wash), ice/plasma hits are solid.
  let alpha = clamp(select(0.86, 0.97, hit) + fogEnergy * 0.08 + glow * 0.02 + shock * 0.1 + sublimationSheath * 0.05, 0.0, 1.0);

  // Write
  let outCoords = vec2<i32>(global_id.xy);
  textureStore(writeTexture, outCoords, vec4<f32>(mapped, alpha));
  textureStore(writeDepthTexture, outCoords, vec4<f32>(1.0 - clamp(t / MAX_DIST, 0.0, 1.0), 0.0, 0.0, 1.0));
  textureStore(dataTextureA, outCoords, vec4<f32>(col, alpha));
}
