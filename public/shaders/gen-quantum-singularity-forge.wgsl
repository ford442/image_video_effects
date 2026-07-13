// ═══════════════════════════════════════════════════════════════════
//  Quantum Singularity-Forge
//  Category: generative
//  Features: raymarched, chromatic-dispersion, audio-reactive,
//            mouse-driven, gravitational-lensing, upgraded-rgba,
//            depth-aware, aces-tone-map, cosmic-forge
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

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
  let q = vec2<f32>(length(p.xz) - t.x, p.y);
  return length(q) - t.y;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = sat(0.5 + 0.5 * (b - a) / k);
  return mix(b, a, h) - k * h * (1.0 - h);
}

fn opRep(p: vec3<f32>, c: vec3<f32>) -> vec3<f32> {
  return p - c * round(p / c);
}

// ─── ACES Tone Map ───
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ─── KIFS Constellation ───
fn kifsConstellation(p: vec3<f32>, time: f32, audio: f32) -> f32 {
  var z = p;
  var dr = 1.0;
  var d = 8.0;
  for (var i: i32 = 0; i < 4; i = i + 1) {
    z = abs(z);
    let fi = f32(i);
    let rot = rot3Y(time * 0.3 + fi * 1.047) * rot3X(time * 0.2 + fi * 0.785);
    z = rot * z;
    z = z - vec3<f32>(0.5 + audio * 0.2, 0.2, 0.0);
    dr = dr * 2.0;
    let dd = length(z) / dr;
    if (dd < d) { d = dd; }
  }
  return d;
}

// ─── Scene Map ───
struct MapResult {
  d: f32,
  mat: f32,
  glow: f32,
};

fn map(p_in: vec3<f32>, time: f32, audio: f32, gravity: f32, accretionSpeed: f32,
       ejectionRate: f32, mousePos: vec3<f32>) -> MapResult {
  var p = p_in;

  // Gravitational lensing distortion from mouse
  let md = p - mousePos;
  let mDist = length(md);
  let lensRadius = 4.0;
  if (mDist < lensRadius) {
    let lens = (1.0 - mDist / lensRadius) * gravity * 0.5;
    p = p + normalize(md) * lens * sin(mDist * 3.0 + time);
  }

  // Central singularity (black hole)
  let bhDist = length(p);
  let bhRadius = 0.3 + audio * 0.05;
  let singularity = sdSphere(p, bhRadius);

  // Accretion disk (distorted torus)
  let diskAngle = time * accretionSpeed;
  let diskP = rot3Y(diskAngle) * p;
  // Warp the disk
  let warp = vec3<f32>(
    sin(diskP.y * 2.0 + time) * 0.2,
    cos(diskP.x * 2.0 + time * 0.7) * 0.15,
    sin(diskP.z * 1.5 + time * 0.5) * 0.1
  );
  let diskDist = sdTorus(diskP + warp, vec2<f32>(1.2 + audio * 0.1, 0.25 + audio * 0.05));
  let disk = diskDist - 0.1 * fbm3(diskP * 3.0 + time, 3);

  // Event horizon glow
  var glow = sat(0.0 - singularity) * 3.0;
  glow = glow + sat(0.0 - disk) * (1.0 + audio * 2.0);

  // Ejected constellations (KIFS crystals)
  var constellation = 8.0;
  let beatPhase = sin(time * 3.0 + audio * 5.0) * ejectionRate;
  if (beatPhase > 0.0) {
    let ejectionP = p - vec3<f32>(0.0, 0.0, 0.0);
    let rotAngle = time * 0.5 + audio * 2.0;
    var ec = rot3Y(rotAngle) * ejectionP;
    ec = ec - vec3<f32>(2.0 + beatPhase * 2.0, 0.0, 0.0);
    constellation = kifsConstellation(ec, time, audio);
  }

  // Combine
  let d = min(min(disk, constellation), singularity);

  var mat = 1.0; // 1.0 = accretion disk
  if (singularity < 0.001) { mat = 0.0; } // black hole
  if (constellation < disk && constellation < singularity) { mat = 2.0; } // crystal

  return MapResult(d, mat, glow);
}

fn calcNormal(p: vec3<f32>, time: f32, audio: f32, gravity: f32, accretionSpeed: f32,
              ejectionRate: f32, mousePos: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let m1 = map(p + e.xyy, time, audio, gravity, accretionSpeed, ejectionRate, mousePos);
  let m2 = map(p - e.xyy, time, audio, gravity, accretionSpeed, ejectionRate, mousePos);
  let m3 = map(p + e.yxy, time, audio, gravity, accretionSpeed, ejectionRate, mousePos);
  let m4 = map(p - e.yxy, time, audio, gravity, accretionSpeed, ejectionRate, mousePos);
  let m5 = map(p + e.yyx, time, audio, gravity, accretionSpeed, ejectionRate, mousePos);
  let m6 = map(p - e.yyx, time, audio, gravity, accretionSpeed, ejectionRate, mousePos);
  return normalize(vec3<f32>(m1.d - m2.d, m3.d - m4.d, m5.d - m6.d));
}

// ─── Heat Gradient (black -> indigo -> cyan -> white) ───
fn heatGradient(t: f32) -> vec3<f32> {
  let tt = clamp(t, 0.0, 1.0);
  return mix(
    mix(vec3<f32>(0.0, 0.0, 0.05), vec3<f32>(0.1, 0.0, 0.3), tt * 3.0),
    mix(vec3<f32>(0.0, 0.8, 1.0), vec3<f32>(1.0, 1.0, 1.0), (tt - 0.5) * 2.0),
    sat(tt * 2.0 - 0.5)
  );
}

// ─── Raymarch ───
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time: f32, audio: f32, bass: f32, mids: f32,
            gravity: f32, accretionSpeed: f32, ejectionRate: f32, mousePos: vec3<f32>) -> vec4<f32> {
  var t = 0.0;
  var col = vec3<f32>(0.0);
  var alpha = 0.0;
  var hit = false;
  var hitGlow = 0.0;
  var hitMat = 0.0;

  for (var i: i32 = 0; i < 96; i = i + 1) {
    let p = ro + rd * t;
    let res = map(p, time, audio, gravity, accretionSpeed, ejectionRate, mousePos);
    let d = res.d;

    if (d < 0.003) {
      hit = true;
      hitGlow = res.glow;
      hitMat = res.mat;
      let n = calcNormal(p, time, audio, gravity, accretionSpeed, ejectionRate, mousePos);

      if (hitMat < 0.5) {
        // Black hole - pure black with rim glow
        let rim = pow(1.0 - abs(dot(rd, n)), 4.0);
        col = vec3<f32>(0.0, 0.0, 0.0) + vec3<f32>(0.0, 0.3, 0.6) * rim * 2.0;
        alpha = rim * 0.8;
      } else if (hitMat > 1.5) {
        // Crystal constellation - iridescent chromatic dispersion
        let viewAngle = dot(-rd, n);
        let irid = vec3<f32>(
          0.5 + 0.5 * cos(viewAngle * 8.0 + 0.0),
          0.5 + 0.5 * cos(viewAngle * 8.0 + 2.1),
          0.5 + 0.5 * cos(viewAngle * 8.0 + 4.2)
        );
        col = irid * (1.0 + bass * 2.0) * 0.8;
        col = col + vec3<f32>(0.8, 0.9, 1.0) * pow(viewAngle, 3.0) * 0.5;
        alpha = 0.9;
      } else {
        // Accretion disk - heat gradient
        let temp = hitGlow * (0.5 + bass * 0.5);
        col = heatGradient(temp) * (1.0 + bass * 0.5);
        // Add emissive swirl
        let swirl = sin(p.x * 3.0 + time * 2.0 + p.z * 2.0) * 0.5 + 0.5;
        col = col + vec3<f32>(0.2, 0.4, 0.8) * swirl * bass * 0.3;
        alpha = sat(0.3 + hitGlow * 0.7);
      }
      break;
    }

    if (t > 40.0) { break; }
    t = t + d * 0.6;

    // Volumetric glow along ray (accretion fog)
    let glowSample = res.glow;
    if (glowSample > 0.01) {
      let glowCol = heatGradient(glowSample * 0.5) * glowSample * 0.05 * (1.0 + bass * 0.5);
      col = col + glowCol * exp(-t * 0.1);
    }
  }

  if (!hit) {
    // Starfield background with gravitational lensing
    var bg = vec3<f32>(0.0, 0.0, 0.01);
    let starfield = fbm3(rd * 5.0 + time * 0.05, 4);
    bg = bg + vec3<f32>(0.8, 0.85, 1.0) * pow(starfield, 4.0) * 0.3;
    // Distant nebula glow
    bg = bg + vec3<f32>(0.05, 0.0, 0.1) * (0.1 + bass * 0.1) * sat(0.5 / (abs(rd.y) + 0.1));
    col = bg;
    alpha = 0.0;
  }

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

  // Parameters from zoom_params (clamp to normalized range)
  let zparams = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
  let gravity = mix(0.1, 1.0, zparams.x);
  let accretionSpeed = mix(0.1, 2.0, zparams.y);
  let ejectionRate = mix(0.0, 1.0, zparams.z);
  let lensIntensity = mix(0.5, 2.0, zparams.w);

  // Mouse handling: screen top = UP in 3D
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mouseUV = u.zoom_config.yz;
  let mouseY = 1.0 - mouseUV.y; // Flip Y
  let mousePos = vec3<f32>(
    (mouseUV.x * 2.0 - 1.0) * 3.0 * aspect,
    (mouseUV.y * 2.0 - 1.0) * 3.0,
    0.0
  );

  // Camera orbiting the singularity
  let camDist = 4.0 + sin(time * 0.15) * 0.3;
  let camAng = time * 0.2 + mouseUV.x * 0.5;
  let camHeight = mouseY * 1.0 - 0.5;
  let ro = vec3<f32>(cos(camAng) * camDist, camHeight, sin(camAng) * camDist);
  let ta = vec3<f32>(0.0, 0.0, 0.0);
  let ww = normalize(ta - ro);
  let uu = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), ww));
  let vv = cross(ww, uu);

  // Ray direction
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  let rd = normalize(p.x * uu + p.y * vv + 2.5 * ww);

  // Raymarch
  let result = raymarch(ro, rd, time, audio, bass, mids, gravity, accretionSpeed, ejectionRate, mousePos);
  var col = result.rgb;
  var alpha = result.a;

  // Audio-reactive bloom overlay
  col = col + vec3<f32>(0.0, 0.2, 0.4) * bass * 0.15;
  col = col + vec3<f32>(0.3, 0.1, 0.5) * mids * 0.1;

  // Temporal persistence using extraBuffer
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  col = mix(col, prev.rgb * 0.92, 0.05);

  // Tone map
  col = acesToneMap(col * 1.5);

  let finalDepth = sat(0.95 - alpha * 0.3);

  textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(col.r, col.g, col.b, 1.0));
}
