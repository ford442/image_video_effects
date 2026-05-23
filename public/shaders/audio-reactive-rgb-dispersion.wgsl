// ═══════════════════════════════════════════════════════════════════
//  audio-reactive-rgb-dispersion
//  Category: post-processing
//  Features: audio-reactive, fft-bins, frequency-coupled, chromatic-aberration
//  Complexity: Medium
//  Created: 2026-05-23
//  By: copilot / P6 audio bridge
//
//  Chromatic (RGB) dispersion whose offset magnitudes and direction are
//  driven by the spectral centroid computed from the live FFT bin array.
//
//    Spectral centroid = Σ(bin_i × freq_i) / Σ(bin_i)
//      (weighted average frequency, normalised to [0, 1])
//
//  Low centroid (bass-heavy music) → tight, warm dispersion (slight red push).
//  High centroid (treble-heavy)    → wide, cool dispersion (strong cyan push).
//
//  extraBuffer layout (relevant slots):
//    [0]  bass,  [1] mid,  [2] treble
//    [5..132] FFT bins 0..127 (normalised 0–1)
//
//  Parameters:
//    param1 (zoom_params.x) : Dispersion Scale  (0=none, 1=max ~3% of width)
//    param2 (zoom_params.y) : Angle Offset       (additional rotation, 0–1→0–2π)
//    param3 (zoom_params.z) : Edge Falloff       (1=radial falloff, 0=uniform)
//    param4 (zoom_params.w) : Original Blend     (0=full effect, 1=original)
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
  config:      vec4<f32>,  // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX,      z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Scale, y=AngleOffset, z=Falloff, w=OrigBlend
  ripples: array<vec4<f32>, 50>,
};

// ── helpers ──────────────────────────────────────────────────────────────────

fn fftBin(idx: u32) -> f32 {
  let slot = idx + 5u;
  if (slot >= arrayLength(&extraBuffer)) { return 0.0; }
  return clamp(extraBuffer[slot], 0.0, 1.0);
}

/// Spectral centroid of bins [0..127], normalised to [0, 1].
/// Returns 0.5 when no audio is present (silence).
fn spectralCentroid() -> f32 {
  var weightedSum = 0.0;
  var totalPower  = 0.0;
  for (var i = 0u; i < 128u; i++) {
    let mag  = fftBin(i);
    let freq = f32(i) / 127.0;   // normalised frequency 0..1
    weightedSum += mag * freq;
    totalPower  += mag;
  }
  if (totalPower < 0.001) { return 0.5; }  // silence fallback
  return clamp(weightedSum / totalPower, 0.0, 1.0);
}

/// Total spectral energy (sum of all bins), normalised by bin count.
fn spectralEnergy() -> f32 {
  var acc = 0.0;
  for (var i = 0u; i < 128u; i++) {
    acc += fftBin(i);
  }
  return acc / 128.0;
}

// ── main ─────────────────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.z, u.config.w);
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

  let uv     = (vec2<f32>(global_id.xy) + 0.5) / res;
  let centre = vec2<f32>(0.5);

  // ── Audio analysis ───────────────────────────────────────────────
  let centroid = spectralCentroid();   // 0=bass, 1=treble
  let energy   = spectralEnergy();     // overall loudness

  // ── Parameters ──────────────────────────────────────────────────
  // Scale: higher centroid → wider dispersion
  let maxOffset  = mix(0.0, 0.03, u.zoom_params.x);
  let dispersion = maxOffset * energy * (0.3 + centroid * 0.7);

  // Dispersion direction rotates with centroid + user angle offset
  let angleBase   = centroid * 3.14159;              // 0 (bass) → π (treble)
  let angleOffset = u.zoom_params.y * 6.28318;       // full circle
  let angle       = angleBase + angleOffset;

  let dir = vec2<f32>(cos(angle), sin(angle));

  // Radial falloff: effects stronger at edges, gentler at centre
  let falloff     = u.zoom_params.z;
  let radialDist  = length(uv - centre) * 2.0;       // 0 at centre, 1 at corner
  let radialScale = mix(1.0, radialDist, falloff);

  let scaledDisp = dispersion * radialScale;

  // Per-channel offsets: R and B are displaced in opposite directions along
  // the centroid-driven direction; G is sampled at the undisplaced UV to
  // serve as a stable luminance anchor (no net hue shift at rest).
  let offR = dir * scaledDisp * (1.0 - centroid * 0.5);   // red: broader at low centroid
  let offB = -dir * scaledDisp * (0.5 + centroid * 0.5);  // blue: broader at high centroid
  // Green is anchored at the original UV — no offset needed.

  let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + offR, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;  // anchor
  let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + offB, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b;
  let a = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;

  let dispersed = vec4<f32>(r, g, b, a);
  let original  = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let output    = mix(dispersed, original, u.zoom_params.w);

  textureStore(writeTexture, global_id.xy, output);

  // Pass-through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 1.0));

  textureStore(dataTextureA, global_id.xy, output);
}
