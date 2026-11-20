import { bandsOf, mixToMono, OfflineAudioAnalyser, OFFLINE_AUDIO_BINS } from './offlineAudio';

const SR = 44_100;
const tone = (hz: number, seconds = 1, amp = 0.8) =>
  Float32Array.from({ length: SR * seconds }, (_, i) => amp * Math.sin((2 * Math.PI * hz * i) / SR));

describe('offline audio analysis (#1401)', () => {
  it('silence analyses to zero bins and bands', () => {
    const a = new OfflineAudioAnalyser({ samples: new Float32Array(SR), sampleRate: SR }, 30);
    const f = a.at(10);
    expect(f.bins).toHaveLength(OFFLINE_AUDIO_BINS);
    expect(Math.max(...f.bins)).toBe(0);
    expect(f).toMatchObject({ bass: 0, mid: 0, treble: 0 });
  });

  it('a low tone lands in bass, a high tone in treble (bins of ~172 Hz at fftSize 256)', () => {
    const binHz = SR / 256;
    // Quiet enough that no bin clips at the -30 dB top of the byte range.
    const low = new OfflineAudioAnalyser({ samples: tone(3 * binHz, 1, 0.01), sampleRate: SR }, 30).at(15);
    const high = new OfflineAudioAnalyser({ samples: tone(15_000, 1, 0.01), sampleRate: SR }, 30).at(15);
    expect(low.bass).toBeGreaterThan(low.treble);
    expect(high.treble).toBeGreaterThan(high.bass);
    expect(low.bins.indexOf(Math.max(...low.bins))).toBe(3);
  });

  it('is reproducible: same file, same fps → same numbers, whatever order frames are asked in', () => {
    const samples = Float32Array.from({ length: SR }, (_, i) => Math.sin(i * 0.05) * Math.sin(i * 0.0007));
    const a = new OfflineAudioAnalyser({ samples, sampleRate: SR }, 60);
    const b = new OfflineAudioAnalyser({ samples, sampleRate: SR }, 60);
    const forward = Array.from({ length: 30 }, (_, i) => a.at(i));
    expect(b.at(29)).toEqual(forward[29]);
    expect(b.at(5)).toEqual(forward[5]); // going back restarts the smoothing from frame 0
    expect(b.at(5)).toEqual(forward[5]); // asking twice is stable
  });

  it('smoothing carries energy across frames like the live analyser (τ = 0.8)', () => {
    const samples = new Float32Array(SR);
    samples.set(tone(500, 0.1, 0.01), 0); // a 100 ms burst, then silence
    const a = new OfflineAudioAnalyser({ samples, sampleRate: SR }, 30);
    const during = a.at(3).bass; // the last frame whose window holds the burst
    const after = a.at(6).bass; // 100 ms of silence later
    expect(during).toBeGreaterThan(0);
    expect(after).toBeGreaterThan(0); // decaying, not cut
    expect(after).toBeLessThan(during);
  });

  it('bands use the live analyser split and channels mix to mono', () => {
    const bins = new Float32Array(128);
    bins.fill(1, 0, 12);
    expect(bandsOf(bins)).toEqual({ bass: 1, mid: 0, treble: 0 });
    const mono = mixToMono({
      numberOfChannels: 2,
      length: 2,
      getChannelData: (c: number) => Float32Array.from(c === 0 ? [1, 0] : [0, 1]),
    } as unknown as AudioBuffer);
    expect([...mono]).toEqual([0.5, 0.5]);
  });
});
