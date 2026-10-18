// ═══════════════════════════════════════════════════════════════════
//  Audio Reactive Pyramid
//  Category: post-processing
//  Features: audio-reactive, fft-bins, frequency-coupled, pyramid, depth-aware
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: depth-routed bands (near takes the fine boost, far takes gentle coarse softening); per-band chroma split (coarse halos warm, fine edges cool)
//  A packing: display RGBA (enhanced photo, source alpha); C is not read back
// ═══════════════════════════════════════════════════════════════════
//  Created: 2026-05-23  By: copilot / P6 audio bridge
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
//  2026-09-28 floor fix: every band also gets a small silence-floor
//  gain (slider × 0.5), so at silence the default is a gentle detail
//  enhancer instead of an exact pass-through. Audio adds on top.
//
//  No ACES: this is a detail enhancer for photos; a filmic curve would
//  regrade every image's tones, so `upgraded-rgba` is not claimed.
//
//  extraBuffer layout (relevant slots, read-only here):
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

// Idea 1 support — depth-map confidence. Samples a fixed 3×3 grid of the
// depth map; a flat or absent (all-zero) map has no spread → 0, so the
// depth routing collapses to the plain, un-routed pyramid.
fn depthConfidence() -> f32 {
  var dMin = 1.0;
  var dMax = 0.0;
  for (var j = 0; j < 3; j++) {
    for (var i = 0; i < 3; i++) {
      let p = vec2<f32>(0.2 + 0.3 * f32(i), 0.2 + 0.3 * f32(j));
      let d = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, p, 0.0).r, 0.0, 1.0);
      dMin = min(dMin, d);
      dMax = max(dMax, d);
    }
  }
  return smoothstep(0.03, 0.2, dMax - dMin);
}

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
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

  // ── Silence floor (HEAD fix) ────────────────────────────────────
  // Small per-band base gain from the same sliders so the default is
  // visible without audio; audio gains above still add on top.
  let floorCoarse = u.zoom_params.x * 0.5;
  let floorMid    = u.zoom_params.y * 0.5;
  let floorFine   = u.zoom_params.z * 0.5;

  // ── Idea 1: depth-routed bands (aerial perspective) ─────────────
  // Library convention: depth 1 = near, 0 = far. Near pixels take up to
  // 1.5× the fine-band boost (far down to 0.5×); far pixels also get a
  // gentle negative coarse gain that lowers large-scale local contrast,
  // like haze. conf = 0 on a flat / missing depth map → no routing.
  let depth    = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let near     = clamp(depth, 0.0, 1.0);
  let conf     = depthConfidence();
  let fineRoute  = mix(1.0, 0.5 + near, conf);
  let farSoften  = conf * (1.0 - smoothstep(0.0, 0.5, near)) * 0.35;

  let gainCoarse = bassGain   + floorCoarse;
  let gainMid    = midGain    + floorMid;
  let gainFine   = (trebleGain + floorFine) * fineRoute;

  // Reconstruct with audio-driven amplitudes
  let enhanced = blur2
    + levelCoarse * (1.0 + gainCoarse - farSoften)
    + levelMid    * (1.0 + gainMid)
    + levelFine   * (1.0 + gainFine);

  // ── Idea 2: per-band chroma split ───────────────────────────────
  // Only the *added* detail is tinted: the coarse-band boost leans warm,
  // the fine-band boost leans cool, in proportion to |added luma|, so both
  // sides of a halo shift the same way and flat/neutral areas stay neutral.
  let addCoarse = abs(luma(levelCoarse.rgb)) * max(gainCoarse - farSoften, 0.0);
  let addFine   = abs(luma(levelFine.rgb))   * gainFine;
  let warmDir   = vec3<f32>( 1.0, 0.35, -0.9);
  let coolDir   = vec3<f32>(-0.7, 0.05,  1.0);
  let chromaRGB = enhanced.rgb + (warmDir * addCoarse + coolDir * addFine) * 0.6;
  let enhancedTinted = vec4<f32>(chromaRGB, enhanced.a);

  let output = mix(original, enhancedTinted, blend);
  let display = vec4<f32>(clamp(output.rgb, vec3<f32>(0.0), vec3<f32>(1.0)), clamp(original.a, 0.0, 1.0));
  textureStore(writeTexture, global_id.xy, display);

  // Pass-through depth
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 1.0));

  // A = display RGBA (not read back as C by this shader)
  textureStore(dataTextureA, global_id.xy, display);
}
