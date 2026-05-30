import { connectSource, disposeAudioGraph, getSharedAudioContext } from './audioGraph';

class FakeNode {
  connect = jest.fn();
  disconnect = jest.fn();
}

class FakeAnalyser extends FakeNode {
  fftSize = 0;
  smoothingTimeConstant = 0;
  frequencyBinCount = 512;
}

class FakeFilter extends FakeNode {
  type: BiquadFilterType = 'lowpass';
  frequency = { value: 0 };
  Q = { value: 0 };
}

class FakeAudioContext {
  state: AudioContextState = 'suspended';
  createMediaStreamSource() {
    return new FakeNode() as unknown as MediaStreamAudioSourceNode;
  }
  createMediaElementSource() {
    return new FakeNode() as unknown as MediaElementAudioSourceNode;
  }
  createBiquadFilter() {
    return new FakeFilter() as unknown as BiquadFilterNode;
  }
  createAnalyser() {
    return new FakeAnalyser() as unknown as AnalyserNode;
  }
  async resume() {
    this.state = 'running';
  }
}

describe('audioGraph', () => {
  const originalAudioContext = (global as any).AudioContext;
  const originalGetUserMedia = navigator.mediaDevices?.getUserMedia;

  beforeEach(() => {
    (global as any).AudioContext = FakeAudioContext as any;
    Object.defineProperty(navigator, 'mediaDevices', {
      value: {
        getUserMedia: jest.fn(async () => ({
          getTracks: () => [{ stop: jest.fn() }],
        })),
      },
      configurable: true,
    });
  });

  afterEach(async () => {
    await disposeAudioGraph();
    if (originalAudioContext) {
      (global as any).AudioContext = originalAudioContext;
    }
    if (originalGetUserMedia) {
      Object.defineProperty(navigator, 'mediaDevices', {
        value: { getUserMedia: originalGetUserMedia },
        configurable: true,
      });
    }
  });

  test('creates shared audio context and connects mic source', async () => {
    const context = await getSharedAudioContext();
    expect(context).toBeTruthy();

    const analyser = await connectSource('mic');
    expect(analyser).toBeTruthy();
  });

  test('connects element source when media element is provided', async () => {
    const element = document.createElement('video');
    const analyser = await connectSource('element', element);
    expect(analyser).toBeTruthy();
  });
});
