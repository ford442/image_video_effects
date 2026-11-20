/**
 * offlineAudio.ts — reproducible audio input for offline renders (#1401).
 *
 * Live, the analyser graph (audioGraph.ts / useAudioAnalyzer) is sampled whenever the page
 * polls it, so audio-reactive shaders differ run to run. Offline, the soundtrack is decoded
 * once (OfflineAudioContext, no playback, no user gesture) and analysed per video frame
 * exactly the way an AnalyserNode with the live settings would at that instant:
 *
 *   fftSize 256 (128 bins → extraBuffer[5..132]), Blackman window, |X[k]| / N,
 *   smoothing τ = 0.8 across analysed frames, dB → bytes over [-100, -30] dB, / 255.
 *
 * bass / mid / treble are the means of bins [0, 12) / [12, 64) / [64, 128), as in
 * useAudioAnalyzer. The same file at the same fps always gives the same numbers.
 */

export const OFFLINE_AUDIO_FFT_SIZE = 256;
export const OFFLINE_AUDIO_BINS = OFFLINE_AUDIO_FFT_SIZE / 2;
const DEFAULT_SMOOTHING = 0.8;
const MIN_DB = -100;
const MAX_DB = -30;

export interface DecodedAudio {
  /** Mono samples (channels averaged). */
  samples: Float32Array;
  sampleRate: number;
  durationSec: number;
}

export interface AudioFrameFeatures {
  bass: number;
  mid: number;
  treble: number;
  /** 128 bins, 0..1 (byte / 255, like getByteFrequencyData). */
  bins: Float32Array;
}

/** Decode an audio (or video-with-audio) file without playing it. */
export async function decodeAudioFile(data: ArrayBuffer, sampleRate = 44_100): Promise<DecodedAudio> {
  const Ctx = (globalThis as { OfflineAudioContext?: typeof OfflineAudioContext }).OfflineAudioContext;
  if (!Ctx) throw new Error('OfflineAudioContext is not available in this browser');
  const ctx = new Ctx(1, 1, sampleRate);
  const buffer = await ctx.decodeAudioData(data.slice(0));
  return { samples: mixToMono(buffer), sampleRate: buffer.sampleRate, durationSec: buffer.duration };
}

export function mixToMono(buffer: Pick<AudioBuffer, 'numberOfChannels' | 'length' | 'getChannelData'>): Float32Array {
  const out = new Float32Array(buffer.length);
  const channels = Math.max(1, buffer.numberOfChannels);
  for (let c = 0; c < buffer.numberOfChannels; c++) {
    const data = buffer.getChannelData(c);
    for (let i = 0; i < out.length; i++) out[i] = (out[i] ?? 0) + (data[i] ?? 0) / channels;
  }
  return out;
}

/** Radix-2 in-place FFT on (re, im), length a power of two. */
function fft(re: Float64Array, im: Float64Array): void {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) {
      const tr = re[i] ?? 0;
      re[i] = re[j] ?? 0;
      re[j] = tr;
      const ti = im[i] ?? 0;
      im[i] = im[j] ?? 0;
      im[j] = ti;
    }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const ang = (-2 * Math.PI) / len;
    const wr = Math.cos(ang);
    const wi = Math.sin(ang);
    for (let i = 0; i < n; i += len) {
      let cr = 1;
      let ci = 0;
      for (let k = 0; k < len / 2; k++) {
        const a = i + k;
        const b = a + len / 2;
        const ar = re[a] ?? 0;
        const ai = im[a] ?? 0;
        const br = re[b] ?? 0;
        const bi = im[b] ?? 0;
        const xr = br * cr - bi * ci;
        const xi = br * ci + bi * cr;
        re[b] = ar - xr;
        im[b] = ai - xi;
        re[a] = ar + xr;
        im[a] = ai + xi;
        const nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
}

/**
 * Sequential per-frame analysis. `at(frameIndex)` must be called with non-decreasing
 * indices to carry the smoothing (an earlier index restarts from frame 0, so any call
 * order still gives the same answer for the same index).
 */
export class OfflineAudioAnalyser {
  private readonly window = new Float64Array(OFFLINE_AUDIO_FFT_SIZE);
  private readonly smoothed = new Float64Array(OFFLINE_AUDIO_BINS);
  private readonly re = new Float64Array(OFFLINE_AUDIO_FFT_SIZE);
  private readonly im = new Float64Array(OFFLINE_AUDIO_FFT_SIZE);
  private nextFrame = 0;
  private last: AudioFrameFeatures | null = null;

  constructor(
    private readonly audio: Pick<DecodedAudio, 'samples' | 'sampleRate'>,
    private readonly fps: number,
    private readonly smoothing = DEFAULT_SMOOTHING,
    /** Timeline offset: frame 0 analyses the audio at this many seconds in. */
    private readonly startSec = 0,
  ) {
    const n = OFFLINE_AUDIO_FFT_SIZE;
    for (let i = 0; i < n; i++) {
      // Blackman window, as the Web Audio AnalyserNode.
      this.window[i] = 0.42 - 0.5 * Math.cos((2 * Math.PI * i) / n) + 0.08 * Math.cos((4 * Math.PI * i) / n);
    }
  }

  at(frameIndex: number): AudioFrameFeatures {
    const index = Math.max(0, Math.floor(frameIndex));
    if (this.last && index === this.nextFrame - 1) return cloneFeatures(this.last);
    if (index < this.nextFrame) this.reset();
    let features = this.analyse(this.nextFrame++);
    while (this.nextFrame <= index) features = this.analyse(this.nextFrame++);
    this.last = features;
    return cloneFeatures(features);
  }

  private reset(): void {
    this.smoothed.fill(0);
    this.nextFrame = 0;
    this.last = null;
  }

  private analyse(frameIndex: number): AudioFrameFeatures {
    const n = OFFLINE_AUDIO_FFT_SIZE;
    const { samples, sampleRate } = this.audio;
    // The analyser sees the most recent fftSize samples ending at the frame's time.
    const end = Math.round((this.startSec + frameIndex / this.fps) * sampleRate);
    for (let i = 0; i < n; i++) {
      const s = end - n + i;
      this.re[i] = (s >= 0 && s < samples.length ? samples[s] ?? 0 : 0) * (this.window[i] ?? 0);
      this.im[i] = 0;
    }
    fft(this.re, this.im);
    const bins = new Float32Array(OFFLINE_AUDIO_BINS);
    const tau = this.smoothing;
    for (let k = 0; k < OFFLINE_AUDIO_BINS; k++) {
      const mag = Math.hypot(this.re[k] ?? 0, this.im[k] ?? 0) / n;
      const s = tau * (this.smoothed[k] ?? 0) + (1 - tau) * mag;
      this.smoothed[k] = s;
      const db = s > 0 ? 20 * Math.log10(s) : -Infinity;
      const byte = Math.floor((255 / (MAX_DB - MIN_DB)) * (db - MIN_DB));
      bins[k] = Math.min(255, Math.max(0, Number.isFinite(byte) ? byte : 0)) / 255;
    }
    return { ...bandsOf(bins), bins };
  }
}

/** bass / mid / treble exactly as useAudioAnalyzer derives them from the byte spectrum. */
export function bandsOf(bins: Float32Array): { bass: number; mid: number; treble: number } {
  const len = bins.length;
  const bassEnd = Math.floor(len * 0.1);
  const midEnd = Math.floor(len * 0.5);
  let bass = 0;
  let mid = 0;
  let treble = 0;
  for (let i = 0; i < len; i++) {
    const v = bins[i] ?? 0;
    if (i < bassEnd) bass += v;
    else if (i < midEnd) mid += v;
    else treble += v;
  }
  return {
    bass: bass / (bassEnd || 1),
    mid: mid / ((midEnd - bassEnd) || 1),
    treble: treble / ((len - midEnd) || 1),
  };
}

function cloneFeatures(f: AudioFrameFeatures): AudioFrameFeatures {
  return { bass: f.bass, mid: f.mid, treble: f.treble, bins: f.bins.slice() };
}
