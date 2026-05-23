// ═══════════════════════════════════════════════════════════════════
//  audio-reactive-pyramid
//  Category: post-processing
//  Features: audio-reactive, fft-bins, frequency-coupled, pyramid
//  Complexity: Medium
//  Created: 2026-05-23
//  By: copilot / P6 audio bridge
//
//  Three-level Laplacian-style sharpening pyramid whose band
//  intensities are driven by matching FFT frequency bands:
//    Level 0 (coarse detail)  ← bins  0..12   (bass,  ~0–1.4 kHz)
//    Level 1 (mid detail)     ← bins 13..50   (mid,   ~1.4–5.4 kHz)
//    Level 2 (fine detail)    ← bins 51..127  (treble, ~5.4–22 kHz)
//
//  Each level is approximated by a Difference-of-Gaussians (DoG):
//    level_n = blurN(image) − blurN+1(image)
//  and then amplified by the per-band audio energy before being
//  added back to the base (blurriest) image.
//
//  extraBuffer layout (relevant slots):
//    [0]  bass,  [1] mid,  [2] treble
//    [5..132] FFT bins 0..127 (normalised 0–1)
//
//  Parameters:
//    param1 (zoom_params.x) : Bass Gain   (low-detail amplitude multiplier)
//    param2 (zoom_params.y) : Mid Gain    (mid-detail amplitude multiplier)
//    param3 (zoom_params.z) : Treble Gain (high-detail amplitude multiplier)
//    param4 (zoom_params.w) : Overall Blend (mix original vs. enhanced)
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
  zoom_params: vec4<f32>,  // x=BassGain, y=MidGain, z=TrebleGain, w=Blend
  ripples: array<vec4<f32>, 50>,
};

// ── helpers ──────────────────────────────────────────────────────────────────

fn fftBin(idx: u32) -> f32 {
  let slot = idx + 5u;
  if (slot >= arrayLength(&extraBuffer)) { return 0.0; }
  return clamp(extraBuffer[slot], 0.0, 1.0);
}

fn avgBins(lo: u32, hi: u32) -> f32 {
  if (hi < lo) { return 0.0; }
  var acc = 0.0;
  for (var b = lo; b <= hi; b++) {
    acc += fftBin(b);
  }
  return acc / f32(hi - lo + 1u);
}

/// Separable 5-tap Gaussian blur (σ ≈ 1.0) at a given step size.
/// Single-pass approximate Gaussian blur at a given texel step size.
///
/// A true separable Gaussian requires two full-resolution passes (horizontal
/// then vertical), which doubles the memory bandwidth.  In this single-pass
/// version the horizontal and vertical 5-tap responses are averaged, which
/// gives a visually equivalent result for the small kernel sizes (σ ≤ 2 px)
/// used here.  The slight approximation error is imperceptible at these
/// scales and is outweighed by the performance benefit of a single dispatch.
fn gaussBlur(samp: texture_2d<f32>, uv: vec2<f32>, step: f32) -> vec4<f32> {
  let res = vec2<f32>(textureDimensions(samp));
  let d = step / res;

  // Horizontal 5-tap response
  var col = vec4<f32>(0.0);
  col += textureSampleLevel(samp, u_sampler, uv + vec2<f32>(-2.0 * d.x, 0.0), 0.0) * 0.0625;
  col += textureSampleLevel(samp, u_sampler, uv + vec2<f32>(-1.0 * d.x, 0.0), 0.0) * 0.25;
  col += textureSampleLevel(samp, u_sampler, uv,                                    0.0) * 0.375;
  col += textureSampleLevel(samp, u_sampler, uv + vec2<f32>( 1.0 * d.x, 0.0), 0.0) * 0.25;
  col += textureSampleLevel(samp, u_sampler, uv + vec2<f32>( 2.0 * d.x, 0.0), 0.0) * 0.0625;

  // Vertical 5-tap response
  var row = vec4<f32>(0.0);
  row += textureSampleLevel(samp, u_sampler, uv + vec2<f32>(0.0, -2.0 * d.y), 0.0) * 0.0625;
  row += textureSampleLevel(samp, u_sampler, uv + vec2<f32>(0.0, -1.0 * d.y), 0.0) * 0.25;
  row += textureSampleLevel(samp, u_sampler, uv,                                    0.0) * 0.375;
  row += textureSampleLevel(samp, u_sampler, uv + vec2<f32>(0.0,  1.0 * d.y), 0.0) * 0.25;
  row += textureSampleLevel(samp, u_sampler, uv + vec2<f32>(0.0,  2.0 * d.y), 0.0) * 0.0625;

  return (col + row) * 0.5;
}

// ── main ─────────────────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.z, u.config.w);
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;

  // ── Audio energy per pyramid band ────────────────────────────────
  // Bin ranges chosen to span bass/mid/treble thirds of 128 bins.
  let bassEnergy   = avgBins(  0u,  12u);   // bins  0–12  (~0–1.4 kHz)
  let midEnergy    = avgBins( 13u,  50u);   // bins 13–50  (~1.4–5.4 kHz)
  let trebleEnergy = avgBins( 51u, 127u);   // bins 51–127 (~5.4–22 kHz)

  // Gain knobs from params (allow up to 4× amplification)
  let bassGain   = mix(0.0, 4.0, u.zoom_params.x) * bassEnergy;
  let midGain    = mix(0.0, 4.0, u.zoom_params.y) * midEnergy;
  let trebleGain = mix(0.0, 4.0, u.zoom_params.z) * trebleEnergy;
  let blend      = u.zoom_params.w;

  // ── Gaussian pyramid approximation ──────────────────────────────
  // blur0: fine scale (1 pixel step)
  // blur1: medium scale (2 pixel steps)
  // blur2: coarse scale (4 pixel steps)
  let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let blur0    = gaussBlur(readTexture, uv, 1.0);
  let blur1    = gaussBlur(readTexture, uv, 2.0);
  let blur2    = gaussBlur(readTexture, uv, 4.0);

  // Laplacian levels (Difference of Gaussians)
  let levelFine   = original - blur0;   // fine detail
  let levelMid    = blur0    - blur1;   // mid detail
  let levelCoarse = blur1    - blur2;   // coarse detail

  // Reconstruct with audio-driven amplitudes
  let enhanced = blur2
    + levelCoarse * (1.0 + bassGain)
    + levelMid    * (1.0 + midGain)
    + levelFine   * (1.0 + trebleGain);

  let output = mix(original, enhanced, blend);
  textureStore(writeTexture, global_id.xy, clamp(output, vec4<f32>(0.0), vec4<f32>(1.0)));

  // Pass-through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 1.0));

  textureStore(dataTextureA, global_id.xy, output);
}
