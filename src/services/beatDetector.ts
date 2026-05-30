export class BeatDetector {
  private analyser: AnalyserNode;
  private onBeat: (timestamp: number) => void;
  private buffer: Uint8Array;
  private rafId: number | null = null;
  private running = false;
  private energyAverage = 0;
  private readonly thresholdMultiplier = 1.45;
  private readonly minEnergy = 0.02;
  private readonly refractoryMs = 250;
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

    const lowBandEnd = Math.max(1, Math.floor(this.buffer.length * 0.2));
    let energy = 0;
    for (let i = 0; i < lowBandEnd; i++) {
      energy += this.buffer[i] / 255;
    }
    energy /= lowBandEnd;

    if (this.energyAverage === 0) {
      this.energyAverage = energy;
    } else {
      this.energyAverage = this.energyAverage * 0.92 + energy * 0.08;
    }

    const threshold = Math.max(this.minEnergy, this.energyAverage * this.thresholdMultiplier);
    if (energy > threshold && now - this.lastBeatAt >= this.refractoryMs) {
      this.lastBeatAt = now;
      this.onBeat(now);
    }
  }
}

