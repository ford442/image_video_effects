// ═══════════════════════════════════════════════════════════════════
//  Prismatic Quantum-Fractal Nautilus-Engine
//  Category: generative
//  Features: raymarched, logarithmic-spiral, prismatic-glass,
//            fractal-chambers, audio-reactive, mouse-driven,
//            upgraded-rgba, depth-aware, aces-tone-map
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
  zoom_params: vec4<f32>,  // x=AuraIntensity, y=SpiralExpansion, z=FractalDepth, w=AudioReactivity
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

fn rot3Z(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
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

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
  let q = vec2<f32>(length(p.xz) - t.x, p.y);
  return length(q) - t.y;
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

// ─── Wavelength to RGB ───
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
  let g = 1.0 - abs(t - 0.45) * 2.5;
  let b = 1.0 - smoothstep(0.0, 0.45, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

// ─── Global State ───
var<private> g_time: f32;
var<private> g_audio: f32;
var<private> g_mouse: vec2<f32>;

// ─── Logarithmic Spiral Transform ───
fn spiralMap(p: vec3<f32>, expansion: f32) -> vec3<f32> {
  let r = length(p.xz);
  let theta = atan2(p.z, p.x);
  let logSpiral = log(r + 0.1) * expansion;
  let newTheta = theta + logSpiral;
  return vec3<f32>(
    r * cos(newTheta),
    p.y,
    r * sin(newTheta)
  );
}

// ─── Scene Map ───
struct MapResult {
  d: f32,
  mat: f32,
  glow: f32,
};

fn map(p_in: vec3<f32>, auraIntensity: f32, expansion: f32, fractalDepth: f32, audioReactivity: f32) -> MapResult {
  var p = p_in;

  // Mouse gravity distortion
  let mouseWorld = vec3<f32>(g_mouse.x * 4.0, (0.5 - g_mouse.y) * 4.0, 0.0);
  let mouseDist = length(p.xy - mouseWorld.xy);
  let mPower = max(0.0, 1.0 - mouseDist / 3.0) * audioReactivity;
  p = p + normalize(p - mouseWorld + vec3<f32>(0.0, 0.0, 0.5)) * mPower * 0.3;

  // Logarithmic spiral mapping
  let sp = spiralMap(p, expansion);

  // Main nautilus shell - torus-like structure along spiral
  let shellR = 2.0;
  let shellThick = 0.3 + g_audio * 0.05 * audioReactivity;
  let torusDist = sdTorus(sp - vec3<f32>(shellR, 0.0, 0.0), vec2<f32>(shellR * 0.5, shellThick));

  // Fractal inner chambers via domain repetition along spiral
  var chamberDist = 1000.0;
  let numChambers = i32(clamp(fractalDepth, 1.0, 6.0));
  for (var i: i32 = 0; i < numChambers; i++) {
    let fi = f32(i);
    let scale = pow(0.7, fi);
    let offset = fi * 1.5;
    let chamberPos = sp - vec3<f32>(shellR * scale, 0.0, offset * 0.3);
    let d = sdSphere(chamberPos, 0.2 * scale + g_audio * 0.02);
    chamberDist = smin(chamberDist, d, 0.1);
  }

  // Mechanical greebles
  let greebleBox = sdBox(sp - vec3<f32>(shellR * 0.3, 0.0, 0.0), vec3<f32>(0.15, 0.05, 0.15));
  let greeble = greebleBox - 0.02;

  // Combine shell and chambers
  var d = smin(torusDist, chamberDist, 0.15);
  d = smin(d, greeble, 0.05);

  // Glowing auroral core
  let coreDist = length(sp - vec3<f32>(shellR * 0.1, 0.0, 0.0)) - (0.15 + g_audio * 0.1 * audioReactivity);

  var mat = 1.0; // 1.0 = shell
  var glow = 0.0;

  if (coreDist < d) {
    d = coreDist;
    mat = 0.0; // 0.0 = core
    glow = auraIntensity * (2.0 + g_audio * 3.0);
  }

  return MapResult(d, mat, glow);
}

fn calcNormal(p: vec3<f32>, auraIntensity: f32, expansion: f32, fractalDepth: f32, audioReactivity: f32) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let m1 = map(p + e.xyy, auraIntensity, expansion, fractalDepth, audioReactivity);
  let m2 = map(p - e.xyy, auraIntensity, expansion, fractalDepth, audioReactivity);
  let m3 = map(p + e.yxy, auraIntensity, expansion, fractalDepth, audioReactivity);
  let m4 = map(p - e.yxy, auraIntensity, expansion, fractalDepth, audioReactivity);
  let m5 = map(p + e.yyx, auraIntensity, expansion, fractalDepth, audioReactivity);
  let m6 = map(p - e.yyx, auraIntensity, expansion, fractalDepth, audioReactivity);
  return normalize(vec3<f32>(m1.d - m2.d, m3.d - m4.d, m5.d - m6.d));
}

// ─── Chromatic Raymarch ───
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, auraIntensity: f32, expansion: f32, fractalDepth: f32, audioReactivity: f32) -> vec4<f32> {
  var t = 0.0;
  var col = vec3<f32>(0.0);
  var alpha = 0.0;
  var hit = false;
  var hitGlow = 0.0;
  var matId = 1.0;

  for (var i: i32 = 0; i < 100; i = i + 1) {
    let p = ro + rd * t;
    let res = map(p, auraIntensity, expansion, fractalDepth, audioReactivity);
    let d = res.d;

    if (d < 0.001) {
      hit = true;
      hitGlow = res.glow;
      matId = res.mat;

      let n = calcNormal(p, auraIntensity, expansion, fractalDepth, audioReactivity);
      let v = -rd;
      let cosi = max(dot(n, v), 0.0);
      let fresnel = pow(1.0 - cosi, 3.0);

      if (matId < 0.5) {
        // Core: auroral plasma
        let coreCol = vec3<f32>(0.2, 0.8, 1.0) * auraIntensity * 3.0;
        let auroraSwirl = fbm3(p * 2.0 + vec3<f32>(g_time * 0.3, 0.0, g_time * 0.2));
        col = coreCol * (0.8 + auroraSwirl * 0.4);
        col += vec3<f32>(1.0, 0.3, 0.8) * g_audio * auraIntensity;
        alpha = 0.9;
      } else {
        // Shell: prismatic glass with subsurface scattering
        // Iridescence based on view angle
        let iridPhase = cosi * 8.0;
        let irid = vec3<f32>(
          0.5 + 0.5 * cos(iridPhase + 0.0),
          0.5 + 0.5 * cos(iridPhase + 2.1),
          0.5 + 0.5 * cos(iridPhase + 4.2)
        );

        // Subsurface scattering approximation
        let sss = pow(1.0 - cosi, 2.0) * auraIntensity;
        let sssCol = vec3<f32>(0.3, 0.6, 0.9) * sss;

        // Shell base color with prismatic tint
        let shellCol = mix(vec3<f32>(0.1, 0.15, 0.2), irid * 1.5, fresnel);
        col = shellCol + sssCol;
        col += vec3<f32>(0.2, 0.5, 0.7) * g_audio * fresnel;
        alpha = 0.5 + fresnel * 0.4;
      }
      break;
    }

    if (t > 30.0) { break; }
    t = t + d * 0.7;
  }

  if (!hit) {
    // Cosmic nebula background
    let nebula = fbm3(ro + rd * 5.0 + vec3<f32>(g_time * 0.05, 0.0, 0.0));
    let nebula2 = fbm3(ro + rd * 3.0 + vec3<f32>(0.0, g_time * 0.03, g_time * 0.07));
    col = vec3<f32>(0.02, 0.01, 0.04) * (0.5 + nebula * 0.5);
    col += vec3<f32>(0.1, 0.05, 0.2) * nebula2 * (0.3 + g_audio * 0.3);

    // Stars
    let starHash = hash21(vec2<f32>(rd.x * 100.0 + g_time * 0.01, rd.y * 100.0));
    if (starHash > 0.995) {
      col += vec3<f32>(0.9, 0.9, 1.0) * (starHash - 0.995) * 200.0 * (0.8 + g_audio * 0.2);
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
  if (gid.x == 0u && gid.y == 0u) {
    extraBuffer[0] = smoothBass;
  }

  // Parameters
  let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
  let auraIntensity = mix(0.0, 1.0, zp.x);
  let expansion = mix(0.5, 2.0, zp.y);
  let fractalDepth = mix(1.0, 6.0, zp.z);
  let audioReactivity = mix(0.0, 2.0, zp.w);

  // Mouse
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mouseUV = u.zoom_config.yz;
  g_mouse = vec2<f32>((mouseUV.x - 0.5) * 2.0 * aspect, (0.5 - mouseUV.y) * 2.0);

  g_time = time;
  g_audio = smoothBass;

  // Camera orbit
  let camDist = 6.0 + sin(time * 0.15) * 0.5;
  let camAng = time * 0.12 + mouseUV.x * 0.3;
  let camHeight = sin(time * 0.08) * 0.3 + (0.5 - mouseUV.y) * 0.2;
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
  let result = raymarch(ro, rd, auraIntensity, expansion, fractalDepth, audioReactivity);
  var col = result.rgb;
  var alpha = result.a;

  // Volumetric plasma trails
  var trailGlow = vec3<f32>(0.0);
  let numVol = 12;
  let volStep = 12.0 / f32(numVol);
  for (var i: i32 = 0; i < numVol; i = i + 1) {
    let vt = f32(i) * volStep + hash21(vec2<f32>(f32(i32(gid.x) + i * 73), f32(i32(gid.y) + i * 137))) * volStep;
    let vp = ro + rd * vt;
    let vfbm = fbm3(vp * 0.6 + vec3<f32>(time * 0.15, 0.0, time * 0.1));
    let vg = sat(0.4 - vfbm) * exp(-vt * 0.08);
    trailGlow += vec3<f32>(0.3, 0.15, 0.5) * vg * (0.04 + smoothBass * 0.08);
  }
  col = col + trailGlow;

  // Audio-reactive chromatic surge
  col = col + vec3<f32>(0.1, 0.3, 0.5) * smoothBass * 0.15 * alpha;

  // Temporal persistence
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  col = mix(col, prev.rgb * 0.92, 0.04);

  // Tone map
  col = acesToneMap(col * 1.1);

  // Output
  let presence = sat(alpha + length(trailGlow) * 2.0);
  let finalAlpha = 1.0;
  let finalDepth = sat(0.95 - alpha * 0.5);

  textureStore(writeTexture, coord, vec4<f32>(col, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(col.r, col.g, col.b, finalAlpha));
}
