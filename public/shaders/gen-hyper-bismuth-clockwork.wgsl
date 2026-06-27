// ═══════════════════════════════════════════════════════════════════
//  Hyper-Bismuth Clockwork
//  Category: generative
//  Features: raymarched, KIFS, bismuth-crystal, iridescent, audio-reactive,
//            mouse-driven, clockwork-mechanical, upgraded-rgba, depth-aware,
//            aces-tone-map, ambient-occlusion
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

// ─── Math Helpers ───
fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash3(p: vec3<f32>) -> f32 {
  let q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
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

// ─── ACES Tone Map ───
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ─── Bismuth stepped crystal SDF ───
fn sdBismuthStep(p: vec3<f32>, size: f32, steps: i32) -> f32 {
  var d = sdBox(p, vec3<f32>(size));
  var s = size * 0.5;
  var pp = p;
  for (var i: i32 = 0; i < steps; i = i + 1) {
    let offset = vec3<f32>(s * 0.3, -s * 0.2, s * 0.1);
    pp = pp - offset;
    let inner = sdBox(pp, vec3<f32>(s * 0.85, s * 0.9, s * 0.85));
    d = max(d, -inner); // Subtract inner = hollow stepped
    s = s * 0.7;
  }
  return d;
}

// ─── KIFS Bismuth ───
fn sdKIFSBismuth(p: vec3<f32>, time: f32, complexity: f32, clockSpeed: f32) -> f32 {
  var z = p;
  var dr = 1.0;
  let rot = rot3Y(time * clockSpeed * 0.2) * rot3X(time * clockSpeed * 0.15);
  
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
       clockSpeed: f32, gridDensity: f32, mousePos: vec3<f32>) -> MapResult {
  var p = p_in;

  // Magnetic singularity cursor
  let md = p - mousePos;
  let mDist = length(md);
  let magRadius = 2.5;
  if (mDist < magRadius) {
    let pull = (1.0 - mDist / magRadius) * 1.5;
    p = p + normalize(md) * pull * 0.3;
  }

  // Grid cell
  let cell = 2.0 / gridDensity;
  let q = opRep(p, vec3<f32>(cell));
  let cellId = floor(p / cell);
  let cellHash = hash3(cellId);

  // Audio-reactive clockwork motion
  let phase = time * clockSpeed + cellHash * 6.28 + audio * 2.0;
  let rotation = rot3Y(phase * 0.5) * rot3X(phase * 0.3);
  let rq = rotation * q;

  // Stepped bismuth crystal in each cell
  let stepCount = i32(2.0 + complexity * 0.5);
  let bismuth = sdBismuthStep(rq, cell * 0.35, stepCount);

  // KIFS structure at center
  let kifs = sdKIFSBismuth(q, time + cellHash * 10.0, complexity, clockSpeed);

  // Blend: bismuth + KIFS
  var d = smin(bismuth, kifs, 0.15);

  // Interlocking gear teeth
  let gearPhase = time * clockSpeed * 2.0 + cellHash * 3.14;
  let gearOffset = vec3<f32>(
    cos(gearPhase) * cell * 0.15,
    sin(gearPhase * 1.3) * cell * 0.1,
    cos(gearPhase * 0.7) * cell * 0.12
  );
  let gear = sdBox(q - gearOffset, vec3<f32>(cell * 0.05, cell * 0.15, cell * 0.05));
  d = smin(d, gear, 0.05);

  // Frame edges
  let frame = sdBoxFrame(q, vec3<f32>(cell * 0.38), cell * 0.02);
  d = smin(d, frame, 0.03);

  // Material
  var mat = 1.0; // crystal
  if (mDist < magRadius * 0.5) {
    mat = 0.5; // molten core
  }

  // Ambient occlusion proxy
  let ao = sat(0.7 + 0.3 * hash3(cellId + vec3<f32>(0.5)));

  return MapResult(d, mat, ao);
}

fn calcNormal(p: vec3<f32>, time: f32, audio: f32, complexity: f32,
              clockSpeed: f32, gridDensity: f32, mousePos: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let m1 = map(p + e.xyy, time, audio, complexity, clockSpeed, gridDensity, mousePos);
  let m2 = map(p - e.xyy, time, audio, complexity, clockSpeed, gridDensity, mousePos);
  let m3 = map(p + e.yxy, time, audio, complexity, clockSpeed, gridDensity, mousePos);
  let m4 = map(p - e.yxy, time, audio, complexity, clockSpeed, gridDensity, mousePos);
  let m5 = map(p + e.yyx, time, audio, complexity, clockSpeed, gridDensity, mousePos);
  let m6 = map(p - e.yyx, time, audio, complexity, clockSpeed, gridDensity, mousePos);
  return normalize(vec3<f32>(m1.d - m2.d, m3.d - m4.d, m5.d - m6.d));
}

// ─── Iridescent thin-film color ───
fn iridescent(nDotV: f32, shift: f32) -> vec3<f32> {
  let t = nDotV * 3.14159 + shift;
  return vec3<f32>(
    0.5 + 0.5 * cos(t + 0.0),
    0.5 + 0.5 * cos(t + 2.09),
    0.5 + 0.5 * cos(t + 4.18)
  );
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
  let complexity = mix(1.0, 5.0, u.zoom_params.x);
  let clockSpeed = mix(0.2, 2.0, u.zoom_params.y);
  let iridescence = mix(0.2, 2.0, u.zoom_params.z);
  let gridDensity = mix(1.0, 3.0, u.zoom_params.w);

  // Mouse position in 3D
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mouseUV = u.zoom_config.yz;
  let mouseY = 1.0 - mouseUV.y;  // Flip Y: screen top = up
  let mousePos = vec3<f32>(
    (mouseUV.x * 2.0 - 1.0) * 3.0 * aspect,
    (mouseUV.y * 2.0 - 1.0) * 3.0,  // 3D position: screen top = +Y (up)
    0.0
  );

  // Camera - orbiting through the clockwork
  let camDist = 4.0 + sin(time * 0.1) * 0.5;
  let camAng = time * 0.12 + mouseUV.x * 0.4;
  let camHeight = mouseY * 1.0;
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

  for (var i: i32 = 0; i < 100; i = i + 1) {
    let pos = ro + rd * t;
    let res = map(pos, time, audio, complexity, clockSpeed, gridDensity, mousePos);

    if (res.d < 0.005) {
      hit = true;
      hitPos = pos;
      hitMat = res.mat;
      hitAo = res.ao;
      depth = t;
      break;
    }

    if (t > 25.0) { break; }
    t = t + res.d * 0.7;
  }

  if (hit) {
    let n = calcNormal(hitPos, time, audio, complexity, clockSpeed, gridDensity, mousePos);
    let viewDir = -rd;
    let nDotV = sat(dot(n, viewDir));

    let lightDir = normalize(vec3<f32>(0.5, 0.8, 0.3));
    let lightDir2 = normalize(vec3<f32>(-0.3, 0.5, -0.7));

    let diff = sat(dot(n, lightDir));
    let diff2 = sat(dot(n, lightDir2)) * 0.5;
    let spec = pow(sat(dot(reflect(-lightDir, n), viewDir)), 32.0);
    let spec2 = pow(sat(dot(reflect(-lightDir2, n), viewDir)), 64.0) * 0.5;

    if (hitMat < 0.5) {
      // Molten core
      let coreCol = vec3<f32>(1.0, 0.9, 0.7) * (1.0 + audio * 2.0);
      let innerGlow = vec3<f32>(0.8, 0.4, 0.1) * (1.0 - nDotV) * 2.0;
      col = coreCol * (0.6 + diff * 0.4) + innerGlow;
    } else {
      // Bismuth crystal surface
      let ired = iridescent(nDotV, time * 0.5 + complexity) * iridescence;
      let baseMetal = vec3<f32>(0.15, 0.18, 0.22);
      let metal = baseMetal + ired * 0.6;

      // Sharp stepped edges = more iridescent
      let edge = pow(1.0 - nDotV, 4.0);
      metal = metal + ired * edge * 0.4;

      col = metal * (0.3 + diff * 0.5 + diff2 * 0.2);
      col = col + vec3<f32>(0.6, 0.7, 0.8) * (spec + spec2) * 0.5;

      // Audio-reactive shimmer
      col = col + ired * bass * 0.2;
    }

    // Ambient occlusion
    col = col * (0.4 + 0.6 * hitAo);

    // Deep shadows in crevices
    let cavity = pow(1.0 - nDotV, 2.0) * 0.3;
    col = col * (1.0 - cavity);
  } else {
    // Background - void with distant clockwork glow
    col = vec3<f32>(0.01, 0.02, 0.03);
    let voidGlow = sat(0.05 / (length(p) * 0.5 + 0.02));
    col = col + vec3<f32>(0.1, 0.15, 0.2) * voidGlow * (0.2 + audio * 0.1);
    depth = 25.0;
  }

  // Temporal persistence
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  col = mix(col, prev.rgb * 0.94, 0.04);

  // Tone map
  col = acesToneMap(col * 1.2);

  let alpha = sat(0.7 + (1.0 - depth / 10.0) * 0.3);
  let finalDepth = sat(0.95 - depth * 0.04);

  textureStore(writeTexture, coord, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(col.r, col.g, col.b, alpha));
}