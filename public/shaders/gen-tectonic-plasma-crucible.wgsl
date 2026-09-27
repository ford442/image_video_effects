// ═══════════════════════════════════════════════════════════════════
//  Tectonic Plasma-Crucible
//  Category: generative
//  Features: raymarched, voronoi-terrain, plasma-magma, audio-reactive,
//            mouse-driven, heat-distortion, upgraded-rgba, depth-aware,
//            aces-tone-map, blackbody-radiation
//  Complexity: Very High
//  Created: 2026-06-28
//  Upgraded: 2026-09-27
//  Ideas: incandescent-crack temperature ramp (continuous white-yellow -> orange -> red -> obsidian from edge distance);
//         per-plate isostatic bobbing/tilt from the Voronoi cell hash + bass rifting that widens fissures
//  A packing: display RGBA (ACES RGB, alpha = hit coverage + heat glow)
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

fn rot3Y(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
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
  for (var i: i32 = 0; i < 5; i = i + 1) {
    v = v + a * noise3D(pp);
    pp = pp * 2.03;
    a = a * 0.5;
  }
  return v;
}

// ─── Voronoi ───
struct VorOut {
  md: f32,        // nearest squared distance
  edge: f32,      // second - first squared distance (edge proximity)
  r: vec3<f32>,   // vector from p to nearest feature point (cell units)
  id: f32,        // hash of the nearest Voronoi cell (plate id)
};

fn voronoi(p: vec3<f32>) -> VorOut {
  let n = floor(p);
  let f = fract(p);
  var md = 8.0;
  var mr = vec3<f32>(0.0);
  var mg = vec3<f32>(0.0);
  for (var k: i32 = -1; k <= 1; k = k + 1) {
    for (var j: i32 = -1; j <= 1; j = j + 1) {
      for (var i: i32 = -1; i <= 1; i = i + 1) {
        let g = vec3<f32>(f32(i), f32(j), f32(k));
        let o = vec3<f32>(hash3(n + g + vec3<f32>(0.0, 0.0, 1.0)),
                         hash3(n + g + vec3<f32>(0.0, 1.0, 0.0)),
                         hash3(n + g + vec3<f32>(1.0, 0.0, 0.0)));
        let r = g + o - f;
        let d = dot(r, r);
        if (d < md) {
          md = d;
          mr = r;
          mg = g;
        }
      }
    }
  }
  // Second nearest for edge detection
  var md2 = 8.0;
  for (var k: i32 = -1; k <= 1; k = k + 1) {
    for (var j: i32 = -1; j <= 1; j = j + 1) {
      for (var i: i32 = -1; i <= 1; i = i + 1) {
        let g = vec3<f32>(f32(i), f32(j), f32(k));
        let o = vec3<f32>(hash3(n + g + vec3<f32>(0.0, 0.0, 1.0)),
                         hash3(n + g + vec3<f32>(0.0, 1.0, 0.0)),
                         hash3(n + g + vec3<f32>(1.0, 0.0, 0.0)));
        let r = g + o - f;
        let d = dot(r, r);
        if (d < md2 && d > md) {
          md2 = d;
        }
      }
    }
  }
  // IDEA 2: plate id = hash of the winning cell (no extra taps)
  let pid = hash3(n + mg + vec3<f32>(7.0, 13.0, 3.0));
  return VorOut(md, md2 - md, mr, pid);
}

// ─── SDF ───
fn sdPlane(p: vec3<f32>, n: vec3<f32>, h: f32) -> f32 {
  return dot(p, n) + h;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = sat(0.5 + 0.5 * (b - a) / k);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// ─── Blackbody color ───
fn blackbody(t: f32) -> vec3<f32> {
  // Approximate blackbody radiation color
  var col = vec3<f32>(0.0);
  col.r = 1.0;
  col.g = sat(1.0 - (t - 0.4) * (t - 0.4) * 5.0);
  col.b = sat(1.0 - t * 3.0);
  col = col * vec3<f32>(1.0, 0.9, 0.8);
  return col;
}

// IDEA 1: incandescent ramp. h = 1 white-yellow core, ~0.6 orange, ~0.3 dull red, 0 obsidian (HDR, pre-ACES)
fn incandescent(h: f32) -> vec3<f32> {
  let x = sat(h);
  var c = mix(vec3<f32>(0.0), vec3<f32>(0.45, 0.05, 0.02), smoothstep(0.0, 0.35, x));
  c = mix(c, vec3<f32>(1.0, 0.38, 0.06), smoothstep(0.3, 0.65, x));
  c = mix(c, vec3<f32>(1.7, 1.35, 0.7), smoothstep(0.6, 1.0, x));
  return c;
}

// ─── ACES Tone Map ───
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ─── Scene Map ───
struct MapResult {
  d: f32,
  mat: f32,    // 0 = crust, 1 = magma, 2 = heat haze
  temp: f32,   // temperature for glow
  heat: f32,   // IDEA 1: continuous crack heat 0..1 (falls off onto the crust)
};

fn map(p_in: vec3<f32>, time: f32, crustDensity: f32, magmaTurbulence: f32,
       eruptionIntensity: f32, tectonicStress: f32, mousePos: vec2<f32>, rift: f32) -> MapResult {
  var p = p_in;

  // Mouse tectonic stress
  let mouseWorld = vec3<f32>(mousePos.x * 6.0, 0.0, mousePos.y * 6.0);
  let md = p - mouseWorld;
  let mDist = length(md.xz);
  let stressRadius = 3.0;
  if (mDist < stressRadius) {
    let stress = (1.0 - mDist / stressRadius) * tectonicStress;
    p.y = p.y - stress * 0.5;
    p.x = p.x + stress * md.x * 0.2;
    p.z = p.z + stress * md.z * 0.2;
  }

  // Base plane
  var d = sdPlane(p, vec3<f32>(0.0, 1.0, 0.0), 0.0);

  // Voronoi tectonic slabs
  let vp = p * crustDensity;
  let vor = voronoi(vp);
  let cellDist = vor.md;
  let edgeDist = vor.edge;

  // Slab height
  let slabHeight = 0.3 + hash3(floor(vp)) * 0.4;

  // IDEA 2: isostatic bobbing + tilt per plate (rises/tilts about its own feature point).
  // slab surface sits at y = -height, so upward lift subtracts from the height.
  let rel = -vor.r.xz / crustDensity;
  let plateLift = sin(time * 0.7 + vor.id * 6.2831) * 0.05
                + (sin(time * 0.45 + vor.id * 17.0) * rel.x + cos(time * 0.38 + vor.id * 9.0) * rel.y) * 0.06;
  var slab = sdPlane(p, vec3<f32>(0.0, 1.0, 0.0), slabHeight - plateLift);

  // Eruption spikes from audio
  let spike = sin(p.x * 3.0 + time * 2.0) * sin(p.z * 3.0 + time * 1.5);
  let eruption = spike * eruptionIntensity * 0.2;
  slab = slab + eruption;

  // Fissures = where voronoi edges are thin
  // IDEA 2: bass rifting widens the fissures (rift = 0 at silence -> original width)
  let fissureWidth = 0.08 / crustDensity * (1.0 + rift);
  let inFissure = sat(1.0 - edgeDist / fissureWidth);
  // IDEA 1: continuous thermal falloff, ~2.5 fissure widths onto the crust
  let thermal = sat(1.0 - edgeDist / (fissureWidth * 2.5));
  let heat = thermal * thermal;

  // Crust surface: slabs minus fissures
  var crust = smin(slab, d + 0.5, 0.2);
  crust = crust - inFissure * 0.5;

  // Magma ocean below crust
  let magmaSurface = -0.2 + fbm(p * 2.0 + vec3<f32>(0.0, time * 0.3, 0.0)) * magmaTurbulence * 0.3;
  let magma = sdPlane(p, vec3<f32>(0.0, 1.0, 0.0), magmaSurface);

  // Combine: crust on top, magma below
  var finalD = smin(crust, magma + 0.3, 0.15);

  // Determine material
  var mat = 0.0; // crust
  var temp = 0.0;

  if (p.y < magmaSurface + 0.1) {
    mat = 1.0; // magma
    temp = 1.0;
  }

  // Fissures expose magma
  if (inFissure > 0.5 && p.y < slabHeight + 0.2) {
    mat = 1.0;
    temp = inFissure;
  }

  // Crust temp (cooler at top)
  if (mat < 0.5) {
    temp = sat(0.1 + inFissure * 0.3 + eruption * 0.5);
  }

  return MapResult(finalD, mat, temp, heat);
}

fn calcNormal(p: vec3<f32>, time: f32, crustDensity: f32, magmaTurbulence: f32,
              eruptionIntensity: f32, tectonicStress: f32, mousePos: vec2<f32>, rift: f32) -> vec3<f32> {
  let e = vec2<f32>(0.005, 0.0);
  let m1 = map(p + e.xyy, time, crustDensity, magmaTurbulence, eruptionIntensity, tectonicStress, mousePos, rift);
  let m2 = map(p - e.xyy, time, crustDensity, magmaTurbulence, eruptionIntensity, tectonicStress, mousePos, rift);
  let m3 = map(p + e.yxy, time, crustDensity, magmaTurbulence, eruptionIntensity, tectonicStress, mousePos, rift);
  let m4 = map(p - e.yxy, time, crustDensity, magmaTurbulence, eruptionIntensity, tectonicStress, mousePos, rift);
  let m5 = map(p + e.yyx, time, crustDensity, magmaTurbulence, eruptionIntensity, tectonicStress, mousePos, rift);
  let m6 = map(p - e.yyx, time, crustDensity, magmaTurbulence, eruptionIntensity, tectonicStress, mousePos, rift);
  return normalize(vec3<f32>(m1.d - m2.d, m3.d - m4.d, m5.d - m6.d));
}

// ─── Heat haze distortion ───
fn heatHaze(ro: vec3<f32>, rd: vec3<f32>, p: vec3<f32>, temp: f32, time: f32) -> vec3<f32> {
  if (temp < 0.3) { return rd; }
  let dist = length(p - ro);
  let hazeStrength = temp * sat(1.0 - dist * 0.1) * 0.05;
  let offset = vec3<f32>(
    sin(p.y * 10.0 + time * 3.0) * hazeStrength,
    cos(p.x * 10.0 + time * 2.5) * hazeStrength,
    sin(p.z * 8.0 + time * 2.0) * hazeStrength
  );
  return normalize(rd + offset);
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
  let crustDensity = mix(0.5, 2.5, clamp(u.zoom_params.x, 0.0, 1.0));
  let magmaTurbulence = mix(0.0, 1.5, clamp(u.zoom_params.y, 0.0, 1.0));
  let eruptionIntensity = mix(0.0, 2.0, clamp(u.zoom_params.z, 0.0, 1.0));
  let tectonicStress = mix(0.0, 3.5, clamp(u.zoom_params.w, 0.0, 1.0));
  // IDEA 2: bass rift factor (0 at silence)
  let rift = sat(bass) * (0.4 + eruptionIntensity * 0.6);

  // Mouse
  let mouseRaw = u.zoom_config.yz * 2.0 - 1.0;
  let mousePos = mouseRaw;  // Flip Y: screen top = up

  // Camera
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let camDist = 5.0 + sin(time * 0.1) * 0.5;
  let camAng = time * 0.08 + mousePos.x * 0.3;
  let ro = vec3<f32>(cos(camAng) * camDist, 2.5 + mousePos.y * 0.5, sin(camAng) * camDist);
  let ta = vec3<f32>(0.0, -0.5, 0.0);
  let ww = normalize(ta - ro);
  let uu = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), ww));
  let vv = cross(ww, uu);

  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  var rd = normalize(p.x * uu + p.y * vv + 2.5 * ww);

  // Raymarch
  var t = 0.0;
  var col = vec3<f32>(0.0);
  var hit = false;
  var hitPos = vec3<f32>(0.0);
  var hitMat = 0.0;
  var hitTemp = 0.0;
  var hitHeat = 0.0;
  var depth = 0.0;

  for (var i: i32 = 0; i < 100; i = i + 1) {
    let pos = ro + rd * t;
    let res = map(pos, time, crustDensity, magmaTurbulence, eruptionIntensity, tectonicStress, mousePos, rift);

    // Heat haze on approach
    if (res.temp > 0.3 && !hit) {
      rd = heatHaze(ro, rd, pos, res.temp, time);
    }

    if (res.d < 0.005) {
      hit = true;
      hitPos = pos;
      hitMat = res.mat;
      hitTemp = res.temp;
      hitHeat = res.heat;
      depth = t;
      break;
    }

    if (t > 40.0) { break; }
    t = t + res.d * 0.6;
  }

  if (hit) {
    let n = calcNormal(hitPos, time, crustDensity, magmaTurbulence, eruptionIntensity, tectonicStress, mousePos, rift);
    let lightDir = normalize(vec3<f32>(0.5, 0.8, 0.3));
    let viewDir = -rd;

    if (hitMat > 0.5) {
      // Magma material
      let bb = blackbody(sat(hitTemp * 0.8 + audio * 0.3));
      let diff = sat(dot(n, lightDir));
      let spec = pow(sat(dot(reflect(-lightDir, n), viewDir)), 16.0);

      // Bubbling surface
      let bubble = fbm(hitPos * 4.0 + vec3<f32>(0.0, time, 0.0)) * magmaTurbulence;
      let bubbleGlow = vec3<f32>(1.0, 0.6, 0.2) * bubble * 0.5;

      // IDEA 1: fissure magma follows the incandescent ramp (white-yellow core), open ocean keeps blackbody
      let hotCol = incandescent(hitHeat) * (0.7 + diff * 0.4);
      let hw = smoothstep(0.05, 0.7, hitHeat);
      col = mix(bb * (0.6 + diff * 0.4), hotCol, hw) + vec3<f32>(1.0, 0.9, 0.7) * spec * 0.3;
      col = col + bubbleGlow;

      // Audio eruption glow
      col = col + vec3<f32>(1.0, 0.4, 0.1) * bass * eruptionIntensity * 0.3;
    } else {
      // Obsidian crust
      let diff = sat(dot(n, lightDir));
      let spec = pow(sat(dot(reflect(-lightDir, n), viewDir)), 64.0);
      let fresnel = pow(1.0 - sat(dot(n, viewDir)), 3.0);

      // Obsidian color
      var crustCol = vec3<f32>(0.04, 0.03, 0.05);
      // Heat glow on crust edges
      let edgeGlow = blackbody(hitTemp) * hitTemp * 0.5;
      crustCol = crustCol + edgeGlow;

      col = crustCol * (0.3 + diff * 0.5) + vec3<f32>(0.3, 0.25, 0.35) * spec * 0.4;
      col = col + vec3<f32>(0.1, 0.05, 0.2) * fresnel * 0.3;
      // IDEA 1: thermal halo — unlit emissive falloff from the crack onto the obsidian
      col = col + incandescent(hitHeat) * hitHeat * 0.8;
    }

    // Ambient occlusion (fake)
    let ao = sat(0.5 + 0.5 * n.y);
    col = col * (0.5 + 0.5 * ao);
  } else {
    // Sky
    col = vec3<f32>(0.01, 0.005, 0.02) * (1.0 + rd.y * 0.5);
    // Distant heat glow on horizon
    col = col + vec3<f32>(0.3, 0.1, 0.05) * sat(0.1 / (abs(rd.y) + 0.05)) * (0.1 + audio * 0.1);
    depth = 40.0;
  }

  // Volumetric heat shimmer (glowing air above magma)
  var volGlow = vec3<f32>(0.0);
  for (var i: i32 = 0; i < 12; i = i + 1) {
    let vt = f32(i) * 0.8 + hash21(vec2<f32>(f32(i32(gid.x) + i * 31), f32(i32(gid.y) + i * 57))) * 0.4;
    if (vt > depth) { break; }
    let vPos = ro + rd * vt;
    let vRes = map(vPos, time, crustDensity, magmaTurbulence, 0.0, 0.0, mousePos, rift);
    if (vRes.mat > 0.5) {
      let falloff = exp(-vt * 0.15);
      volGlow = volGlow + vec3<f32>(0.5, 0.2, 0.05) * falloff * 0.02 * (0.5 + audio * 0.5);
    }
  }
  col = col + volGlow;

  // Tone map, then temporal persistence in display space (A stores display RGB)
  col = acesToneMap(col * 1.3);
  let prev = textureLoad(dataTextureC, coord, 0);
  col = mix(col, prev.rgb * 0.92, 0.03);

  // Semantic alpha: hit coverage + heat glow + volumetric glow
  let alpha = clamp(select(0.35, 0.7, hit) + 0.3 * hitHeat + 0.3 * sat(length(volGlow) * 8.0), 0.0, 1.0);
  let finalDepth = sat(0.9 - depth * 0.02 + hitTemp * 0.05);

  textureStore(writeTexture, coord, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(col.r, col.g, col.b, alpha));
}
