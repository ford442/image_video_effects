/**
 * AutoDJ races: a stop / overlapping start during the async auto-transition
 * setup, and the cycle's delayed image swap after stop() (regressions).
 */
import { Alucinate } from './AutoDJ';

const audio = vi.hoisted(() => ({
  resolveConnect: [] as Array<(a: AnalyserNode) => void>,
  dispose: vi.fn(async () => {}),
}));
vi.mock('./services/audioGraph', () => ({
  connectSource: () => new Promise<AnalyserNode>((resolve) => { audio.resolveConnect.push(resolve); }),
  disposeAudioGraph: audio.dispose,
}));

const beats = vi.hoisted(() => ({ started: 0 }));
vi.mock('./services/beatDetector', () => ({
  BeatDetector: class {
    start() { beats.started++; }
    stop() {}
  },
}));

type Internals = {
  status: string;
  llm: unknown;
  activeShaderIds: string[];
  catalogCache: unknown[];
  transitionOrchestrator: unknown;
  beatDetector: unknown;
  captioner: (url: string, opts: unknown) => Promise<Array<{ generated_text: string }>>;
  imageManifest: Array<{ url: string; tags: string[] }>;
  shaderManifest: Array<{ id: string; name: string; tags: string[]; params: unknown[] }>;
  selectShadersFromLLM: (caption: string, vibe: string) => Promise<unknown>;
  getNextImageThemeFromLLM: (caption: string, shader: string) => Promise<string | null>;
};

async function flushAsync(): Promise<void> {
  for (let i = 0; i < 20; i++) await Promise.resolve();
}

function build() {
  const onNextImage = vi.fn();
  const dj = new Alucinate(
    onNextImage,
    vi.fn(),
    () => ({ currentImage: { url: 'https://img/a.jpg', tags: [] } as never, currentShader: null }),
  );
  const internals = dj as unknown as Internals;
  internals.status = 'ready';
  internals.llm = {};
  internals.activeShaderIds = ['liquid'];
  internals.catalogCache = [{ id: 'liquid', params: [{ id: 'p1', min: 0, max: 1, step: 0.01, default: 0.5 }] }];
  internals.shaderManifest = [{ id: 'liquid', name: 'Liquid', tags: [], params: [] }];
  return { dj, internals, onNextImage };
}

describe('Alucinate auto-transition races', () => {
  let rafs: number;
  beforeEach(() => {
    rafs = 0;
    audio.resolveConnect = [];
    audio.dispose.mockClear();
    beats.started = 0;
    vi.stubGlobal('requestAnimationFrame', vi.fn(() => ++rafs));
    vi.stubGlobal('cancelAnimationFrame', vi.fn());
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('a stop during connectSource leaves no mic, beat detector or rAF loop behind', async () => {
    const { dj, internals } = build();
    const started = dj.startAutoTransition({ source: 'beat', durationMs: 1000 });
    await flushAsync();
    expect(audio.resolveConnect).toHaveLength(1);

    dj.stopAutoTransition();
    const disposeCallsAfterStop = audio.dispose.mock.calls.length;
    audio.resolveConnect[0]?.({} as AnalyserNode);

    await expect(started).resolves.toBe(false);
    expect(beats.started).toBe(0);
    expect(rafs).toBe(0);
    expect(internals.transitionOrchestrator).toBeNull();
    // The late-opened mic is released again.
    expect(audio.dispose.mock.calls.length).toBeGreaterThan(disposeCallsAfterStop);
  });

  it('overlapping starts end with exactly one orchestrator and one rAF loop', async () => {
    const { dj, internals } = build();
    const first = dj.startAutoTransition({ source: 'beat', durationMs: 1000 });
    await flushAsync();
    const second = dj.startAutoTransition({ source: 'beat', durationMs: 1000 });
    await flushAsync();
    audio.resolveConnect.forEach((resolve) => resolve({} as AnalyserNode));

    await expect(first).resolves.toBe(false);
    await expect(second).resolves.toBe(true);
    expect(beats.started).toBe(1);
    expect(rafs).toBe(1);
    expect(internals.transitionOrchestrator).not.toBeNull();
    dj.stopAutoTransition();
  });

  it('timer transitions still start', async () => {
    const { dj } = build();
    await expect(dj.startAutoTransition({ source: 'timer', intervalMs: 5000, durationMs: 1000 })).resolves.toBe(true);
    expect(rafs).toBe(1);
    dj.stopAutoTransition();
  });
});

describe('Alucinate cycle timers', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('stop() cancels the pending 5 s image swap, even after a quick restart', async () => {
    const { dj, internals, onNextImage } = build();
    internals.captioner = vi.fn().mockResolvedValue([{ generated_text: 'a forest' }]);
    internals.selectShadersFromLLM = vi.fn().mockResolvedValue(null);
    internals.getNextImageThemeFromLLM = vi.fn().mockResolvedValue('forest');
    internals.imageManifest = [{ url: 'https://img/b.jpg', tags: ['forest'] }];

    dj.start();
    await flushAsync();
    vi.advanceTimersByTime(2000);
    await flushAsync();

    dj.stop();
    internals.status = 'ready';
    internals.captioner = vi.fn(() => new Promise<Array<{ generated_text: string }>>(() => {})); // the new run stays busy
    dj.start();
    vi.advanceTimersByTime(5000);
    await flushAsync();

    expect(onNextImage).not.toHaveBeenCalled();
    dj.stop();
  });
});
