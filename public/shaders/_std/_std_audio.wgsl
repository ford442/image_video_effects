// ═══════════════════════════════════════════════════════════════════
//  _std/_std_audio.wgsl — named audio accessors
//  @std-module audio
//  @std-version 1
//  @requires prelude
//
//  Source of truth: docs/BINDING_CONTRACT.md. Bands are
//  plasmaBuffer[0].xyz; the 128 normalised FFT bins are extraBuffer[5..132].
//  u.config.y/z/w are NOT audio (config.y is rippleCount) — reading audio
//  from config is the recurring dead-audio bug these accessors replace.
// ═══════════════════════════════════════════════════════════════════

/// First FFT bin index in extraBuffer.
const FFT_BIN_OFFSET: u32 = 5u;
/// Number of FFT bins.
const FFT_BIN_COUNT: u32 = 128u;

/// Bass energy (20–200 Hz), plasmaBuffer[0].x.
/// @range ≥ 0, typically 0–2
/// @cost 1 load
fn audioBass() -> f32 {
  return plasmaBuffer[0].x;
}

/// Mid energy (200–2000 Hz), plasmaBuffer[0].y.
/// @range ≥ 0, typically 0–2
/// @cost 1 load
fn audioMids() -> f32 {
  return plasmaBuffer[0].y;
}

/// Treble energy (2–20 kHz), plasmaBuffer[0].z.
/// @range ≥ 0, typically 0–2
/// @cost 1 load
fn audioTreble() -> f32 {
  return plasmaBuffer[0].z;
}

/// Mean of bass, mids and treble.
/// @range ≥ 0, typically 0–2
/// @cost 1 load
fn audioLevel() -> f32 {
  return dot(plasmaBuffer[0].xyz, vec3<f32>(1.0 / 3.0));
}

/// FFT bin i (0..127, clamped); 0 if the buffer is shorter than the contract.
/// @range [0, 1]
/// @cost 1 load
fn fftBin(i: u32) -> f32 {
  let idx = FFT_BIN_OFFSET + min(i, FFT_BIN_COUNT - 1u);
  if (idx >= arrayLength(&extraBuffer)) {
    return 0.0;
  }
  return extraBuffer[idx];
}

/// FFT sampled at normalised frequency t in [0, 1], linearly interpolated between bins.
/// @range [0, 1]
/// @cost 2 loads
fn fftAt(t: f32) -> f32 {
  let x = saturate(t) * f32(FFT_BIN_COUNT - 1u);
  let i = u32(floor(x));
  return mix(fftBin(i), fftBin(i + 1u), fract(x));
}

/// Mean of FFT bins [lo, hi] inclusive (clamped to the bin range).
/// @range [0, 1]
/// @cost (hi − lo + 1) loads
fn fftBand(lo: u32, hi: u32) -> f32 {
  let a = min(lo, FFT_BIN_COUNT - 1u);
  let b = clamp(hi, a, FFT_BIN_COUNT - 1u);
  var sum = 0.0;
  for (var i = a; i <= b; i++) {
    sum += fftBin(i);
  }
  return sum / f32(b - a + 1u);
}
