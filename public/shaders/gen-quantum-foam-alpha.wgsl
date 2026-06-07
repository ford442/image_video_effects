// ═══════════════════════════════════════════════════════════════════
//  Quantum Foam Alpha
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: Very High
//  Description: Particle positions rendered as quantum probability clouds.
//    Alpha encodes Heisenberg uncertainty — high uncertainty creates diffuse
//    translucent clouds, low uncertainty yields sharp opaque peaks.
//    Mouse measurement collapses the wavefunction locally.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=CloudDensity, y=Uncertainty, z=VacuumEnergy, w=CollapseStrength
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265358979323846;

// ── Hash for pseudo-particles ─────────────────────────────────────
fn hash_q(n: f32) -> f32 {
  return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

fn hash2_q(n: f32) -> vec2<f32> {
  return vec2<f32>(hash_q(n), hash_q(n + 57.3));
}

fn hash3_q(n: f32) -> vec3<f32> {
  return vec3<f32>(hash_q(n), hash_q(n + 33.1), hash_q(n + 71.5));
}

// ── Value noise for vacuum fluctuations ───────────────────────────
fn vnoise_q(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let n00 = fract(sin(dot(i + vec2<f32>(0.0, 0.0), vec2<f32>(127.1, 311.7))) * 43758.5453);
  let n10 = fract(sin(dot(i + vec2<f32>(1.0, 0.0), vec2<f32>(127.1, 311.7))) * 43758.5453);
  let n01 = fract(sin(dot(i + vec2<f32>(0.0, 1.0), vec2<f32>(127.1, 311.7))) * 43758.5453);
  let n11 = fract(sin(dot(i + vec2<f32>(1.0, 1.0), vec2<f32>(127.1, 311.7))) * 43758.5453);
  return mix(mix(n00, n10, u.x), mix(n01, n11, u.x), u.y);
}

fn fbm_q(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i = 0; i < 4; i++) {
    v += a * vnoise_q(pp);
    pp = pp * 2.0 + vec2<f32>(3.1, 1.7);
    a *= 0.5;
  }
  return v;
}

// ── Gaussian probability cloud ────────────────────────────────────
fn probCloud(p: vec2<f32>, center: vec2<f32>, sigma: f32) -> f32 {
  let d2 = dot(p - center, p - center);
  return exp(-d2 / (2.0 * sigma * sigma));
}

// ── Interference pattern ──────────────────────────────────────────
fn interference(p: vec2<f32>, c1: vec2<f32>, c2: vec2<f32>, sigma: f32, t: f32) -> f32 {
  let d1 = length(p - c1);
  let d2 = length(p - c2);
  let wave1 = sin(d1 * 20.0 - t * 3.0) * probCloud(p, c1, sigma);
  let wave2 = sin(d2 * 20.0 - t * 3.0 + PI) * probCloud(p, c2, sigma);
  return wave1 + wave2;
}

// ── Audio smoothing ───────────────────────────────────────────────
fn env_q(prev: f32, val: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, val > prev);
  return mix(prev, val, k);
}

// ── HSV to RGB ────────────────────────────────────────────────────
fn hsv2rgb_q(h: f32, s: f32, v: f32) -> vec3<f32> {
  let c = v * s;
  let h6 = fract(h) * 6.0;
  let x = c * (1.0 - abs(fract(h6 * 0.5) * 2.0 - 1.0));
  var rgb = vec3<f32>(0.0);
  if (h6 < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
  else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + (v - c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

  let uv = vec2<f32>(gid.xy) / res;
  let aspect = res.x / res.y;
  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let rms = plasmaBuffer[0].w;

  // Mouse for wavefunction collapse
  let mouse = u.zoom_config.yz;
  let mPos = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDown = u.zoom_config.w > 0.5;

  // Parameters
  let cloudDensity = u.zoom_params.x * 40.0 + 10.0;
  let uncertaintyBase = u.zoom_params.y * 0.08 + 0.02;
  let vacuumEnergy = u.zoom_params.z;
  let collapseStrength = u.zoom_params.w * 2.0 + 0.5;

  // Audio smoothing
  let bassSmooth = env_q(0.5, bass, 0.08, 0.04);
  let midsSmooth = env_q(0.4, mids, 0.1, 0.05);

  // ── Temporal feedback for vacuum energy fluctuations ────────────
  let prevFrame = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
  let prevVacuum = prevFrame.r;

  // ── Vacuum fluctuation noise ────────────────────────────────────
  let vacNoise = fbm_q(p * 8.0 + time * 0.3);
  let vacFluctuation = vacNoise * (1.0 + bassSmooth * vacuumEnergy * 3.0);
  let vacuumField = env_q(prevVacuum, vacFluctuation, 0.02, 0.015);

  // ── Particle pair system ────────────────────────────────────────
  let numPairs = i32(midsSmooth * 8.0 + 4.0);
  var totalProb = 0.0;
  var colorAccum = vec3<f32>(0.0);
  var totalUncertainty = 0.0;

  for (var i = 0; i < numPairs; i++) {
    let fi = f32(i);
    let seed = fi * 19.7;

    // Particle position - Lissajous-like orbit
    let orbitT = time * 0.2 + fi * 1.3;
    let a = hash_q(seed) * 2.0 + 1.0;
    let b = hash_q(seed + 1.0) * 2.0 + 1.0;
    let basePos = vec2<f32>(
      sin(orbitT * a) * 0.35 * aspect,
      cos(orbitT * b) * 0.35
    ) + (hash2_q(seed + 3.0) - 0.5) * 0.1;

    // Pair creation - particles exist as correlated pairs
    let pairOffset = vec2<f32>(
      cos(orbitT * 1.5 + fi) * 0.06,
      sin(orbitT * 1.2 + fi) * 0.06
    ) * (1.0 + midsSmooth);

    let p1 = basePos + pairOffset;
    let p2 = basePos - pairOffset;

    // Uncertainty varies with vacuum energy
    var sigma = uncertaintyBase * (1.0 + vacuumField * 0.5);

    // Wavefunction collapse near mouse
    let dMouse1 = length(p - p1);
    let dMouse2 = length(p - p2);
    let collapseDist = length(p - mPos);
    var collapseFactor = exp(-collapseDist * collapseDist * 4.0);
    if (mouseDown) {
      collapseFactor = collapseFactor * 1.5 + 0.3;
    }

    // Collapse reduces uncertainty (sharpens peak)
    let collapsedSigma = sigma * (1.0 - collapseFactor * 0.7);
    let localSigma = mix(sigma, collapsedSigma, collapseFactor);

    // Probability clouds
    let prob1 = probCloud(p, p1, localSigma);
    let prob2 = probCloud(p, p2, localSigma);

    // Interference between pair
    let interf = interference(p, p1, p2, localSigma, time);
    let pairProb = prob1 + prob2 + interf * 0.3;

    // Color based on energy level
    let energy = hash_q(seed + 5.0) + vacuumField * 0.3;
    let hue = fract(energy * 0.3 + fi / f32(numPairs) + time * 0.02);
    let sat = 0.6 + prob1 * 0.4;
    let val = 0.5 + pairProb * 2.0;
    let pColor = hsv2rgb_q(hue, sat, val);

    totalProb += pairProb;
    colorAccum += pColor * pairProb;
    totalUncertainty += localSigma * pairProb;
  }

  // ── Background vacuum energy glow ───────────────────────────────
  let bgGlow = vacuumField * 0.15;
  let bgHue = fract(time * 0.01 + length(p) * 0.3);
  let bgColor = hsv2rgb_q(bgHue, 0.4, 0.05 + bgGlow);

  // ── Quantum foam texture ────────────────────────────────────────
  let foamScale = 30.0;
  let foam = fbm_q(p * foamScale + time * 0.5 + vacuumField);
  let foamColor = hsv2rgb_q(fract(time * 0.03 + 0.5), 0.3, foam * 0.1);

  // ── Combine ─────────────────────────────────────────────────────
  var col = bgColor + foamColor;
  if (totalProb > 0.001) {
    col += colorAccum / totalProb * min(totalProb * 1.5, 1.2);
  }

  // Vacuum energy highlights
  col += hsv2rgb_q(fract(time * 0.05 + 0.2), 0.5, vacuumField * 0.2);

  // Collapse visual indicator
  let collapseGlow = exp(-length(p - mPos) * length(p - mPos) * 3.0) * 0.3;
  col += hsv2rgb_q(fract(time * 0.08), 0.3, collapseGlow);

  col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
  col = pow(col, vec3<f32>(0.4545));

  // ── Alpha encoding ──────────────────────────────────────────────
  // Alpha = uncertainty. High uncertainty = diffuse/translucent.
  // Low uncertainty = sharp/opaque.
  let avgUncertainty = select(totalUncertainty / totalProb, uncertaintyBase, totalProb < 0.001);
  let uncertaintyNorm = avgUncertainty / uncertaintyBase;

  // High uncertainty reduces alpha (diffuse), low uncertainty increases it
  var alpha = clamp(totalProb * 2.0, 0.0, 1.0);
  alpha = alpha * mix(0.95, 0.25, smoothstep(0.5, 2.0, uncertaintyNorm));

  // Vacuum foam adds faint translucency everywhere
  alpha = max(alpha, foam * 0.08);

  // Collapse region becomes more opaque
  let collapseAlphaBoost = collapseGlow * 0.4;
  alpha = mix(alpha, min(alpha + collapseAlphaBoost, 0.9), collapseGlow * 2.0);

  alpha = clamp(alpha, 0.0, 0.95);

  let outCol = vec4<f32>(acesToneMap(col * 1.1), alpha);
  textureStore(writeTexture, gid.xy, outCol);
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(vacuumField, totalProb, avgUncertainty, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(alpha, 0.0, 0.0, 0.0));
}
