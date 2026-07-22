// ═══════════════════════════════════════════════════════════════════
//  Magnetic Flux Garden
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, aces-tone-map, depth-aware
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-06
//  Optimized: 2026-07-22 (curl-noise line weave, IQ palette bloom,
//             feedback clamp, rewired slider mappings)
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

fn sat(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

// ── Value noise (canonical form) ─────────────────────────────────
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let s = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), s.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), s.x),
    s.y
  );
}

// ── Curl noise: perpendicular gradient of value noise ────────────
//  Divergence-free, so flux lines weave organically without clumping.
fn curlNoise(p: vec2<f32>) -> vec2<f32> {
  let e = 0.1;
  let nT = valueNoise(p + vec2<f32>(0.0, e));
  let nB = valueNoise(p - vec2<f32>(0.0, e));
  let nR = valueNoise(p + vec2<f32>(e, 0.0));
  let nL = valueNoise(p - vec2<f32>(e, 0.0));
  let grad = vec2<f32>(nR - nL, nT - nB) / (2.0 * e);
  return vec2<f32>(grad.y, -grad.x);
}

// ── IQ cosine palette ────────────────────────────────────────────
//  Blended into the bloom layer at low mix; teal/magenta field colors
//  stay dominant.
fn iqCosPalette(t: f32) -> vec3<f32> {
  let a = vec3<f32>(0.45, 0.38, 0.55);
  let b = vec3<f32>(0.35, 0.30, 0.35);
  let c = vec3<f32>(1.00, 1.00, 1.00);
  let d = vec3<f32>(0.55, 0.20, 0.75);
  return a + b * cos(6.28318 * (c * t + d));
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
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  // ── Slider wiring (zoom_params.x/y/z/w) ────────────────────────
  //  x fieldLines    → number of dipole field lines traced
  //  y fieldStrength → dipole inverse-square gain + line brightness
  //  z organic       → curl-noise weave amplitude (plus harmonic warp)
  //  w bloom         → glow gain + IQ palette mix on the bloom layer
  let fieldLines = mix(4.0, 24.0, u.zoom_params.x);
  let dipoleGain = mix(0.4, 2.2, u.zoom_params.y);
  let lineGain = mix(0.3, 1.8, u.zoom_params.y);
  let curlAmp = u.zoom_params.z * 0.45;
  let warpAmp = u.zoom_params.z * 0.15;
  let bloomGain = mix(0.2, 1.5, u.zoom_params.w);
  let paletteMix = 0.3 * sat(u.zoom_params.w * 1.4);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  let poleA = mouse * 0.5;
  let poleB = -mouse * 0.3;

  var flux = 0.0;
  var curl = 0.0;
  var seed = 0.0;

  let lineCount = u32(max(fieldLines, 1.0));
  let curlTime = time * 0.25 + bass * 0.4;

  for (var i = 0u; i < lineCount; i = i + 1u) {
    let fi = f32(i);
    let angle = fi * 6.28318 / fieldLines;
    let dir = vec2<f32>(cos(angle), sin(angle));
    let start = poleA + dir * 0.02;

    var pos = start;
    var lineInt = 0.0;
    for (var step = 0u; step < 40u; step = step + 1u) {
      let toB = poleB - pos;
      let toA = poleA - pos;
      let distA = length(toA);
      let distB = length(toB);
      if (distA < 0.02 || distB < 0.02) { break; }

      // Dipole field, strength scaled by Field Strength slider
      let fieldDir = normalize(
        toA / (distA * distA + 0.001) - toB / (distB * distB + 0.001)
      ) * dipoleGain;

      // Harmonic organic warp (original motion)
      let organicWarp = vec2<f32>(
        sin(pos.y * 8.0 + time * 0.5 + fi) * warpAmp,
        cos(pos.x * 6.0 + time * 0.3 + fi * 1.3) * warpAmp
      );

      // Curl-noise perturbation: derivative-of-noise offset so lines
      // weave organically instead of lying perfectly smooth.
      let curlOff = curlNoise(pos * 3.0 + vec2<f32>(curlTime, fi * 0.37)) * curlAmp;

      pos = pos + (fieldDir + organicWarp + curlOff) * 0.02;

      let pd = length(p - pos);
      lineInt = lineInt + exp(-pd * pd * 800.0);
    }
    flux = flux + lineInt;
    let curlAngle = angle + time * 0.2 * (1.0 + bass * 0.5);
    let curlPos = poleA + vec2<f32>(cos(curlAngle), sin(curlAngle)) * (0.1 + fi * 0.02);
    curl = curl + exp(-length(p - curlPos) * length(p - curlPos) * 300.0) * (0.5 + mids);
  }

  seed = step(0.995 - treble * 0.02, hash21(floor(uv * 250.0 + time * 0.08))) * flux;

  // ── Chromatic layers: teal flux lines, magenta curls, gold seeds ──
  var color = vec3<f32>(0.01, 0.01, 0.02);
  color = color + vec3<f32>(0.1, 0.85, 0.75) * flux * lineGain * bloomGain * (1.0 + bass * 0.2);

  // Bloom layer: magenta base blended toward IQ cosine palette at low
  // mix (~0.3), param-scaled by the Bloom slider; magenta stays dominant.
  let bloomAmt = curl * bloomGain * 0.5 * (1.0 + mids * 0.15);
  let palCol = iqCosPalette(curl * 0.35 + flux * 0.15 + time * 0.03);
  let bloomCol = mix(vec3<f32>(0.9, 0.35, 0.75), palCol, paletteMix);
  color = color + bloomCol * bloomAmt;

  color = color + vec3<f32>(1.0, 0.85, 0.25) * seed * (0.4 + treble);

  // ── Temporal feedback with pre-tint clamp (luma-echo-warp lesson) ─
  //  Clamp the accumulated frame at ~1.2 before tinting so bloom trails
  //  cannot blow out over time.
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let prevClamped = min(prev.rgb, vec3<f32>(1.2));
  color = mix(color, prevClamped * 0.9, 0.025 + bass * 0.01);

  let presence = sat(flux * 0.85 + curl * 0.6 + seed * 0.9);
  let alpha = sat(0.1 + presence * 0.9);
  let depth = sat(0.92 - flux * 0.5 - curl * 0.3);

  color = acesToneMap(color * 1.1);
  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(flux, curl, seed, alpha));
}
