import { mountStage } from './stagePage';
import { STAGE_TAG } from './stageProtocol';

describe('mountStage (stage window)', () => {
  const posted: Array<{ msg: Record<string, unknown>; transfer: unknown[] }> = [];
  let opener: { closed: boolean; postMessage: (m: unknown, o: { transfer?: unknown[] }) => void };
  let handle: { dispose(): void } | null = null;

  beforeEach(() => {
    posted.length = 0;
    document.body.innerHTML = '<div id="root"></div>';
    opener = {
      closed: false,
      postMessage: (m, o) => posted.push({ msg: m as Record<string, unknown>, transfer: o.transfer ?? [] }),
    };
    Object.defineProperty(window, 'opener', { configurable: true, value: opener });
    const offscreen = { kind: 'offscreen' };
    (HTMLCanvasElement.prototype as unknown as { transferControlToOffscreen: () => unknown }).transferControlToOffscreen =
      vi.fn(() => offscreen);
  });

  afterEach(() => {
    handle?.dispose();
    handle = null;
    delete (HTMLCanvasElement.prototype as unknown as { transferControlToOffscreen?: unknown }).transferControlToOffscreen;
  });

  const fromControl = (data: Record<string, unknown>) =>
    window.dispatchEvent(new MessageEvent('message', { data: { px: STAGE_TAG, ...data }, origin: window.location.origin, source: opener as unknown as Window }));

  it('says hello, then transfers a fresh canvas each time one is requested', () => {
    handle = mountStage(window, 'wall');
    expect(posted[0]?.msg).toEqual({ px: STAGE_TAG, type: 'hello', outputId: 'wall' });
    fromControl({ type: 'request-canvas', outputId: 'wall' });
    fromControl({ type: 'request-canvas', outputId: 'wall' });
    const canvases = posted.filter((p) => p.msg.type === 'canvas');
    expect(canvases).toHaveLength(2);
    expect(canvases[1]?.msg).toMatchObject({ outputId: 'wall', serial: 2 });
    expect(canvases[0]?.transfer).toEqual([{ kind: 'offscreen' }]);
    // Only the newest canvas stays in the page.
    expect(document.querySelectorAll('canvas')).toHaveLength(1);
  });

  it('ignores requests for another output and forwards calibration keys', () => {
    handle = mountStage(window, 'wall');
    fromControl({ type: 'request-canvas', outputId: 'other' });
    expect(posted.some((p) => p.msg.type === 'canvas')).toBe(false);
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', shiftKey: true }));
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'x' }));
    expect(posted.filter((p) => p.msg.type === 'key').map((p) => p.msg)).toEqual([
      { px: STAGE_TAG, type: 'key', outputId: 'wall', key: 'ArrowUp', shift: true, alt: false },
    ]);
  });

  it('says bye when the page goes away', () => {
    handle = mountStage(window, 'wall');
    window.dispatchEvent(new Event('pagehide'));
    expect(posted.at(-1)?.msg).toEqual({ px: STAGE_TAG, type: 'bye', outputId: 'wall' });
  });
});
