// ═══════════════════════════════════════════════════════════════════
//  Chronos Monolith Resonator
//  Category: generative
//  Features: raymarched, KIFS, dark-matter, temporal-plasma, cosmic,
//            audio-reactive, mouse-driven, sub-surface-scattering, upgraded-rgba,
//            depth-aware, aces-tone-map, volumetric-ribbons
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
  let f = fract(p);
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
  let fractures = monolith + fractureNoise * 0.1;
  let isFractured = fractureNoise < 0.0 ? 1.0 : 0.0;

  // Inner crystal core (visible through fractures)
  let core = sdSphere(p, 0.8 + sin(time * 0.5) * 0.1);
  let coreGlow = (1.0 - sat(core / 0.3)) * coreResonance;

  // Temporal plasma ribbons - orbiting around monolith
  let orbitSpeed = time * 0.5 + audio * 0.3;
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
  let ribbons = min(min(ribbon1, ribbon2), ribbon3);

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
  let temporalFlow = mix(0.1, 1.5, u.zoom_params.x);
  let plasmaDensity = mix(0.0, 1.0, u.zoom_params.y);
  let monolithComplexity = mix(1.0, 5.0, u.zoom_params.z);
  let coreResonance = mix(0.0, 1.0, u.zoom_params.w);

  // Mouse in 3D
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mouseUV = u.zoom_config.yz;
  let mousePos = vec3<f32>(
    (mouseUV.x * 2.0 - 1.0) * 3.0 * aspect,
    (1.0 - mouseUV.y * 2.0) * 3.0,
    0.0
  );

  // Camera - orbiting the monolith
  let camDist = 5.0 + sin(time * 0.1) * 0.5;
  let camAng = time * 0.15 * temporalFlow + mouseUV.x * 0.5;
  let camHeight = sin(time * 0.08) * 0.5 + mouseUV.y * 0.3;
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
    } else if (hitMat < 1.5) {
      // Temporal plasma ribbon - cyan, violet, gold
      let ribbonPhase = hitPos.x * 2.0 + time * 2.0;
      let ribbonCol = vec3<f32>(
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
    let vt = f32(i) * 1.0 + hash21(vec2<f32>(f32(gid.x + i * 73), f32(gid.y + i * 137))) * 0.5;
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
  }
  col = col + volGlow;

  // Temporal persistence
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  col = mix(col, prev.rgb * 0.92, 0.03);

  // Tone map
  col = acesToneMap(col * 1.3);

  let alpha = sat(0.8 + length(volGlow) * 2.0);
  let finalDepth = sat(0.95 - depth * 0.03);

  textureStore(writeTexture, coord, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(col.r, col.g, col.b, alpha));
}