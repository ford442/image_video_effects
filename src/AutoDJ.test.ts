/**
 * #1395: one failed cycle must not stop the AI VJ loop for good.
 */

import { Alucinate } from './AutoDJ';

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
  const onUpdateStack = jest.fn();
  const dj = new Alucinate(
    jest.fn(),
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
    jest.useFakeTimers();
    jest.spyOn(console, 'log').mockImplementation(() => {});
    jest.spyOn(console, 'error').mockImplementation(() => {});
    jest.spyOn(console, 'warn').mockImplementation(() => {});
  });
  afterEach(() => {
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('keeps cycling after the captioner rejects', async () => {
    const { dj, internals, onUpdateStack } = build();
    const captioner = jest.fn().mockRejectedValue(new Error('model crashed'));
    internals.captioner = captioner;

    expect(dj.start()).toBe(true);
    await flushAsync();
    expect(captioner).toHaveBeenCalledTimes(1);
    expect(internals.status).toBe('error');
    expect(onUpdateStack).toHaveBeenLastCalledWith(['liquid', 'none', 'none']);

    jest.advanceTimersByTime(CYCLE_MS);
    await flushAsync();
    expect(captioner).toHaveBeenCalledTimes(2);

    dj.stop();
  });

  it('returns to ready when no next theme comes back, so the next tick runs', async () => {
    const { dj, internals } = build();
    const captioner = jest.fn().mockResolvedValue([{ generated_text: 'a forest' }]);
    internals.captioner = captioner;
    internals.selectShadersFromLLM = jest.fn().mockResolvedValue(null);
    internals.getNextImageThemeFromLLM = jest.fn().mockResolvedValue(null);

    dj.start();
    await flushAsync();
    jest.advanceTimersByTime(2000); // pause between stack and theme
    await flushAsync();
    expect(internals.status).toBe('ready');

    jest.advanceTimersByTime(CYCLE_MS);
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
