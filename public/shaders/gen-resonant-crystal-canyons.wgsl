// ═══════════════════════════════════════════════════════════════════
//  Resonant Crystal-Canyons
//  Category: generative
//  Features: raymarched, crystal-terrain, chromatic-dispersion, plasma-rivers,
//            audio-reactive, mouse-driven, thin-film-interference, upgraded-rgba,
//            depth-aware, aces-tone-map, domain-warped
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

fn rot2D(a: f32) -> mat2x2<f32> {
  let c = cos(a); let s = sin(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn rot3Y(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
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
  for (var i: i32 = 0; i < 5; i = i + 1) {
    v = v + a * noise3D(pp);
    pp = pp * 2.03;
    a = a * 0.5;
  }
  return v;
}

fn fbmDomainWarp(p: vec3<f32>, time: f32) -> vec3<f32> {
  var q = vec3<f32>(
    fbm(p + vec3<f32>(0.0, 0.0, time * 0.1)),
    fbm(p + vec3<f32>(5.2, 1.3, time * 0.08)),
    fbm(p + vec3<f32>(1.7, 9.2, time * 0.12))
  );
  var r = vec3<f32>(
    fbm(p + 4.0 * q + vec3<f32>(1.7, 9.2, 0.0)),
    fbm(p + 4.0 * q + vec3<f32>(8.3, 2.8, 0.0)),
    fbm(p + 4.0 * q + vec3<f32>(2.3, 5.4, 0.0))
  );
  return p + 2.0 * r;
}

// ─── SDF ───
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
  let q = abs(p) - b;
  return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
  let a = abs(p);
  return (a.x + a.y + a.z - s) * 0.57735027;
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

// ─── Thin-film interference (bismuth-like) ───
fn thinFilmColor(cosTheta: f32, thickness: f32) -> vec3<f32> {
  let phase = thickness * 3.14159 * 2.0 * cosTheta;
  return vec3<f32>(
    0.5 + 0.5 * cos(phase + 0.0),
    0.5 + 0.5 * cos(phase + 2.09),
    0.5 + 0.5 * cos(phase + 4.18)
  );
}

// ─── Scene Map: Crystal Canyon Terrain ───
struct MapResult {
  d: f32,
  mat: f32,    // 0 = crystal wall, 1 = plasma river, 2 = floor
  glow: f32,
};

fn map(p_in: vec3<f32>, time: f32, audio: f32, crystalDensity: f32,
       plasmaGlow: f32, refractiveIndex: f32, mousePos: vec2<f32>) -> MapResult {
  var p = p_in;

  // Mouse warps terrain locally
  let mouseWorld = vec3<f32>(mousePos.x * 5.0, 0.0, mousePos.y * 5.0);
  let md = p - mouseWorld;
  let mDist = length(md.xz);
  if (mDist < 3.0) {
    let warp = (1.0 - mDist / 3.0) * 0.5;
    p.y = p.y + warp * sin(mDist * 2.0 + time);
    p.x = p.x + warp * md.x * 0.3;
  }

  // Domain-warped canyon terrain
  var wp = fbmDomainWarp(p * crystalDensity * 0.3, time);

  // Canyon walls = sliced crystal prisms
  let wallY = wp.y * 3.0 + fbm(p * 0.5 + vec3<f32>(0.0, time * 0.1, 0.0)) * 1.5;
  let wallOffset = sin(p.z * 0.3 + time * 0.2) * 2.0 + cos(p.x * 0.2) * 1.5;
  let wallL = sdBox(p - vec3<f32>(wallOffset - 2.0, wallY * 0.5, 0.0), vec3<f32>(0.5, 4.0, 10.0));
  let wallR = sdBox(p - vec3<f32>(wallOffset + 2.0, wallY * 0.5, 0.0), vec3<f32>(0.5, 4.0, 10.0));

  // Crystal protrusions
  let crystalP = p;
  let crystalPhase = time * 0.3 + audio * 2.0;
  let crystal1 = sdOctahedron(
    crystalP - vec3<f32>(wallOffset - 1.5, 1.0 + sin(crystalPhase) * 0.3, 0.0),
    0.8 + audio * 0.2
  );
  let crystal2 = sdOctahedron(
    crystalP - vec3<f32>(wallOffset + 1.5, 0.5 + cos(crystalPhase * 1.3) * 0.2, 2.0),
    0.6 + audio * 0.15
  );
  let crystal3 = sdBox(
    crystalP - vec3<f32>(wallOffset - 2.0, 2.0, -1.5),
    vec3<f32>(0.3, 0.6 + sin(crystalPhase * 0.7) * 0.2, 0.3)
  );

  // Canyon floor
  let floorH = -1.0 + fbm(p.xz * 0.5) * 0.5;
  let floor = p.y - floorH;

  // Combine walls with crystals
  var walls = smin(wallL, wallR, 0.5);
  walls = smin(walls, crystal1, 0.3);
  walls = smin(walls, crystal2, 0.3);
  walls = smin(walls, crystal3, 0.2);

  // Plasma river = bottom channel
  let riverBed = -1.5 + sin(p.z * 0.2 + time * 0.1) * 0.3;
  let river = p.y - riverBed;
  let riverWidth = 1.5 + cos(p.z * 0.15) * 0.5;
  let riverChannel = abs(p.x - wallOffset) - riverWidth;
  let riverSurface = max(river, riverChannel);

  // Combine: floor first, then walls, then river carved out
  var d = smin(floor, walls, 0.3);
  d = smin(d, riverSurface, 0.2);

  // Determine material
  var mat = 0.0; // crystal
  var glow = 0.0;

  if (riverSurface < 0.1 && riverChannel < 0.0) {
    mat = 1.0; // plasma river
    glow = plasmaGlow * (1.0 + audio * 0.5);
  }
  if (p.y < floorH + 0.1) {
    mat = 2.0; // floor
  }

  return MapResult(d, mat, glow);
}

fn calcNormal(p: vec3<f32>, time: f32, audio: f32, crystalDensity: f32,
              plasmaGlow: f32, refractiveIndex: f32, mousePos: vec2<f32>) -> vec3<f32> {
  let e = vec2<f32>(0.005, 0.0);
  let m1 = map(p + e.xyy, time, audio, crystalDensity, plasmaGlow, refractiveIndex, mousePos);
  let m2 = map(p - e.xyy, time, audio, crystalDensity, plasmaGlow, refractiveIndex, mousePos);
  let m3 = map(p + e.yxy, time, audio, crystalDensity, plasmaGlow, refractiveIndex, mousePos);
  let m4 = map(p - e.yxy, time, audio, crystalDensity, plasmaGlow, refractiveIndex, mousePos);
  let m5 = map(p + e.yyx, time, audio, crystalDensity, plasmaGlow, refractiveIndex, mousePos);
  let m6 = map(p - e.yyx, time, audio, crystalDensity, plasmaGlow, refractiveIndex, mousePos);
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
  let crystalDensity = mix(0.2, 1.0, u.zoom_params.x);
  let plasmaGlow = mix(0.0, 1.5, u.zoom_params.y);
  let refractiveIndex = mix(1.0, 2.0, u.zoom_params.z);
  let audioReactivity = mix(0.0, 2.0, u.zoom_params.w);

  // Mouse
  let mouseRaw = u.zoom_config.yz * 2.0 - 1.0;
  let mousePos = vec2<f32>(mouseRaw.x, -mouseRaw.y);  // Flip Y: screen top = up

  // Camera: sweeping through canyon
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let camSpeed = 0.5 + audioReactivity * audio * 0.3;
  let camZ = time * camSpeed;
  let camX = sin(time * 0.2) * 2.0 + mousePos.x * 1.0;
  let camY = 1.5 + sin(time * 0.15) * 0.5 + mousePos.y * 0.5;
  let ro = vec3<f32>(camX, camY, camZ);

  // Look ahead + slightly down into canyon
  let lookAt = vec3<f32>(camX * 0.5, 0.0, camZ + 5.0);
  let ww = normalize(lookAt - ro);
  let uu = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), ww));
  let vv = cross(ww, uu);

  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  let rd = normalize(p.x * uu + p.y * vv + 2.0 * ww);

  // Raymarch
  var t = 0.0;
  var col = vec3<f32>(0.0);
  var hit = false;
  var hitPos = vec3<f32>(0.0);
  var hitMat = 0.0;
  var hitGlow = 0.0;
  var depth = 0.0;

  for (var i: i32 = 0; i < 120; i = i + 1) {
    let pos = ro + rd * t;
    let res = map(pos, time, audio, crystalDensity, plasmaGlow, refractiveIndex, mousePos);

    if (res.d < 0.005) {
      hit = true;
      hitPos = pos;
      hitMat = res.mat;
      hitGlow = res.glow;
      depth = t;
      break;
    }

    if (t > 60.0) { break; }
    t = t + res.d * 0.6;
  }

  if (hit) {
    let n = calcNormal(hitPos, time, audio, crystalDensity, plasmaGlow, refractiveIndex, mousePos);
    let viewDir = -rd;
    let nDotV = sat(dot(n, viewDir));

    let lightDir = normalize(vec3<f32>(0.3, 0.8, 0.5));
    let diff = sat(dot(n, lightDir));
    let spec = pow(sat(dot(reflect(-lightDir, n), viewDir)), 32.0);

    if (hitMat < 0.5) {
      // Crystal wall - thin film iridescence
      let film = thinFilmColor(nDotV, refractiveIndex * 2.0) * 0.8;
      let crystalBase = vec3<f32>(0.8, 0.9, 1.0) * 0.3;
      let crystalCol = crystalBase + film * (0.5 + audioReactivity * audio * 0.3);

      // Chromatic edge dispersion
      let edge = pow(1.0 - nDotV, 3.0);
      let chromatic = vec3<f32>(
        0.5 + 0.5 * cos(edge * 10.0 + 0.0),
        0.5 + 0.5 * cos(edge * 10.0 + 2.1),
        0.5 + 0.5 * cos(edge * 10.0 + 4.2)
      ) * edge * 0.3;

      col = crystalCol * (0.4 + diff * 0.6) + vec3<f32>(0.5, 0.6, 0.7) * spec * 0.5;
      col = col + chromatic;

      // Subsurface glow from nearby plasma
      col = col + vec3<f32>(0.2, 0.05, 0.4) * hitGlow * 0.2;
    } else if (hitMat < 1.5) {
      // Plasma river - bioluminescent
      let plasmaCol = vec3<f32>(0.3, 0.0, 0.5) * (0.5 + hitGlow * 2.0);
      let surface = vec3<f32>(0.1, 0.0, 0.2) * diff;
      let boil = fbm(hitPos * 3.0 + vec3<f32>(0.0, time * 2.0, 0.0)) * 0.5;
      col = plasmaCol + surface + vec3<f32>(0.5, 0.2, 0.8) * boil * (0.5 + audio * 0.5);
      col = col + vec3<f32>(0.3, 0.1, 0.5) * spec * 0.3;
    } else {
      // Canyon floor
      let floorCol = vec3<f32>(0.05, 0.04, 0.06);
      col = floorCol * (0.3 + diff * 0.4) + vec3<f32>(0.1, 0.08, 0.12) * spec * 0.2;
      // Reflected plasma glow
      col = col + vec3<f32>(0.2, 0.05, 0.3) * hitGlow * 0.15;
    }

    // Ambient occlusion (approximate)
    let ao = sat(0.5 + 0.5 * n.y);
    col = col * (0.4 + 0.6 * ao);
  } else {
    // Sky / void above canyon
    col = vec3<f32>(0.005, 0.01, 0.02) + vec3<f32>(0.01, 0.02, 0.04) * max(rd.y, 0.0);
    // Distant crystal glow on horizon
    col = col + vec3<f32>(0.1, 0.15, 0.2) * sat(0.05 / (abs(rd.y) + 0.02)) * 0.5;
    depth = 60.0;
  }

  // Volumetric plasma glow in the canyon depths
  var volGlow = vec3<f32>(0.0);
  for (var i: i32 = 0; i < 16; i = i + 1) {
    let vt = f32(i) * 2.0 + hash21(vec2<f32>(f32(gid.x + i * 31), f32(gid.y + i * 57))) * 1.0;
    if (vt > depth) { break; }
    let vPos = ro + rd * vt;
    let vRes = map(vPos, time, audio, crystalDensity, plasmaGlow, refractiveIndex, mousePos);
    if (vRes.mat > 0.5 && vRes.mat < 1.5) {
      let falloff = exp(-vt * 0.08);
      volGlow = volGlow + vec3<f32>(0.3, 0.05, 0.5) * falloff * 0.015 * vRes.glow;
    }
  }
  col = col + volGlow;

  // Temporal persistence
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  col = mix(col, prev.rgb * 0.92, 0.03);

  // Tone map
  col = acesToneMap(col * 1.2);

  let alpha = sat(0.9 + length(volGlow) * 2.0);
  let finalDepth = sat(0.95 - depth * 0.015);

  textureStore(writeTexture, coord, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(col.r, col.g, col.b, alpha));
}