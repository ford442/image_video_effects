/**
 * #1311 WP-A — WebGPUCanvas lifecycle pins: remount waits for teardown before re-probing.
 */
import React from 'react';
import { render, act } from '@testing-library/react';
import WebGPUCanvas from './WebGPUCanvas';
import { RendererManager } from '../renderer/RendererManager';
import { runWebGpuBootProbe } from '../renderer/webgpuBootProbe';
import type { SlotParams } from '../renderer/types';

const teardowns: Array<() => void> = [];
const events: string[] = [];

jest.mock('../renderer/RendererManager', () => ({
  getRendererTypeFromURL: () => null,
  RendererManager: class {
    init() { events.push('init'); return Promise.resolve(true); }
    destroy() {
      events.push('destroy');
      return new Promise<void>((resolve) => teardowns.push(() => { events.push('teardown-done'); resolve(); }));
    }
    setVideo() {}
    setInputSource() {}
    syncAllSlotParams() {}
    render() {}
    setParam() {}
    onBackendFailure() {}
    getAvailableModes() { return []; }
  },
}));

jest.mock('../renderer/webgpuBootProbe', () => ({
  runWebGpuBootProbe: jest.fn(),
  publishWebGpuProbe: () => {},
  publishWasmProbeFailure: () => {},
  toWebGpuProbeBreadcrumb: () => null,
}));

beforeAll(() => {
  (global as any).ResizeObserver = class { observe() {} unobserve() {} disconnect() {} };
  for (const m of ['play', 'pause', 'load'] as const) {
    Object.defineProperty(window.HTMLMediaElement.prototype, m, {
      writable: true,
      value: () => Promise.resolve(),
    });
  }
});

function mount() {
  const rendererRef = { current: null as RendererManager | null };
  return render(
    <WebGPUCanvas
      modes={['none', 'none', 'none']}
      slotParams={[{}, {}, {}] as SlotParams[]}
      rendererRef={rendererRef}
      farthestPoint={{ x: 0.5, y: 0.5 }}
      mousePosition={{ x: -1, y: -1 }}
      setMousePosition={() => {}}
      isMouseDown={false}
      setIsMouseDown={() => {}}
      inputSource="image"
      selectedVideo=""
      isMuted
      activeSlot={0}
      apiBaseUrl=""
    />,
  );
}

const flush = () => act(async () => { await new Promise((r) => setTimeout(r, 0)); });

describe('WebGPUCanvas lifecycle (#1311 WP-A)', () => {
  beforeEach(() => {
    teardowns.length = 0;
    events.length = 0;
    jest.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({
      width: 800, height: 600, top: 0, left: 0, right: 800, bottom: 600, x: 0, y: 0, toJSON: () => ({}),
    } as DOMRect);
    (runWebGpuBootProbe as jest.Mock).mockImplementation(async () => {
      events.push('probe');
      return { ok: true, handoff: undefined };
    });
  });

  it('remount re-probes only after the previous renderer teardown resolves', async () => {
    const first = mount();
    await flush();
    expect(runWebGpuBootProbe).toHaveBeenCalledTimes(1);
    first.unmount();
    mount();
    await flush();
    expect(teardowns).toHaveLength(1);
    expect(runWebGpuBootProbe).toHaveBeenCalledTimes(1);

    await act(async () => { teardowns[0](); });
    await flush();
    expect(runWebGpuBootProbe).toHaveBeenCalledTimes(2);
    expect(events.indexOf('teardown-done')).toBeLessThan(events.lastIndexOf('probe'));
  });
});
