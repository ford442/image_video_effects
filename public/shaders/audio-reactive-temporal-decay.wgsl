// ═══════════════════════════════════════════════════════════════════
//  audio-reactive-temporal-decay
//  Category: post-processing
//  Features: audio-reactive, temporal, fft-bins, frequency-coupled
//  Complexity: Medium
//  Created: 2026-05-23
//  By: copilot / P6 audio bridge
//
//  Ring decay rate per-pixel modulated by the sum of FFT bins in a
//  target frequency range.  Low-bin energy → slow decay (long trails);
//  high-bin energy → fast decay (fast fade).
//
//  extraBuffer layout used:
//    [0]  bass   (averaged low band)
//    [1]  mid    (averaged mid band)
//    [2]  treble (averaged high band)
//    [3]  reserved
//    [4]  historyHead
//    [5..132] FFT bins 0..127 (normalised 0–1)
//             bin = extraBuffer[5 + binIndex]
//
//  Parameters:
//    param1 (zoom_params.x) : Decay Base   — base decay rate [0.01 .. 0.3]
//    param2 (zoom_params.y) : Audio Drive  — how strongly bins modulate decay
//    param3 (zoom_params.z) : Bin Range Lo — low  bin index (0–127)
//    param4 (zoom_params.w) : Bin Range Hi — high bin index (0–127)
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
  zoom_params: vec4<f32>,  // x=DecayBase, y=AudioDrive, z=BinLo, w=BinHi
  ripples: array<vec4<f32>, 50>,
};

// ── helpers ──────────────────────────────────────────────────────────────────

/// Return normalised [0,1] magnitude for FFT bin `idx` (0-127).
/// Falls back to 0 when the extraBuffer is too small.
fn fftBin(idx: u32) -> f32 {
  let slot = idx + 5u;
  if (slot >= arrayLength(&extraBuffer)) { return 0.0; }
  return clamp(extraBuffer[slot], 0.0, 1.0);
}

/// Average FFT energy over bins [lo, hi] (inclusive).
fn avgBins(lo: u32, hi: u32) -> f32 {
  if (hi < lo) { return 0.0; }
  var acc = 0.0;
  for (var b = lo; b <= hi; b++) {
    acc += fftBin(b);
  }
  return acc / f32(hi - lo + 1u);
}

// ── main ─────────────────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.z, u.config.w);
  if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;

  // ── Parameters ──────────────────────────────────────────────────
  let decayBase  = mix(0.01, 0.30, u.zoom_params.x);   // [0.01 .. 0.30]
  let audioDrive = mix(0.0,  1.0,  u.zoom_params.y);   // [0    ..  1  ]
  let binLo      = u32(clamp(u.zoom_params.z * 127.0, 0.0, 127.0));
  let binHi      = u32(clamp(u.zoom_params.w * 127.0, f32(binLo), 127.0));

  // ── Frequency energy in the selected bin range ───────────────────
  let energy = avgBins(binLo, binHi);

  // Decay rate increases with energy: more energy → faster fade.
  // The factor 0.4 caps the audio-driven modulation to a 40 percentage-point
  // maximum above the base rate, keeping trails visible even at full drive
  // while still allowing clear beat-synchronised fades.
  let AUDIO_DRIVE_CEILING = 0.4;
  let decay = clamp(decayBase + energy * audioDrive * AUDIO_DRIVE_CEILING, 0.001, 0.99);

  // ── Sample current and previous-frame colour ─────────────────────
  let current  = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let previous = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

  // ── Blend: mix previous frame toward black using per-pixel decay ─
  // High decay → previous fades quickly; low decay → longer trails.
  let blended = mix(previous, current, decay);

  textureStore(writeTexture, global_id.xy, blended);

  // Pass-through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 1.0));

  // Persist blended frame in dataTextureA for next-frame access via dataTextureC
  textureStore(dataTextureA, global_id.xy, blended);
}
