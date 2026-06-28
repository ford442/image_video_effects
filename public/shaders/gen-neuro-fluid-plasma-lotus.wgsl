// ═══════════════════════════════════════════════════════════════════
//  Neuro-Fluid Plasma-Lotus
//  Category: generative
//  Features: raymarched, volumetric, audio-reactive, mouse-driven,
//            liquid-neon, chromatic-dispersion, upgraded-rgba,
//            depth-aware, aces-tone-map
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
  config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=PetalCurl, y=BloomPulse, z=CoreHeat, w=Dispersion
  ripples: array<vec4<f32>, 50>,
};

// ─── Math Helpers ───
fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash3(p: vec3<f32>) -> f32 {
  let q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  var qv = q + dot(q, q.yzx + vec3<f32>(33.33));
  return fract((qv.x + qv.y) * qv.z);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn rot2D(a: f32) -> mat2x2<f32> {
  let c = cos(a);
  let s = sin(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn rot3Y(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

// ─── Noise ───
fn vnoise3(p: vec3<f32>) -> f32 {
  let i = floor(p);
  var f = fract(p);
  f = f * f * (vec3<f32>(3.0) - 2.0 * f);
  let h = i.x + i.y * 57.0 + i.z * 113.0;
  return mix(
    mix(
      mix(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), hash3(i + vec3<f32>(1.0, 0.0, 0.0)), f.x),
      mix(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), hash3(i + vec3<f32>(1.0, 1.0, 0.0)), f.x), f.y
    ),
    mix(
      mix(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), hash3(i + vec3<f32>(1.0, 0.0, 1.0)), f.x),
      mix(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), hash3(i + vec3<f32>(1.0, 1.0, 1.0)), f.x), f.y
    ), f.z
  );
}

fn fbm3(p: vec3<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pos = p;
  for (var i = 0; i < 5; i++) {
    v += a * vnoise3(pos);
    pos = pos * 2.1 + vec3<f32>(1.7, 0.3, 0.9);
    a *= 0.5;
  }
  return v;
}

// ─── SDF Primitives ───
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
  return length(p) - r;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = sat(0.5 + 0.5 * (b - a) / k);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// ─── Bass Envelope Smoothing ───
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

// ─── ACES Tone Map ───
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ─── Scene Map ───
struct MapResult {
  d: f32,
  mat: f32,
  glow: f32,
};

var<private> g_time: f32;
var<private> g_audio: f32;
var<private> g_mouse: vec2<f32>;

fn map(p_in: vec3<f32>, petalCurl: f32, bloomPulse: f32, coreHeat: f32, dispersion: f32) -> MapResult {
  var p = p_in;

  // Magnetic twist along Y axis
  let twistAngle = g_time * 0.2 + g_audio * 0.5;
  let rotTwist = rot2D(twistAngle * 0.3);
  let p_xz = rotTwist * p.xz;
  p.x = p_xz.x;
  p.z = p_xz.y;

  // Mouse phototropic offset - petals reach toward cursor
  let mouseWorld = vec3<f32>(g_mouse.x * 3.0, (0.5 - g_mouse.y) * 3.0, 0.0);
  let mouseDist = length(p - mouseWorld);
  let reach = max(0.0, 1.0 - mouseDist / 4.0) * 0.4;
  p = p + normalize(p - mouseWorld + vec3<f32>(0.0, 0.5, 0.0)) * reach;

  // Convert to spherical-like coords for petal shaping
  let r = length(p);
  let theta = atan2(p.z, p.x);
  let phi = acos(clamp(p.y / max(r, 0.001), -1.0, 1.0));

  // Base sphere
  let baseRadius = 1.5 + bloomPulse * 0.3;
  var d = r - baseRadius;

  // Petal ridges via sinusoidal displacement on sphere
  let numPetals = 8.0;
  let petalWave = sin(theta * numPetals + g_time * 0.5) * cos(phi * 2.0);
  let petalAmp = 0.3 * petalCurl;
  let petalDist = r - baseRadius - petalWave * petalAmp - bloomPulse * 0.2;

  // FBM displacement for organic fluid look
  let noiseWarp = fbm3(p * 1.5 + vec3<f32>(g_time * 0.1, 0.0, g_time * 0.15)) * 0.25;
  let fluidDist = r - baseRadius - noiseWarp;

  // Combine: smooth min of base sphere, petal ridges, and fluid noise
  d = smin(d, petalDist, 0.3);
  d = smin(d, fluidDist, 0.2);

  // Inner glowing core (stamen)
  let coreRadius = 0.4 + coreHeat * 0.15;
  let coreNoise = fbm3(p * 3.0 + vec3<f32>(g_time * 0.3)) * 0.1;
  let coreDist = r - coreRadius - coreNoise;

  // Material and glow
  var mat = 1.0; // 1.0 = petal
  var glow = 0.0;

  if (coreDist < d) {
    d = coreDist;
    mat = 0.0; // 0.0 = core
    glow = coreHeat * (1.0 + g_audio * 2.0);
  }

  // Subsurface scattering glow near surface
  let sss = sat((0.2 - abs(d)) / 0.2) * bloomPulse;
  glow += sss * 0.5;

  return MapResult(d, mat, glow);
}

fn calcNormal(p: vec3<f32>, petalCurl: f32, bloomPulse: f32, coreHeat: f32, dispersion: f32) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let m1 = map(p + e.xyy, petalCurl, bloomPulse, coreHeat, dispersion);
  let m2 = map(p - e.xyy, petalCurl, bloomPulse, coreHeat, dispersion);
  let m3 = map(p + e.yxy, petalCurl, bloomPulse, coreHeat, dispersion);
  let m4 = map(p - e.yxy, petalCurl, bloomPulse, coreHeat, dispersion);
  let m5 = map(p + e.yyx, petalCurl, bloomPulse, coreHeat, dispersion);
  let m6 = map(p - e.yyx, petalCurl, bloomPulse, coreHeat, dispersion);
  return normalize(vec3<f32>(m1.d - m2.d, m3.d - m4.d, m5.d - m6.d));
}

// ─── Raymarch ───
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, petalCurl: f32, bloomPulse: f32, coreHeat: f32, dispersion: f32) -> vec4<f32> {
  var t = 0.0;
  var col = vec3<f32>(0.0);
  var depth = 0.0;
  var alpha = 0.0;
  var hit = false;
  var hitGlow = 0.0;
  var matId = 1.0;

  for (var i: i32 = 0; i < 100; i = i + 1) {
    let p = ro + rd * t;
    let res = map(p, petalCurl, bloomPulse, coreHeat, dispersion);
    let d = res.d;

    if (d < 0.001) {
      hit = true;
      depth = t;
      hitGlow = res.glow;
      matId = res.mat;

      let n = calcNormal(p, petalCurl, bloomPulse, coreHeat, dispersion);
      let v = -rd;

      // Light direction
      let lightDir = normalize(vec3<f32>(1.0, 1.5, -1.0));
      let diff = max(dot(n, lightDir), 0.0);

      if (matId < 0.5) {
        // Core: white-hot plasma
        let coreCol = vec3<f32>(1.0, 0.85, 0.6) * coreHeat * 2.0;
        let plasmaSwirl = fbm3(p * 2.0 + vec3<f32>(g_time * 0.5, 0.0, 0.0));
        col = coreCol * (1.0 + plasmaSwirl * 0.5);
        col += vec3<f32>(0.3, 0.6, 1.0) * g_audio * 2.0;
        alpha = 0.95;
      } else {
        // Petal: liquid-neon with chromatic dispersion
        // Base gradient: deep violet/magenta at base -> electric cyan/neon pink at tips
        let tipFactor = clamp((length(p) - 1.2) / 1.0, 0.0, 1.0);
        let baseCol = vec3<f32>(0.3, 0.0, 0.5); // violet
        let midCol = vec3<f32>(0.8, 0.0, 0.4);  // magenta
        let tipCol = vec3<f32>(0.0, 0.9, 0.9);  // electric cyan

        var petalCol = mix(baseCol, midCol, tipFactor);
        petalCol = mix(petalCol, tipCol, tipFactor * tipFactor);

        // Schlick glossy wet sheen
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 3.0);
        let sheen = vec3<f32>(0.5, 0.5, 0.6) * fresnel * dispersion;

        // Chromatic edge tint
        let chromatic = vec3<f32>(
          0.5 + 0.5 * cos(fresnel * 8.0 + 0.0),
          0.5 + 0.5 * cos(fresnel * 8.0 + 2.1),
          0.5 + 0.5 * cos(fresnel * 8.0 + 4.2)
        );

        // Core illumination (subsurface scattering)
        let coreDist = length(p);
        let sss = vec3<f32>(1.0, 0.6, 0.3) * (1.0 / (1.0 + coreDist * coreDist * 2.0)) * coreHeat * bloomPulse;

        col = petalCol * (diff * 0.6 + 0.2) + sheen + chromatic * 0.2 + sss;
        col += vec3<f32>(0.2, 0.0, 0.4) * g_audio * fresnel;
        alpha = 0.4 + fresnel * 0.4;
      }
      break;
    }

    if (t > 30.0) { break; }
    t = t + d * 0.7;
  }

  if (!hit) {
    // Deep abyss background with iridescent dust
    let abyss = vec3<f32>(0.01, 0.005, 0.02);
    let dust = hash21(vec2<f32>(ro.x + rd.x * 10.0, ro.z + rd.y * 10.0 + g_time * 0.1));
    let dustSparkle = step(0.97, dust) * (0.3 + g_audio * 0.5);
    col = abyss + vec3<f32>(0.3, 0.2, 0.5) * dustSparkle;
    depth = 30.0;
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

  // Audio
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Smooth bass via extraBuffer
  var prevBass = extraBuffer[0];
  let smoothBass = bass_env(prevBass, bass, 0.15, 0.02);
  extraBuffer[0] = smoothBass;

  // Parameters
  let petalCurl = mix(0.5, 3.0, u.zoom_params.x);
  let bloomPulse = mix(0.1, 2.5, u.zoom_params.y);
  let coreHeat = mix(1.0, 5.0, u.zoom_params.z);
  let dispersion = mix(0.5, 2.5, u.zoom_params.w);

  // Mouse
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mouseUV = u.zoom_config.yz;
  g_mouse = vec2<f32>((mouseUV.x - 0.5) * 2.0 * aspect, (0.5 - mouseUV.y) * 2.0);

  g_time = time;
  g_audio = smoothBass;

  // Camera orbit
  let camDist = 5.0 + sin(time * 0.2) * 0.5;
  let camAng = time * 0.15 + mouseUV.x * 0.5;
  let camHeight = sin(time * 0.1) * 0.5 + (0.5 - mouseUV.y) * 0.3;
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
  let result = raymarch(ro, rd, petalCurl, bloomPulse, coreHeat, dispersion);
  var col = result.rgb;
  var alpha = result.a;

  // Volumetric plasma glow from core
  var volGlow = vec3<f32>(0.0);
  let numVol = 16;
  let volStep = 15.0 / f32(numVol);
  for (var i: i32 = 0; i < numVol; i = i + 1) {
    let vt = f32(i) * volStep + hash21(vec2<f32>(f32(gid.x + i * 73), f32(gid.y + i * 137))) * volStep;
    let vp = ro + rd * vt;
    let vfbm = fbm3(vp * 0.8 + vec3<f32>(time * 0.2, 0.0, 0.0));
    let vg = sat(0.5 - vfbm) * exp(-vt * 0.1);
    volGlow += vec3<f32>(0.4, 0.1, 0.5) * vg * (0.05 + smoothBass * 0.1);
  }
  col = col + volGlow;

  // Audio-reactive bloom on petals
  col = col + vec3<f32>(0.3, 0.0, 0.5) * smoothBass * 0.15 * alpha;

  // Temporal persistence
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  col = mix(col, prev.rgb * 0.92, 0.04);

  // Tone map
  col = acesToneMap(col * 1.2);

  // Output
  let presence = sat(alpha + length(volGlow) * 2.0);
  let finalAlpha = sat(0.05 + presence * 0.95);
  let finalDepth = sat(0.95 - alpha * 0.5);

  textureStore(writeTexture, coord, vec4<f32>(col, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(col.r, col.g, col.b, finalAlpha));
}
