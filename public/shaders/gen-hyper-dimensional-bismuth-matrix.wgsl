// ═══════════════════════════════════════════════════════════════════
//  Hyper-Dimensional Bismuth-Matrix
//  Category: generative
//  Features: raymarched, KIFS, bismuth-crystal, hopper-steps,
//            iridescent, audio-reactive, mouse-driven, upgraded-rgba,
//            depth-aware, chromatic, volumetric-fog
//  Complexity: Very High
//  Created: 2026-06-28
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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
  for (var i: i32 = 0; i < steps; i = i + 1) {
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
};

fn map(p_in: vec3<f32>, time: f32, audio: f32, complexity: f32,
       growthRate: f32, gridDensity: f32, disruptionRadius: f32,
       mousePos: vec3<f32>) -> MapResult {
  var p = p_in;

  // Mouse disruption field - quantum scatter
  let md = p - mousePos;
  let mDist = length(md);
  if (mDist < disruptionRadius * 3.0) {
    let disrupt = (1.0 - mDist / (disruptionRadius * 3.0));
    let noiseDisrupt = hash3(p * 5.0 + time) * 2.0 - 1.0;
    p = p + normalize(md) * disrupt * noiseDisrupt * 0.4;
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

  // Interlocking stair-step extrusions
  let stairPhase = time * growthRate + cellHash * 3.14;
  let stairOffset = vec3<f32>(
    floor(rq.x / (crystalSize * 0.3)) * crystalSize * 0.15,
    floor(rq.y / (crystalSize * 0.3)) * crystalSize * 0.15,
    floor(rq.z / (crystalSize * 0.3)) * crystalSize * 0.15
  );
  let stair = sdBox(rq - stairOffset, vec3<f32>(crystalSize * 0.08, crystalSize * 0.12, crystalSize * 0.08));
  d = smin(d, stair, 0.04);

  // Frame edges
  let frame = sdBoxFrame(q, vec3<f32>(cellSize * 0.38), cellSize * 0.015);
  d = smin(d, frame, 0.03);

  // Material
  var mat = 1.0; // crystal
  if (mDist < disruptionRadius * 0.5) {
    mat = 0.5; // disrupted zone
  }

  let ao = sat(0.6 + 0.4 * hash3(cellId + vec3<f32>(0.5)));

  return MapResult(d, mat, ao);
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

  // Parameters
  let complexity = mix(1.5, 5.0, clamp(u.zoom_params.x, 0.0, 1.0));
  let iridescence = mix(0.3, 2.0, clamp(u.zoom_params.y, 0.0, 1.0));
  let growthRate = mix(0.2, 1.5, clamp(u.zoom_params.z, 0.0, 1.0));
  let disruptionRadius = mix(0.5, 3.0, clamp(u.zoom_params.w, 0.0, 1.0));

  // Mouse in 3D - screen top = UP, flip Y
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mouseUV = u.zoom_config.yz;
  let mouseY = mouseUV.y;
  let mousePos = vec3<f32>(
    (mouseUV.x * 2.0 - 1.0) * 3.0 * aspect,
    (mouseUV.y * 2.0 - 1.0) * 3.0,
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
  let rd = normalize(p.x * uu + p.y * vv + 2.5 * ww);

  // Raymarch
  var t = 0.0;
  var col = vec3<f32>(0.0);
  var hit = false;
  var hitPos = vec3<f32>(0.0);
  var hitMat = 0.0;
  var hitAo = 1.0;
  var depth = 0.0;

  for (var i: i32 = 0; i < 120; i = i + 1) {
    let pos = ro + rd * t;
    let res = map(pos, time, audio, complexity, growthRate, 1.5, disruptionRadius, mousePos);
    if (res.d < 0.005) {
      hit = true;
      hitPos = pos;
      hitMat = res.mat;
      hitAo = res.ao;
      depth = t;
      break;
    }
    if (t > 30.0) { break; }
    t = t + res.d * 0.7;
  }

  if (hit) {
    let n = calcNormal(hitPos, time, audio, complexity, growthRate, 1.5, disruptionRadius, mousePos);
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

    if (hitMat < 0.5) {
      // Disrupted zone - scattered crystalline chaos
      let chaosCol = iridescent(nDotV, time * 0.5 + bass * 3.0, mid) * 2.0;
      col = chaosCol * (0.5 + diff * 0.3) + vec3<f32>(0.8, 0.6, 0.4) * spec * 0.5;
    } else {
      // Bismuth crystal surface
      let ired = iridescent(nDotV, time * 0.3 + complexity, audio) * iridescence;
      let baseMetal = vec3<f32>(0.15, 0.18, 0.22);
      var metal = baseMetal + ired * 0.8;

      // Edge = more iridescent (stepped crystal edges)
      let edge = pow(1.0 - nDotV, 4.0);
      metal = metal + ired * edge * 0.5;

      // Specular highlights (glass-like)
      let specCol = vec3<f32>(0.9, 0.95, 1.0) * (spec + spec2) * 0.6;

      // Rim
      let rim = vec3<f32>(0.5, 0.6, 0.7) * fresnel * 0.6;

      col = metal * (0.3 + diff * 0.5 + diff2 * 0.2 + diff3 * 0.15);
      col = col + specCol + rim;

      // Audio-reactive shimmer on crystal faces
      col = col + ired * bass * 0.3;
    }

    // Ambient occlusion
    col = col * (0.4 + 0.6 * hitAo);

    // Deep shadows in crevices (valleys between stair steps)
    let cavity = pow(1.0 - nDotV, 2.0) * 0.4;
    col = col * (1.0 - cavity);

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

  // Temporal persistence
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let bassEnv = extraBuffer[0];
  extraBuffer[0] = mix(bassEnv, bass, 0.03);
  col = mix(col, prev.rgb * 0.96, 0.02 + extraBuffer[0] * 0.02);

  // Tone map
  col = acesToneMap(col * 1.2);

  let alpha = 1.0;
  let finalDepth = sat(0.95 - depth * 0.03);

  textureStore(writeTexture, coord, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(col.r, col.g, col.b, alpha));
}
