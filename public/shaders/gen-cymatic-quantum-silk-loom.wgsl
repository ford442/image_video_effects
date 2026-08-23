// ═══════════════════════════════════════════════════════════════════
//  Cymatic Quantum-Silk Loom
//  Category: generative
//  Features: raymarched, cymatic, silk-ribbons, iridescent,
//            audio-reactive, mouse-driven, click-reactive, upgraded-rgba,
//            depth-aware, flowing, neon-spectrum
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

fn rot3Z(a: f32) -> mat3x3<f32> {
  let c = cos(a); let s = sin(a);
  return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
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
fn sdPlane(p: vec3<f32>, n: vec3<f32>, h: f32) -> f32 {
  return dot(p, n) + h;
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

// ─── Thin-film iridescence ───
fn iridescence(cosi: f32, d: f32) -> vec3<f32> {
  let phase = cosi * d * 10.0;
  return vec3<f32>(
    0.5 + 0.5 * cos(phase + 0.0),
    0.5 + 0.5 * cos(phase + 2.1),
    0.5 + 0.5 * cos(phase + 4.2)
  );
}

// ─── Silk Ribbon SDF ───
fn silkRibbon(p: vec3<f32>, ribbonId: f32, time: f32, audio: f32, cymFreq: f32) -> f32 {
  let fi = ribbonId;
  // Base ribbon path (sine wave through space)
  let pathT = p.z * 0.5 + fi * 1.7 + time * 0.2;
  let baseY = sin(pathT) * 0.5 + fi * 0.3;
  let baseX = cos(pathT * 0.7 + fi) * 0.3;
  let ribbonP = p - vec3<f32>(baseX, baseY, 0.0);

  // Cymatic interference pattern (standing waves across ribbon)
  let cymatic = sin(ribbonP.x * cymFreq * 5.0 + time * 2.0) * cos(ribbonP.y * cymFreq * 3.0 + time * 1.5);
  let ribbonP2 = ribbonP + vec3<f32>(cymatic * 0.1, cymatic * 0.05, 0.0);

  // Domain warping for fluid flow
  let warp = vec3<f32>(
    fbm3(ribbonP2 * 2.0 + time * 0.1, 3) * 0.2,
    fbm3(ribbonP2 * 2.0 + vec3<f32>(10.0, 0.0, 0.0) + time * 0.1, 3) * 0.2,
    0.0
  );
  let ribbonP3 = ribbonP2 + warp;

  // Ribbon = thin plane-like shape
  let ribbonWidth = 0.15 + audio * 0.05;
  let ribbonThickness = 0.01 + audio * 0.005;
  let d = abs(ribbonP3.x) - ribbonWidth;
  let d2 = abs(ribbonP3.y) - ribbonThickness;
  return max(d, d2);
}

// ─── Scene Map ───
struct MapResult {
  d: f32,
  mat: f32,
  glow: f32,
};

fn map(p_in: vec3<f32>, time: f32, audio: f32, bass: f32, silkDensity: f32,
       cymFreq: f32, luminescence: f32, mousePos: vec3<f32>) -> MapResult {
  var p = p_in;

  // Mouse acts as shuttle - pinch and twist nearby silk
  let md = p - mousePos;
  let mDist = length(md);
  let shuttleRadius = 2.5;
  if (mDist < shuttleRadius) {
    let pinch = (1.0 - mDist / shuttleRadius) * sin(mDist * 4.0 - time * 2.0) * 0.4;
    let twist = rot3Z(pinch * 2.0) * md;
    p = mousePos + twist;
  }

  // Multiple silk ribbons
  var silk = 8.0;
  var numRibbons = i32(silkDensity * 8.0 + 3.0);
  for (var i: i32 = 0; i < numRibbons; i = i + 1) {
    let fi = f32(i);
    let ribbon = silkRibbon(p, fi, time, audio, cymFreq);
    silk = smin(silk, ribbon, 0.1);
  }

  // Loom frame (subtle background structure)
  let frame = sdPlane(p, vec3<f32>(0.0, 0.0, 1.0), -3.0);

  var d = silk;
  var mat = 1.0; // silk
  var glow = 0.0;

  // Silk glow based on cymatic interference
  let glowIntensity = sat(0.0 - silk) * 3.0 * luminescence;
  glow = glowIntensity * (0.5 + bass * 0.5);

  return MapResult(d, mat, glow);
}

fn calcNormal(p: vec3<f32>, time: f32, audio: f32, bass: f32, silkDensity: f32,
              cymFreq: f32, luminescence: f32, mousePos: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  let m1 = map(p + e.xyy, time, audio, bass, silkDensity, cymFreq, luminescence, mousePos);
  let m2 = map(p - e.xyy, time, audio, bass, silkDensity, cymFreq, luminescence, mousePos);
  let m3 = map(p + e.yxy, time, audio, bass, silkDensity, cymFreq, luminescence, mousePos);
  let m4 = map(p - e.yxy, time, audio, bass, silkDensity, cymFreq, luminescence, mousePos);
  let m5 = map(p + e.yyx, time, audio, bass, silkDensity, cymFreq, luminescence, mousePos);
  let m6 = map(p - e.yyx, time, audio, bass, silkDensity, cymFreq, luminescence, mousePos);
  return normalize(vec3<f32>(m1.d - m2.d, m3.d - m4.d, m5.d - m6.d));
}

// ─── Raymarch ───
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time: f32, audio: f32, bass: f32, mids: f32,
            treble: f32, silkDensity: f32, cymFreq: f32, luminescence: f32,
            mousePos: vec3<f32>) -> vec4<f32> {
  var t = 0.0;
  var col = vec3<f32>(0.0);
  var alpha = 0.0;
  var hit = false;
  var hitGlow = 0.0;

  for (var i: i32 = 0; i < 80; i = i + 1) {
    let p = ro + rd * t;
    let res = map(p, time, audio, bass, silkDensity, cymFreq, luminescence, mousePos);
    let d = res.d;

    if (d < 0.003) {
      hit = true;
      hitGlow = res.glow;
      let n = calcNormal(p, time, audio, bass, silkDensity, cymFreq, luminescence, mousePos);
      let viewAngle = dot(-rd, n);

      // Thin-film iridescence on silk
      let irid = iridescence(abs(viewAngle), 1.0 + bass * 0.5);

      // Neon spectrum: magenta -> cyan -> gold based on position and audio
      let spectrumPos = sin(p.z * 0.5 + time * 0.3) * 0.5 + 0.5;
      let neonCol = mix(
        mix(vec3<f32>(1.0, 0.0, 0.8), vec3<f32>(0.0, 1.0, 1.0), spectrumPos),
        vec3<f32>(1.0, 0.8, 0.0),
        sin(p.x + time * 0.5) * 0.5 + 0.5
      );

      // Combine iridescence with neon base
      col = neonCol * (0.5 + irid * 0.5) * (1.0 + hitGlow * 2.0);

      // Subsurface scattering (translucent silk glow)
      let sss = pow(sat(-viewAngle), 3.0) * hitGlow * 2.0;
      col = col + vec3<f32>(0.8, 0.6, 1.0) * sss;

      // Bass-reactive pulse
      col = col * (1.0 + bass * 0.3);

      // Treble sparkles on silk edges
      let sparkle = pow(sat(1.0 - abs(viewAngle)), 8.0) * treble * 2.0;
      col = col + vec3<f32>(1.0, 0.9, 0.7) * sparkle;

      alpha = sat(0.4 + hitGlow * 0.4);
      break;
    }

    if (t > 20.0) { break; }
    t = t + d * 0.7;

    // Volumetric glow from silk
    if (res.glow > 0.01 && t < 12.0) {
      let volCol = vec3<f32>(0.4, 0.2, 0.6) * res.glow * 0.02 * exp(-t * 0.1);
      col = col + volCol;
    }
  }

  if (!hit) {
    // Dark loom background with subtle cymatic pattern
    col = vec3<f32>(0.02, 0.01, 0.03);
    let cymBg = sin(rd.x * cymFreq * 3.0 + time) * sin(rd.y * cymFreq * 2.0 + time * 0.7);
    col = col + vec3<f32>(0.1, 0.05, 0.15) * pow(abs(cymBg), 4.0) * (0.1 + bass * 0.1);
    // Distant silk glow
    col = col + vec3<f32>(0.2, 0.1, 0.3) * (0.03 + bass * 0.03) * sat(0.2 / (abs(rd.z) + 0.1));
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
  let silkDensity = mix(0.1, 1.0, clamp(u.zoom_params.x, 0.0, 1.0));
  let cymFreq = mix(0.1, 5.0, clamp(u.zoom_params.y, 0.0, 1.0));
  let luminescence = mix(0.0, 2.0, clamp(u.zoom_params.z, 0.0, 1.0));
  let weaveSpeed = mix(0.1, 3.0, clamp(u.zoom_params.w, 0.0, 1.0));
  let sceneTime = time * weaveSpeed;

  // Mouse handling: screen top = UP in 3D
  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mouseUV = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let mouseY = mouseUV.y;
  let heldGain = select(1.0, 1.8, u.zoom_config.w > 0.5);
  let mousePos = vec3<f32>(
    (mouseUV.x * 2.0 - 1.0) * 3.0 * aspect / heldGain,
    (mouseUV.y * 2.0 - 1.0) * 3.0 / heldGain,
    0.0
  );

  // Clicks pluck the loom: finite radial fronts raise cymatic frequency and
  // luminescence without leaving stale ripple entries active indefinitely.
  var clickEnergy = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age < 0.0 || age > 2.4) { continue; }
    let rippleDistance = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    clickEnergy += exp(-abs(rippleDistance - age * 0.24) * 72.0) * exp(-age * 1.2);
  }
  clickEnergy = clamp(clickEnergy, 0.0, 1.0);

  // Camera (looking at the loom)
  let camDist = 4.0 + sin(sceneTime * 0.1) * 0.3;
  let camAng = sceneTime * 0.15 + mouseUV.x * 0.4;
  let camHeight = mouseY * 0.5;
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
  let activeCymFreq = cymFreq * (1.0 + clickEnergy * 0.28 + mids * 0.08);
  let activeLuminescence = luminescence * heldGain + clickEnergy * 0.7;
  let result = raymarch(ro, rd, sceneTime, audio, bass, mids, treble, silkDensity, activeCymFreq, activeLuminescence, mousePos);
  var col = result.rgb;
  var alpha = result.a;

  // Audio-reactive color enhancement
  col = col + vec3<f32>(0.3, 0.0, 0.2) * bass * 0.15;
  col = col + vec3<f32>(0.0, 0.2, 0.3) * mids * 0.1;
  col = col + vec3<f32>(0.2, 0.15, 0.0) * treble * 0.1;

  // Temporal persistence
  let prev = textureLoad(dataTextureC, coord, 0);
  col = mix(col, prev.rgb * 0.94, 0.03);
  col += vec3<f32>(0.55, 0.25, 0.9) * clickEnergy * (0.18 + treble * 0.22);

  // Tone map
  col = acesToneMap(col * 1.4);

  let inputDepth = textureLoad(readDepthTexture, coord, 0).r;
  alpha = clamp(max(alpha, clickEnergy * 0.24 + length(col) * 0.16), 0.0, 1.0);
  let finalDepth = mix(inputDepth, sat(0.95 - alpha * 0.3), alpha);
  let finalColor = vec4<f32>(col, alpha);

  textureStore(writeTexture, coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, finalColor);
}
