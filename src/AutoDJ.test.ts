/**
 * #1395: one failed cycle must not stop the AI VJ loop for good.
 */

import { Alucinate } from './AutoDJ';

vi.mock('./services/audioGraph', () => ({
  connectSource: vi.fn(),
  disposeAudioGraph: vi.fn().mockResolvedValue(undefined),
}));

type Internals = {
  status: string;
  captioner: (url: string, opts: unknown) => Promise<Array<{ generated_text: string }>>;
  llm: unknown;
  shaderManifest: Array<{ id: string; name: string; tags: string[]; params: unknown[] }>;
  selectShadersFromLLM: (caption: string, vibe: string) => Promise<unknown>;
  getNextImageThemeFromLLM: (caption: string, shader: string) => Promise<string | null>;
};

const CYCLE_MS = 25000;

async function flushAsync(): Promise<void> {
  for (let i = 0; i < 20; i++) await Promise.resolve();
}

function build() {
  const onUpdateStack = vi.fn();
  const dj = new Alucinate(
    vi.fn(),
    onUpdateStack,
    () => ({ currentImage: { url: 'https://img/a.jpg', tags: [] } as never, currentShader: null }),
  );
  const internals = dj as unknown as Internals;
  internals.status = 'ready';
  internals.llm = {};
  internals.shaderManifest = [{ id: 'liquid', name: 'Liquid', tags: [], params: [] }];
  return { dj, internals, onUpdateStack };
}

describe('Alucinate cycle recovery', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('keeps cycling after the captioner rejects', async () => {
    const { dj, internals, onUpdateStack } = build();
    const captioner = vi.fn().mockRejectedValue(new Error('model crashed'));
    internals.captioner = captioner;

    expect(dj.start()).toBe(true);
    await flushAsync();
    expect(captioner).toHaveBeenCalledTimes(1);
    expect(internals.status).toBe('error');
    expect(onUpdateStack).toHaveBeenLastCalledWith(['liquid', 'none', 'none']);

    vi.advanceTimersByTime(CYCLE_MS);
    await flushAsync();
    expect(captioner).toHaveBeenCalledTimes(2);

    dj.stop();
  });

  it('returns to ready when no next theme comes back, so the next tick runs', async () => {
    const { dj, internals } = build();
    const captioner = vi.fn().mockResolvedValue([{ generated_text: 'a forest' }]);
    internals.captioner = captioner;
    internals.selectShadersFromLLM = vi.fn().mockResolvedValue(null);
    internals.getNextImageThemeFromLLM = vi.fn().mockResolvedValue(null);

    dj.start();
    await flushAsync();
    vi.advanceTimersByTime(2000); // pause between stack and theme
    await flushAsync();
    expect(internals.status).toBe('ready');

    vi.advanceTimersByTime(CYCLE_MS);
    await flushAsync();
    expect(captioner).toHaveBeenCalledTimes(2);
    dj.stop();
  });

  it('can start again after a failure left status at error', () => {
    const { dj, internals } = build();
    internals.status = 'error';
    expect(dj.start()).toBe(true);
    dj.stop();
  });
});

describe('Alucinate transitions that swap the shader stack', () => {
  const PRESET_KEY = 'vj_presets';

  function buildCycling() {
    const onUpdateStack = vi.fn();
    const onCrossfade = vi.fn();
    const dj = new Alucinate(
      vi.fn(),
      onUpdateStack,
      () => ({ currentImage: null, currentShader: null }),
    );
    const internals = dj as unknown as { activeShaderIds: string[]; catalogCache: unknown[] };
    internals.activeShaderIds = ['rain'];
    internals.catalogCache = [];
    dj.onCrossfade = onCrossfade;
    dj.onApplyParamsDirect = vi.fn();
    dj.onUpdateParams = vi.fn();
    return { dj, onUpdateStack, onCrossfade };
  }

  async function startCycling(dj: Alucinate, durationMs = 2000) {
    expect(await dj.startAutoTransition({ source: 'timer', intervalMs: 1_000_000, durationMs, mode: 'cyclePresets' })).toBe(true);
  }

  beforeEach(() => {
    vi.spyOn(console, 'log').mockImplementation(() => {});
    localStorage.setItem(PRESET_KEY, JSON.stringify([
      { id: 'p1', name: 'Snow', shaderIds: ['snow'], params: [{}], timestamp: 1 },
    ]));
  });
  afterEach(() => {
    localStorage.removeItem(PRESET_KEY);
    vi.restoreAllMocks();
  });

  it('a crossfade trigger arms the dissolve with the transition duration, before the stack swaps', async () => {
    const { dj, onUpdateStack, onCrossfade } = buildCycling();
    await startCycling(dj, 2500);

    await dj.triggerNextTransition({ crossfade: true });

    expect(onUpdateStack).toHaveBeenCalledWith(['snow']);
    expect(onCrossfade).toHaveBeenCalledTimes(1);
    expect(onCrossfade).toHaveBeenCalledWith(2500);
    expect(onCrossfade.mock.invocationCallOrder[0]).toBeLessThan(onUpdateStack.mock.invocationCallOrder[0]!);
    dj.stopAutoTransition();
  });

  it('a bare trigger swaps exactly as before and arms nothing (existing bindings keep cutting)', async () => {
    const { dj, onUpdateStack, onCrossfade } = buildCycling();
    await startCycling(dj);

    await dj.triggerNextTransition();

    expect(onUpdateStack).toHaveBeenCalledWith(['snow']);
    expect(onCrossfade).not.toHaveBeenCalled();
    dj.stopAutoTransition();
  });

  it('a duration of 0 is a hard cut even when a dissolve was asked for', async () => {
    const { dj, onUpdateStack, onCrossfade } = buildCycling();
    await startCycling(dj, 0);

    await dj.triggerNextTransition({ crossfade: true });

    expect(onUpdateStack).toHaveBeenCalledWith(['snow']);
    expect(onCrossfade).not.toHaveBeenCalled();
    dj.stopAutoTransition();
  });

  it('the request does not leak into the next bare trigger', async () => {
    const { dj, onCrossfade } = buildCycling();
    localStorage.setItem(PRESET_KEY, JSON.stringify([
      { id: 'p1', name: 'Snow', shaderIds: ['snow'], params: [{}], timestamp: 1 },
      { id: 'p2', name: 'Fog', shaderIds: ['fog'], params: [{}], timestamp: 2 },
    ]));
    await startCycling(dj);
    await dj.triggerNextTransition({ crossfade: true });
    expect(onCrossfade).toHaveBeenCalledTimes(1);

    (dj as unknown as { activeShaderIds: string[] }).activeShaderIds = ['rain'];
    await dj.triggerNextTransition();
    expect(onCrossfade).toHaveBeenCalledTimes(1);
    dj.stopAutoTransition();
  });

  it('a param-only transition never arms a dissolve, asked for or not', async () => {
    const { dj, onUpdateStack, onCrossfade } = buildCycling();
    // The only preset is the stack that is already running: sliders ease, nothing swaps.
    localStorage.setItem(PRESET_KEY, JSON.stringify([
      { id: 'p1', name: 'Rain', shaderIds: ['rain'], params: [{}], timestamp: 1 },
    ]));
    await startCycling(dj);

    await dj.triggerNextTransition({ crossfade: true });

    expect(onUpdateStack).not.toHaveBeenCalled();
    expect(onCrossfade).not.toHaveBeenCalled();
    dj.stopAutoTransition();
  });
});

describe('Alucinate auto-transition races', () => {
  function buildActive() {
    const dj = new Alucinate(vi.fn(), vi.fn(), () => ({ currentImage: null, currentShader: null }));
    const internals = dj as unknown as { activeShaderIds: string[]; catalogCache: unknown[] };
    internals.activeShaderIds = ['rain'];
    internals.catalogCache = [];
    dj.onUpdateParams = vi.fn();
    return dj;
  }

  let rafSpy: ReturnType<typeof vi.fn>;
  beforeEach(() => {
    vi.spyOn(console, 'log').mockImplementation(() => {});
    rafSpy = vi.fn(() => 1);
    vi.stubGlobal('requestAnimationFrame', rafSpy);
    vi.stubGlobal('cancelAnimationFrame', vi.fn());
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('a stop while the mic is connecting opens no detector and no rAF loop, and closes the mic', async () => {
    const audio = await import('./services/audioGraph');
    let resolveConnect: (a: AnalyserNode) => void = () => {};
    vi.mocked(audio.connectSource).mockImplementationOnce(
      () => new Promise<AnalyserNode>((r) => { resolveConnect = r; }),
    );
    vi.mocked(audio.disposeAudioGraph).mockClear();
    const dj = buildActive();

    const started = dj.startAutoTransition({ source: 'beat', intervalMs: 1000, durationMs: 500 });
    await flushAsync();
    expect(audio.connectSource).toHaveBeenCalled();
    dj.stopAutoTransition();
    const disposesAtStop = vi.mocked(audio.disposeAudioGraph).mock.calls.length;
    resolveConnect({} as AnalyserNode);

    await expect(started).resolves.toBe(false);
    expect(rafSpy).not.toHaveBeenCalled();
    // The late-resolving connect is disposed again (stop's dispose ran before the mic opened).
    expect(vi.mocked(audio.disposeAudioGraph).mock.calls.length).toBe(disposesAtStop + 1);
  });

  it('overlapping starts leave exactly one transition loop', async () => {
    const dj = buildActive();
    const a = dj.startAutoTransition({ source: 'timer', intervalMs: 1_000_000, durationMs: 500 });
    const b = dj.startAutoTransition({ source: 'timer', intervalMs: 1_000_000, durationMs: 500 });
    const results = await Promise.all([a, b]);
    expect(results).toEqual([false, true]);
    expect(rafSpy).toHaveBeenCalledTimes(1);
    dj.stopAutoTransition();
  });
});

describe('Alucinate run timers', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('stop() cancels the pending image swap, even across a quick restart', async () => {
    const onNextImage = vi.fn();
    const dj = new Alucinate(
      onNextImage,
      vi.fn(),
      () => ({ currentImage: { url: 'https://img/a.jpg', tags: [] } as never, currentShader: null }),
    );
    const internals = dj as unknown as Internals & { imageManifest: Array<{ url: string; tags: string[] }> };
    internals.status = 'ready';
    internals.llm = {};
    internals.shaderManifest = [{ id: 'liquid', name: 'Liquid', tags: [], params: [] }];
    internals.imageManifest = [{ url: 'https://img/b.jpg', tags: ['sea'] }];
    internals.captioner = vi.fn().mockResolvedValue([{ generated_text: 'a forest' }]);
    internals.selectShadersFromLLM = vi.fn().mockResolvedValue(null);
    const theme = vi.fn().mockResolvedValue('sea');
    internals.getNextImageThemeFromLLM = theme;

    dj.start();
    await flushAsync();
    vi.advanceTimersByTime(2000);
    await flushAsync();
    expect(theme).toHaveBeenCalledTimes(1);

    dj.stop();
    internals.captioner = vi.fn(() => new Promise<Array<{ generated_text: string }>>(() => {})); // the restarted cycle stays parked
    dj.start();
    vi.advanceTimersByTime(5000);
    await flushAsync();
    expect(onNextImage).not.toHaveBeenCalled();
    dj.stop();
  });
});
