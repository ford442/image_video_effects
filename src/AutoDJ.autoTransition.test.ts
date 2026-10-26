/**
 * #1511 bug 8: auto-transition runs must not race. A stop or an overlapping start
 * leaves no orchestrator, beat detector, rAF loop or open audio graph behind.
 */
import { Alucinate } from './AutoDJ';
import { connectSource, disposeAudioGraph } from './services/audioGraph';

const h = vi.hoisted(() => ({
  orchestrators: [] as Array<{ started: boolean; stopped: boolean; updates: number }>,
  detectors: [] as Array<{ started: boolean; stopped: boolean }>,
}));

vi.mock('./services/audioGraph', () => ({
  connectSource: vi.fn(),
  disposeAudioGraph: vi.fn(async () => {}),
}));

vi.mock('./services/transitionOrchestrator', () => ({
  TransitionOrchestrator: class {
    private readonly rec = { started: false, stopped: false, updates: 0 };
    constructor() { h.orchestrators.push(this.rec); }
    setTargetFactory() {}
    start() { this.rec.started = true; }
    stop() { this.rec.stopped = true; }
    getState() { return 'IDLE'; }
    enqueueBeat() {}
    async update() { this.rec.updates++; return null; }
  },
}));

vi.mock('./services/beatDetector', () => ({
  BeatDetector: class {
    private readonly rec = { started: false, stopped: false };
    constructor() { h.detectors.push(this.rec); }
    start() { this.rec.started = true; }
    stop() { this.rec.stopped = true; }
  },
}));

type Internals = { activeShaderIds: string[]; catalogCache: unknown[] };

const BEAT = { source: 'beat' as const, durationMs: 1000, beatInput: 'mic' as const };
const TIMER = { source: 'timer' as const, durationMs: 1000, intervalMs: 5000 };

function build() {
  const dj = new Alucinate(vi.fn(), vi.fn(), () => ({ currentImage: null, currentShader: null }));
  const internals = dj as unknown as Internals;
  internals.activeShaderIds = ['liquid'];
  internals.catalogCache = [{ id: 'liquid', params: [{ id: 'p1', min: 0, max: 1, step: 0.01, default: 0.5 }] }];
  return { dj, internals };
}

async function flushAsync(): Promise<void> {
  for (let i = 0; i < 20; i++) await Promise.resolve();
}

const running = () => h.orchestrators.filter((o) => o.started && !o.stopped);

describe('Alucinate auto-transition races (#1511 bug 8)', () => {
  let rafs: Map<number, FrameRequestCallback>;
  beforeEach(() => {
    vi.useFakeTimers();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    h.orchestrators.length = 0;
    h.detectors.length = 0;
    vi.mocked(connectSource).mockReset();
    vi.mocked(disposeAudioGraph).mockClear();
    rafs = new Map();
    let next = 1;
    vi.stubGlobal('requestAnimationFrame', (cb: FrameRequestCallback) => { rafs.set(next, cb); return next++; });
    vi.stubGlobal('cancelAnimationFrame', (id: number) => { rafs.delete(id); });
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  /** Run every pending rAF callback once (the loop re-arms itself if still current). */
  async function tick(): Promise<void> {
    const pending = [...rafs.entries()];
    rafs.clear();
    for (const [, cb] of pending) cb(performance.now());
    await flushAsync();
  }

  it('stop before connectSource resolves leaves no orchestrator running and disposes the graph once', async () => {
    let resolveSource!: (a: AnalyserNode) => void;
    vi.mocked(connectSource).mockImplementation(() => new Promise((r) => { resolveSource = r; }));
    const { dj } = build();

    const started = dj.startAutoTransition(BEAT);
    await flushAsync();
    expect(connectSource).toHaveBeenCalledTimes(1);
    expect(h.orchestrators).toHaveLength(0); // nothing starts before the source is connected

    dj.stopAutoTransition();
    resolveSource({} as AnalyserNode);
    await expect(started).resolves.toBe(false);
    await flushAsync();

    expect(running()).toHaveLength(0);
    expect(h.detectors).toHaveLength(0);
    expect(rafs.size).toBe(0);
    expect(disposeAudioGraph).toHaveBeenCalledTimes(1);
    // Dispose was queued behind the in-flight connect, never ahead of it.
    expect(vi.mocked(disposeAudioGraph).mock.invocationCallOrder[0]!)
      .toBeGreaterThan(vi.mocked(connectSource).mock.invocationCallOrder[0]!);
  });

  it('overlapping start/start keeps exactly one orchestrator and one rAF loop', async () => {
    const resolvers: Array<(a: AnalyserNode) => void> = [];
    vi.mocked(connectSource).mockImplementation(() => new Promise((r) => { resolvers.push(r); }));
    const { dj } = build();

    const first = dj.startAutoTransition(BEAT);
    await flushAsync();
    const second = dj.startAutoTransition(BEAT);
    await flushAsync();
    // The first connect finishes after the second start superseded it.
    resolvers[0]!({} as AnalyserNode);
    await flushAsync();
    resolvers[1]?.({} as AnalyserNode);
    await expect(first).resolves.toBe(false);
    await expect(second).resolves.toBe(true);

    expect(running()).toHaveLength(1);
    expect(h.detectors.filter((d) => d.started && !d.stopped)).toHaveLength(1);
    expect(rafs.size).toBe(1);
    await tick();
    await tick();
    expect(rafs.size).toBe(1);
    expect(running()[0]!.updates).toBe(2);

    dj.stopAutoTransition();
    await flushAsync();
    expect(running()).toHaveLength(0);
    expect(rafs.size).toBe(0);
  });

  it('a stale rAF callback from a stopped run does not drive the next run', async () => {
    const { dj } = build();
    await dj.startAutoTransition(TIMER);
    const [staleCb] = [...rafs.values()];
    dj.stopAutoTransition();
    await dj.startAutoTransition(TIMER);
    staleCb!(performance.now());
    await flushAsync();
    expect(running()).toHaveLength(1);
    expect(running()[0]!.updates).toBe(0);
    expect(rafs.size).toBe(1);
    // Timer runs never open the audio graph, so stopping them never disposes it.
    dj.stopAutoTransition();
    await flushAsync();
    expect(disposeAudioGraph).not.toHaveBeenCalled();
  });

  it('stop() clears the pending 5 s next-image timeout from a real cycle', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const onNextImage = vi.fn();
    const dj = new Alucinate(onNextImage, vi.fn(), () => ({
      currentImage: { url: 'https://img/a.jpg', tags: [] } as never,
      currentShader: null,
    }));
    const internals = dj as unknown as Record<string, unknown>;
    internals.status = 'ready';
    internals.llm = {};
    internals.shaderManifest = [{ id: 'liquid', name: 'Liquid', tags: [], params: [] }];
    internals.imageManifest = [{ url: 'https://img/ocean.jpg', tags: ['ocean'] }];
    internals.captioner = vi.fn(async () => [{ generated_text: 'a calm sea' }]);
    internals.selectShadersFromLLM = vi.fn(async () => null);
    internals.getNextImageThemeFromLLM = vi.fn(async () => 'ocean waves');

    expect(dj.start()).toBe(true);
    await flushAsync();
    vi.advanceTimersByTime(2000); // the cycle's settle delay before picking the next image
    await flushAsync();
    expect(vi.getTimerCount()).toBeGreaterThan(0);

    dj.stop();
    expect(vi.getTimerCount()).toBe(0);
    vi.advanceTimersByTime(10_000);
    expect(onNextImage).not.toHaveBeenCalled();
  });
});
