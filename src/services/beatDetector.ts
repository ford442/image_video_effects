export class BeatDetector {
  // Beat event when instantaneous bass energy exceeds this multiple of rolling average.
  private static readonly THRESHOLD_MULTIPLIER = 1.45;
  // Ignore very low-energy spikes to reject ambient/noise floor transients.
  private static readonly MIN_ENERGY = 0.02;
  // Debounce window to drop rapid double-fires from single kicks.
  private static readonly REFRACTORY_MS = 250;
  // Portion of FFT bins treated as low-frequency (kick/bass) energy.
  private static readonly LOW_BAND_RATIO = 0.2;
  // Exponential moving average smoothing for adaptive threshold baseline.
  private static readonly ENERGY_AVG_KEEP = 0.92;
  private static readonly ENERGY_AVG_INJECT = 0.08;

  private analyser: AnalyserNode;
  private onBeat: (timestamp: number) => void;
  private buffer: Uint8Array;
  private rafId: number | null = null;
  private running = false;
  private energyAverage = 0;
  private lastBeatAt = -Infinity;

  constructor(analyser: AnalyserNode, onBeat: (timestamp: number) => void) {
    this.analyser = analyser;
    this.onBeat = onBeat;
    this.buffer = new Uint8Array(analyser.frequencyBinCount);
  }

  public start() {
    if (this.running) return;
    this.running = true;
    const loop = () => {
      if (!this.running) return;
      this.tick(performance.now());
      this.rafId = requestAnimationFrame(loop);
    };
    this.rafId = requestAnimationFrame(loop);
  }

  public stop() {
    this.running = false;
    if (this.rafId !== null) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }
  }

  public tick(now: number) {
    this.analyser.getByteFrequencyData(this.buffer);

    const lowBandEnd = Math.max(1, Math.floor(this.buffer.length * BeatDetector.LOW_BAND_RATIO));
    let energy = 0;
    for (let i = 0; i < lowBandEnd; i++) {
      energy += this.buffer[i] / 255;
    }
    energy /= lowBandEnd;

    if (this.energyAverage === 0) {
      this.energyAverage = energy;
    } else {
      this.energyAverage =
        this.energyAverage * BeatDetector.ENERGY_AVG_KEEP +
        energy * BeatDetector.ENERGY_AVG_INJECT;
    }

    const threshold = Math.max(BeatDetector.MIN_ENERGY, this.energyAverage * BeatDetector.THRESHOLD_MULTIPLIER);
    if (energy > threshold && now - this.lastBeatAt >= BeatDetector.REFRACTORY_MS) {
      this.lastBeatAt = now;
      this.onBeat(now);
    }
  }
}
