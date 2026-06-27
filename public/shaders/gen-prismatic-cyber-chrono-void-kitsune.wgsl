// ═══════════════════════════════════════════════════════════════════
//  Prismatic Cyber-Chrono Void-Kitsune
//  Category: generative
//  Features: raymarched, kitsune, nine-tails, cyber-glass,
//            chrono-runes, volumetric-rift, audio-reactive,
//            mouse-driven, upgraded-rgba, depth-aware, aces-tone-map
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
  zoom_params: vec4<f32>,  // x=TailDispersion, y=RiftDensity, z=RuneIntensity, w=GlassRefraction
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

fn rot3X(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
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

// ─── SDF Helpers ───
fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = sat(0.5 + 0.5 * (b - a) / k);
  return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
  return length(p) - r;
}

fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
  let k0 = length(p / r);
  let k1 = length(p / (r * r));
  return k0 * (k0 - 1.0) / k1;
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
  let q = abs(p) - b;
  return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// ─── Bass Envelope ───
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

// ─── ACES Tone Map ───
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ─── Blackbody color ramp for rift ───
fn blackbody(t: f32) -> vec3<f32> {
  let tt = clamp(t, 0.0, 1.0);
  let r = smoothstep(0.0, 0.5, tt) + smoothstep(0.5, 1.0, tt) * 0.8;
  let g = smoothstep(0.2, 0.7, tt);
  let b = smoothstep(0.5, 1.0, tt) * 0.9;
  return vec3<f32>(r, g, b);
}

// ─── Global State ───
var<private> g_time: f32;
var<private> g_audio: f32;
var<private> g_mouse: vec2<f32>;

// ─── Tail Spline Path ───
fn tailPath(t: f32, tailIndex: f32, dispersion: f32) -> vec3<f32> {
  let phase = tailIndex * 0.7;
  let freq = 1.0 + tailIndex * 0.2;
  let amp = 1.5 * dispersion;
  return vec3<f32>(
    sin(t * freq + phase + g_time * 0.5) * amp * (1.0 - t * 0.3),
    cos(t * freq * 0.8 + phase * 1.3 + g_time * 0.4) * amp * 0.6 * (1.0 - t * 0.2),
    t * 3.0 - 1.0
  );
}

// ─── Scene Map ───
struct MapResult {
  d: f32,
  mat: f32,
  glow: f32,
};

fn map(p_in: vec3<f32>, tailDispersion: f32, riftDensity: f32, runeIntensity: f32, glassRefraction: f32) -> MapResult {
  var p = p_in;

  // Mouse steers the kitsune's bounding trajectory
  let mouseWorld = vec3<f32>(g_mouse.x * 2.0, (0.5 - g_mouse.y) * 2.0, 0.0);
  let mouseDist = length(p.xy - mouseWorld.xy);
  let steer = max(0.0, 1.0 - mouseDist / 4.0) * 0.3;
  let steerRot = rot3Z(steer * g_mouse.x);
  p = steerRot * p;
  p.y += steer * (0.5 - g_mouse.y);

  // ─── Body: ellipsoid + capsule + box smoothed ───
  let bodyPos = vec3<f32>(0.0, 0.0, 0.0);
  let bodyEllip = sdEllipsoid(p - bodyPos, vec3<f32>(0.6, 0.4, 1.0));
  let neckPos = vec3<f32>(0.0, 0.2, 0.8);
  let neck = sdCapsule(p, bodyPos, neckPos, 0.25);
  let headBox = sdBox(p - vec3<f32>(0.0, 0.3, 1.3), vec3<f32>(0.35, 0.3, 0.4));
  var d = smin(bodyEllip, neck, 0.3);
  d = smin(d, headBox, 0.2);

  // Biomechanical armor plating detail
  let armorNoise = vnoise3(p * 8.0 + vec3<f32>(g_time * 0.1, 0.0, 0.0)) * 0.03;
  d = d - armorNoise;

  // ─── Nine Tails ───
  var tailDist = 1000.0;
  let numTails = 9;
  for (var i: i32 = 0; i < numTails; i++) {
    let fi = f32(i);
    // Spline approximation with segments
    var segDist = 1000.0;
    let numSeg = 8;
    for (var j: i32 = 0; j < numSeg; j++) {
      let t0 = f32(j) / f32(numSeg);
      let t1 = f32(j + 1) / f32(numSeg);
      let a = tailPath(t0, fi, tailDispersion);
      let b = tailPath(t1, fi, tailDispersion);
      let segR = 0.12 * (1.0 - t0 * 0.6) * (1.0 + g_audio * 0.2);
      let sd = sdCapsule(p, a, b, segR);
      segDist = min(segDist, sd);
    }
    tailDist = smin(tailDist, segDist, 0.15);
  }

  if (tailDist < d) {
    d = tailDist;
  }

  // ─── Material assignment ───
  var mat = 1.0; // 1.0 = cyber-glass body
  var glow = 0.0;

  // Chrono-runes etched on body surface
  let runePattern = vnoise3(p * 15.0 + vec3<f32>(g_time * 0.5, 0.0, 0.0));
  let runeLine = abs(runePattern - 0.5);
  if (runeLine < 0.05 && d < 0.05) {
    glow = runeIntensity * (1.0 + g_audio * 2.0);
    mat = 2.0; // 2.0 = rune emission
  }

  // ─── Volumetric Aether-Rift (background tube) ───
  let riftRadius = 4.0;
  let riftThick = 1.5 * riftDensity;
  let tubeDist = abs(length(p.xy) - riftRadius) - riftThick;
  let gyroid = sin(p.x * 2.0) * cos(p.y * 2.0) + sin(p.y * 2.0) * cos(p.z * 2.0) + sin(p.z * 2.0) * cos(p.x * 2.0);
  let riftDist = tubeDist + gyroid * 0.2 * riftDensity;

  // Only use rift if it's closer and we're not inside the body
  if (riftDist < d && tubeDist < riftThick * 2.0) {
    // Don't overwrite body
    if (d > 0.3) {
      d = riftDist;
      mat = 3.0; // 3.0 = rift volumetric
      glow = riftDensity * 0.3;
    }
  }

  return MapResult(d, mat, glow);
}

fn calcNormal(p: vec3<f32>, tailDispersion: f32, riftDensity: f32, runeIntensity: f32, glassRefraction: f32) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let m1 = map(p + e.xyy, tailDispersion, riftDensity, runeIntensity, glassRefraction);
  let m2 = map(p - e.xyy, tailDispersion, riftDensity, runeIntensity, glassRefraction);
  let m3 = map(p + e.yxy, tailDispersion, riftDensity, runeIntensity, glassRefraction);
  let m4 = map(p - e.yxy, tailDispersion, riftDensity, runeIntensity, glassRefraction);
  let m5 = map(p + e.yyx, tailDispersion, riftDensity, runeIntensity, glassRefraction);
  let m6 = map(p - e.yyx, tailDispersion, riftDensity, runeIntensity, glassRefraction);
  return normalize(vec3<f32>(m1.d - m2.d, m3.d - m4.d, m5.d - m6.d));
}

// ─── Raymarch ───
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, tailDispersion: f32, riftDensity: f32, runeIntensity: f32, glassRefraction: f32) -> vec4<f32> {
  var t = 0.0;
  var col = vec3<f32>(0.0);
  var alpha = 0.0;
  var hit = false;
  var matId = 1.0;
  var hitGlow = 0.0;

  for (var i: i32 = 0; i < 100; i = i + 1) {
    let p = ro + rd * t;
    let res = map(p, tailDispersion, riftDensity, runeIntensity, glassRefraction);
    let d = res.d;

    if (d < 0.001) {
      hit = true;
      matId = res.mat;
      hitGlow = res.glow;

      let n = calcNormal(p, tailDispersion, riftDensity, runeIntensity, glassRefraction);
      let v = -rd;
      let lightDir = normalize(vec3<f32>(1.0, 1.5, -1.0));
      let diff = max(dot(n, lightDir), 0.0);
      let cosi = max(dot(n, v), 0.0);
      let fresnel = pow(1.0 - cosi, 3.0);

      if (matId < 1.5) {
        // Cyber-glass armor: faux-refraction + iridescence
        // Sample background noise distorted by normal
        let refractDir = rd - n * glassRefraction * 0.3;
        let bgNoise = fbm3(p * 0.5 + refractDir * 2.0 + vec3<f32>(g_time * 0.1, 0.0, 0.0));

        // Iridescent chromatic aberration
        let iridPhase = cosi * 6.0 + g_time;
        let irid = vec3<f32>(
          0.5 + 0.5 * cos(iridPhase + 0.0),
          0.5 + 0.5 * cos(iridPhase + 2.1),
          0.5 + 0.5 * cos(iridPhase + 4.2)
        );

        let glassBase = vec3<f32>(0.15, 0.2, 0.3);
        let glassCol = mix(glassBase, irid * 1.5, fresnel * glassRefraction);
        glassCol += vec3<f32>(0.1, 0.15, 0.25) * bgNoise * glassRefraction;

        col = glassCol * (diff * 0.5 + 0.3) + irid * fresnel * 0.4;
        col += vec3<f32>(0.2, 0.1, 0.4) * g_audio * fresnel;
        alpha = 0.5 + fresnel * 0.3;
      } else if (matId < 2.5) {
        // Chrono-runes: emissive neon
        let runeCol = mix(
          vec3<f32>(0.8, 0.0, 1.0), // magenta
          vec3<f32>(1.0, 0.9, 0.0), // gold on bass
          g_audio
        );
        col = runeCol * hitGlow;
        alpha = 0.95;
      } else {
        // Rift volumetric: Blackbody color ramp
        let riftT = clamp(length(p.xy) / 5.0, 0.0, 1.0);
        let riftCol = blackbody(riftT) * riftDensity * 0.8;
        // Edge brightening
        let edge = pow(1.0 - cosi, 2.0);
        riftCol += vec3<f32>(0.8, 0.4, 0.6) * edge * riftDensity;
        col = riftCol;
        alpha = 0.3;
      }
      break;
    }

    if (t > 25.0) { break; }
    t = t + d * 0.7;
  }

  if (!hit) {
    // Deep void background
    let voidNoise = fbm3(ro + rd * 5.0 + vec3<f32>(g_time * 0.05, 0.0, 0.0));
    col = vec3<f32>(0.01, 0.005, 0.015) * (0.5 + voidNoise * 0.3);
    // Distant stars
    let starHash = hash21(vec2<f32>(rd.x * 200.0 + g_time * 0.01, rd.y * 200.0));
    if (starHash > 0.997) {
      col += vec3<f32>(0.9, 0.85, 1.0) * (starHash - 0.997) * 300.0;
    }
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
  let tailDispersion = mix(0.1, 3.0, u.zoom_params.x);
  let riftDensity = mix(0.1, 2.0, u.zoom_params.y);
  let runeIntensity = mix(0.5, 5.0, u.zoom_params.z);
  let glassRefraction = mix(0.0, 1.0, u.zoom_params.w);

  // Mouse
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mouseUV = u.zoom_config.yz;
  g_mouse = vec2<f32>((mouseUV.x - 0.5) * 2.0 * aspect, (0.5 - mouseUV.y) * 2.0);

  g_time = time;
  g_audio = smoothBass;

  // Camera follows the bounding trajectory
  let camDist = 6.0 + sin(time * 0.12) * 0.5;
  let camAng = time * 0.1 + mouseUV.x * 0.4;
  let camHeight = sin(time * 0.08) * 0.4 + (0.5 - mouseUV.y) * 0.3;
  let ro = vec3<f32>(cos(camAng) * camDist, camHeight, sin(camAng) * camDist);
  let ta = vec3<f32>(0.0, 0.0, 0.5);
  let ww = normalize(ta - ro);
  let uu = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), ww));
  let vv = cross(ww, uu);

  // Ray direction
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  let rd = normalize(p.x * uu + p.y * vv + 2.5 * ww);

  // Raymarch
  let result = raymarch(ro, rd, tailDispersion, riftDensity, runeIntensity, glassRefraction);
  var col = result.rgb;
  var alpha = result.a;

  // Gravitational plasma dust pulled into tail vortex
  var dustGlow = vec3<f32>(0.0);
  let numDust = 12;
  let dustStep = 10.0 / f32(numDust);
  for (var i: i32 = 0; i < numDust; i = i + 1) {
    let dt = f32(i) * dustStep + hash21(vec2<f32>(f32(gid.x + i * 73), f32(gid.y + i * 137))) * dustStep;
    let dp = ro + rd * dt;
    let dhash = hash3(dp * 3.0 + vec3<f32>(time * 0.3, 0.0, 0.0));
    if (dhash > 0.92) {
      let dustBright = (dhash - 0.92) * 12.0;
      dustGlow += vec3<f32>(0.9, 0.6, 0.3) * dustBright * (0.03 + smoothBass * 0.06) * exp(-dt * 0.1);
    }
  }
  col = col + dustGlow;

  // Audio-reactive tail flare
  col = col + vec3<f32>(0.5, 0.0, 0.8) * smoothBass * 0.12 * alpha;

  // Temporal persistence
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  col = mix(col, prev.rgb * 0.92, 0.04);

  // Tone map
  col = acesToneMap(col * 1.1);

  // Output
  let presence = sat(alpha + length(dustGlow) * 2.0);
  let finalAlpha = sat(0.05 + presence * 0.95);
  let finalDepth = sat(0.95 - alpha * 0.5);

  textureStore(writeTexture, coord, vec4<f32>(col, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(col.r, col.g, col.b, finalAlpha));
}
