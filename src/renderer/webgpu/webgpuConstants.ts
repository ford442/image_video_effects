/**
 * webgpuConstants.ts
 *
 * Shared constants and types for the TypeScript WebGPU renderer.
 */

// ── Constants matching C++ renderer ─────────────────────────────────────────

export const MAX_PLASMA_BALLS = 50;
export const EXTRA_FLOATS = 256; // 1024 bytes
export const PLASMA_BYTES = MAX_PLASMA_BALLS * 48; // 2400 bytes

/**
 * extraBuffer layout:
 *   [0]    bass            (0-1, averaged over bass frequency range)
 *   [1]    mid             (0-1, averaged over mid frequency range)
 *   [2]    treble          (0-1, averaged over treble frequency range)
 *   [3]    reserved
 *   [4]    historyHead     (u32 cast from f32, ring-buffer write pointer)
 *   [5..132] FFT_BINS[0..127]  (128 per-bin magnitudes normalised to [0,1])
 *            bin 0  → ~86 Hz, bin 127 → ~22 kHz (44.1 kHz / fftSize=256)
 *            Wire format matches ford442/flac_player FFT output (N=128 bins).
 */
export const EXTRA_BIN_OFFSET = 5; // First FFT bin index in extraBuffer
export const AUDIO_FFT_BINS = 128; // Number of FFT bins stored in extraBuffer

/** Number of frames kept in the temporal history ring buffer (binding 13). */
export const HISTORY_DEPTH = 8;

// ── Compute Shader Workgroup Configuration ───────────────────────────────────

export const WG_SIZE_X = 16;
export const WG_SIZE_Y = 16;
export const WG_SIZE_1D = 256;

// ── Types ────────────────────────────────────────────────────────────────────

/** Slot execution mode for inter-shader parallelization */
export type SlotMode = 'chained' | 'parallel';

export interface ShaderSlot {
  shaderId: string | null;
  enabled: boolean;
  mode: SlotMode;
}
