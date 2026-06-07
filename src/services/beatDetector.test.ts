import { BeatDetector } from './beatDetector';

class FakeAnalyser {
  public frequencyBinCount = 32;
  private value = 0;

  setValue(v: number) {
    this.value = v;
  }

  getByteFrequencyData(buffer: Uint8Array) {
    const scaled = Math.max(0, Math.min(255, Math.round(this.value * 255)));
    buffer.fill(scaled);
  }
}

describe('BeatDetector', () => {
  test('drops double-fire beats within refractory window', () => {
    const analyser = new FakeAnalyser();
    const beats: number[] = [];
    const detector = new BeatDetector(analyser as unknown as AnalyserNode, (ts) => beats.push(ts));

    analyser.setValue(0.2);
    detector.tick(0);
    analyser.setValue(1.0);
    detector.tick(0);
    detector.tick(80);
    detector.tick(500);

    expect(beats).toEqual([0, 500]);
  });
});
