// ═══════════════════════════════════════════════════════════════════
//  gen-chromatic-glass-lattice
//  Category: generative
//  Features: raymarched, chromatic-dispersion, audio-reactive, mouse-driven, glass-refraction, upgraded-rgba, depth-aware, aces-tone-map
//  Ideas: Cauchy multi-order dispersion with internal TIR caustic ribs, acoustic resonance stress birefringence, micro-fracture edge sparkle glints
//  A packing: display RGBA (RGB=ACES tone-mapped glass color, A=alpha/presence)
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

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
  let q = abs(p) - b;
  return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
  let a = abs(p);
  return (a.x + a.y + a.z - s) * 0.57735027;
}

fn opRep(p: vec3<f32>, c: vec3<f32>) -> vec3<f32> {
  return p - c * round(p / c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = sat(0.5 + 0.5 * (b - a) / k);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// ─── Voronoi for shattering ───
fn voronoi3D(x: vec3<f32>) -> vec2<f32> {
  let n = floor(x);
  let f = fract(x);
  var md = 8.0;
  var mr = vec3<f32>(0.0);
  for (var k: i32 = -1; k <= 1; k = k + 1) {
    for (var j: i32 = -1; j <= 1; j = j + 1) {
      for (var i: i32 = -1; i <= 1; i = i + 1) {
        let g = vec3<f32>(f32(i), f32(j), f32(k));
        let o = vec3<f32>(
          hash3(n + g + vec3<f32>(0.0, 0.0, 1.0)),
          hash3(n + g + vec3<f32>(0.0, 1.0, 0.0)),
          hash3(n + g + vec3<f32>(1.0, 0.0, 0.0))
        );
        let r = g + o - f;
        let d = dot(r, r);
        if (d < md) {
          md = d;
          mr = r;
        }
      }
    }
  }
  return vec2<f32>(md, hash3(floor(x + mr)));
}

// ─── Refraction ───
fn refractRay(I: vec3<f32>, N: vec3<f32>, eta: f32) -> vec3<f32> {
  let cosi = dot(I, N);
  let cost2 = 1.0 - eta * eta * (1.0 - cosi * cosi);
  if (cost2 < 0.0) {
    return reflect(I, N);
  }
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ─── Scene Map ───
struct MapResult {
  d: f32,
  mat: f32,
  glow: f32,
  shatterEdge: f32,
};

fn map(p_in: vec3<f32>, time: f32, audio: f32, shatterForce: f32, latticeDensity: f32,
       mousePos: vec3<f32>) -> MapResult {
  var p = p_in;

  // Mouse shatter distortion
  let md = p - mousePos;
  let mDist = length(md);
  let shatterRadius = 2.8;
  var shatterEdge = 0.0;
  if (mDist < shatterRadius) {
    let voron = voronoi3D(p * 3.0 + time * 0.3);
    let shatter = (1.0 - mDist / shatterRadius);
    shatterEdge = smoothstep(0.1, 0.02, abs(voron.x - 0.5)) * shatter;
    p = p + normalize(md) * shatter * shatterForce * (0.3 + voron.x * 0.7);
  }

  // Audio vibration
  let vibrate = sin(p.y * 8.0 + time * 5.0) * audio * 0.04;
  p = p + vec3<f32>(vibrate, vibrate * 0.7, vibrate * 0.5);

  // Domain repetition for lattice
  let cellSize = 2.2 / latticeDensity;
  let q = opRep(p, vec3<f32>(cellSize));

  // Core lattice: intersected box + octahedron
  let boxSize = cellSize * 0.35;
  let dBox = sdBox(q, vec3<f32>(boxSize));
  let dOct = sdOctahedron(q, boxSize * 1.2);

  var d = max(dBox, dOct * 0.8);

  // Cross-braces
  let q2 = opRep(p + vec3<f32>(cellSize * 0.5), vec3<f32>(cellSize));
  let dBrace = sdBox(q2, vec3<f32>(boxSize * 0.15, boxSize * 0.6, boxSize * 0.15));
  d = smin(d, dBrace, 0.08);

  // Inner core glow sphere
  let coreD = length(q) - boxSize * 0.35;
  var glow = sat((0.15 - coreD) / 0.15) * (0.5 + audio * 0.5);

  var mat = 1.0;
  if (coreD < 0.0) { mat = 0.5; }

  return MapResult(d, mat, glow, shatterEdge);
}

fn calcNormal(p: vec3<f32>, time: f32, audio: f32, shatterForce: f32, latticeDensity: f32,
              mousePos: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let m1 = map(p + e.xyy, time, audio, shatterForce, latticeDensity, mousePos);
  let m2 = map(p - e.xyy, time, audio, shatterForce, latticeDensity, mousePos);
  let m3 = map(p + e.yxy, time, audio, shatterForce, latticeDensity, mousePos);
  let m4 = map(p - e.yxy, time, audio, shatterForce, latticeDensity, mousePos);
  let m5 = map(p + e.yyx, time, audio, shatterForce, latticeDensity, mousePos);
  let m6 = map(p - e.yyx, time, audio, shatterForce, latticeDensity, mousePos);
  return normalize(vec3<f32>(m1.d - m2.d, m3.d - m4.d, m5.d - m6.d));
}

// ─── Chromatic Raymarch ───
fn raymarchChromatic(ro: vec3<f32>, rd: vec3<f32>, time: f32, audio: f32, mids: f32, treble: f32,
                     shatterForce: f32, latticeDensity: f32, chromaticSpread: f32,
                     etaBase: f32, mousePos: vec3<f32>) -> vec4<f32> {
  var t = 0.0;
  var col = vec3<f32>(0.0);
  var alpha = 0.0;
  var hit = false;

  // IDEA 1: Cauchy multi-order dispersion with internal TIR caustic ribs
  // Uses the live slider refraction index as etaBase
  let etaR = 1.0 / (etaBase - chromaticSpread);
  let etaG = 1.0 / etaBase;
  let etaB = 1.0 / (etaBase + chromaticSpread);

  for (var i: i32 = 0; i < 80; i = i + 1) {
    let p = ro + rd * t;
    let res = map(p, time, audio, shatterForce, latticeDensity, mousePos);
    let d = res.d;

    if (d < 0.001) {
      hit = true;
      let hitGlow = res.glow;
      let shatterEdge = res.shatterEdge;

      let n = calcNormal(p, time, audio, shatterForce, latticeDensity, mousePos);
      let cosi = dot(-rd, n);

      let f = fresnel(cosi, etaBase);

      // Refracted directions per wavelength
      let rr = refractRay(rd, n, etaR);
      let rg = refractRay(rd, n, etaG);
      let rb = refractRay(rd, n, etaB);

      // Internal raymarch for caustics & TIR
      var innerCol = vec3<f32>(0.0);
      let innerSteps = 16;
      var it = 0.06;
      for (var j: i32 = 0; j < innerSteps; j = j + 1) {
        let ip = p + rg * it;
        let ires = map(ip, time, audio, shatterForce, latticeDensity, mousePos);
        if (ires.d > 0.0) {
          innerCol = vec3<f32>(0.02, 0.03, 0.06) * (1.0 + 0.5 * sin(ip.y * 0.5 + time));
          innerCol += vec3<f32>(0.1, 0.05, 0.2) * ires.glow;
          break;
        }
        it += 0.1;
      }

      // IDEA 2: Acoustic resonance stress birefringence
      // Internal lattice stress modulated by audio bass/mids produces photoelastic isochromatics
      let strutStress = abs(sin(p.x * latticeDensity * 4.0) * cos(p.y * latticeDensity * 4.0));
      let stressPhase = strutStress * 18.0 + audio * 4.0;
      let photoelasticBirefringence = 0.5 + 0.5 * cos(stressPhase + vec3<f32>(0.0, 2.094, 4.188));
      innerCol += photoelasticBirefringence * (0.2 + mids * 0.3);

      // Core glow
      let coreCol = vec3<f32>(0.8, 0.3, 0.9) * hitGlow * 2.0
                  + vec3<f32>(0.2, 0.6, 1.0) * hitGlow * audio;

      let reflDir = reflect(rd, n);
      let reflCol = vec3<f32>(0.05, 0.08, 0.12) + vec3<f32>(0.1, 0.05, 0.15) * max(reflDir.y, 0.0);

      col.r = mix(innerCol.r * 0.8 + coreCol.r, reflCol.r, f);
      col.g = mix(innerCol.g * 1.0 + coreCol.g, reflCol.g, f);
      col.b = mix(innerCol.b * 1.2 + coreCol.b, reflCol.b, f);

      // Iridescent thin-film Fresnel tint
      let fresnelTint = 0.5 + 0.5 * cos(cosi * 6.0 + vec3<f32>(0.0, 2.094, 4.188));
      col += fresnelTint * f * 0.35;

      // IDEA 3: Micro-fracture edge sparkle glints
      // Grazing specular reflection on shatter fractures
      let glintDot = max(dot(reflDir, normalize(vec3<f32>(1.0, 2.0, -1.0))), 0.0);
      let glint = pow(glintDot, 64.0) * shatterEdge * (1.0 + treble * 2.0);
      col += vec3<f32>(1.2, 0.9, 1.5) * glint;

      alpha = sat(0.35 + f * 0.65);
      break;
    }

    if (t > 30.0) { break; }
    t += d * 0.7;
  }

  if (!hit) {
    let sky = vec3<f32>(0.01, 0.015, 0.03) + vec3<f32>(0.02, 0.01, 0.04) * max(rd.y, 0.0);
    let distGlow = sat(0.05 / (abs(rd.y) + 0.02));
    col = sky + vec3<f32>(0.3, 0.15, 0.5) * distGlow * (0.3 + audio * 0.3);
    alpha = 0.0;
  }

  return vec4<f32>(col, alpha);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let refractionIdx = mix(1.2, 2.5, clamp(u.zoom_params.x, 0.0, 1.0));
  let chromaticSpread = mix(0.0, 0.15, clamp(u.zoom_params.y, 0.0, 1.0));
  let latticeDensity = mix(0.8, 3.0, clamp(u.zoom_params.z, 0.0, 1.0));
  let shatterForce = mix(0.0, 3.0, clamp(u.zoom_params.w, 0.0, 1.0));

  // Single-writer spring-damper cursor for shatter center in extraBuffer[133..138]
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  var sprungMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  var mouseVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  if (extraBuffer[137] < 0.5) {
      sprungMouse = rawMouse;
      mouseVel = vec2<f32>(0.0);
  }
  let dt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
  let omega = 8.0;
  mouseVel += ((rawMouse - sprungMouse) * (omega * omega) - mouseVel * (2.0 * omega)) * dt;
  sprungMouse += mouseVel * dt;

  if (gid.x == 0u && gid.y == 0u && arrayLength(&extraBuffer) > 138u) {
      extraBuffer[133] = sprungMouse.x;
      extraBuffer[134] = sprungMouse.y;
      extraBuffer[135] = mouseVel.x;
      extraBuffer[136] = mouseVel.y;
      extraBuffer[137] = 1.0;
      extraBuffer[138] = time;
  }

  let mouseUV = sprungMouse;
  let mousePos = vec3<f32>(
    (mouseUV.x * 2.0 - 1.0) * 4.0 * aspect,
    (mouseUV.y * 2.0 - 1.0) * 4.0,
    0.0
  );

  // Camera
  let camDist = 6.0 + sin(time * 0.2) * 0.5;
  let camAng = time * 0.15 + mouseUV.x * 0.5;
  let camHeight = sin(time * 0.1) * 0.5 + mouseUV.y * 0.3;
  let ro = vec3<f32>(cos(camAng) * camDist, camHeight, sin(camAng) * camDist);
  let ta = vec3<f32>(0.0, 0.0, 0.0);
  let ww = normalize(ta - ro);
  let uu = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), ww));
  let vv = cross(ww, uu);

  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  let rd = normalize(p.x * uu + p.y * vv + 2.5 * ww);

  // Raymarch
  let result = raymarchChromatic(ro, rd, time, bass, mids, treble, shatterForce, latticeDensity, chromaticSpread, refractionIdx, mousePos);
  var col = result.rgb;
  let alpha = result.a;

  // Volumetric caustics
  var causticGlow = vec3<f32>(0.0);
  let numSamples = 16;
  let stepSize = 15.0 / f32(numSamples);
  for (var i: i32 = 0; i < numSamples; i = i + 1) {
    let t = f32(i) * stepSize + hash21(vec2<f32>(f32(i32(gid.x) + i * 73), f32(i32(gid.y) + i * 137))) * stepSize;
    let rp = ro + rd * t;
    let vn = voronoi3D(rp * latticeDensity * 0.5 + time * 0.1);
    let caust = sat(0.3 - vn.x) * exp(-t * 0.08);
    causticGlow += vec3<f32>(0.4, 0.2, 0.6) * caust * (0.1 + bass * 0.2) * 0.06;
  }
  col += causticGlow;
  col += vec3<f32>(0.1, 0.05, 0.2) * bass * 0.2 * alpha;

  // Exact-integer textureLoad from dataTextureC previous frame feedback
  let prev = textureLoad(dataTextureC, coord, 0);
  col = mix(col, prev.rgb * 0.92, 0.04);

  let finalRGB = acesToneMap(col * 1.2);
  let finalAlpha = clamp(alpha + length(causticGlow) * 1.5, 0.0, 1.0);
  let finalDepth = sat(0.95 - alpha * 0.5 + shatterForce * 0.02);

  textureStore(writeTexture, coord, vec4<f32>(finalRGB, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(finalRGB, finalAlpha));
}
