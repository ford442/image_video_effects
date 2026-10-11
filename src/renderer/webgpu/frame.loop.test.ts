/**
 * #1395: a throwing renderFrame must not end the frame loop silently.
 */

import { setRendererErrorHandler, type RendererError } from '../ErrorHandling';
import { WebGPUFrameRenderer } from './frame';
import type { WebGPUFrameState } from './frameState';

describe('WebGPUFrameRenderer.startRenderLoop', () => {
  let queued: Array<() => void>;
  const errors: RendererError[] = [];

  beforeEach(() => {
    queued = [];
    errors.length = 0;
    jest.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => {
      queued.push(() => cb(0));
      return queued.length;
    });
    setRendererErrorHandler((e) => errors.push(e));
  });

  afterEach(() => {
    jest.restoreAllMocks();
    setRendererErrorHandler(() => {});
  });

  const tick = () => {
    const next = queued.shift();
    if (!next) throw new Error('loop did not schedule another frame');
    next();
  };

  it('keeps scheduling frames after renderFrame throws, and reports the error once', () => {
    const state = { initialized: true, startTime: 0, currentTime: 0, animationId: null } as unknown as WebGPUFrameState;
    const renderer = new WebGPUFrameRenderer();
    let calls = 0;
    jest.spyOn(renderer, 'renderFrame').mockImplementation(() => {
      calls += 1;
      if (calls <= 2) throw new Error('boom');
    });

    renderer.startRenderLoop(state);
    tick();
    tick();

    expect(calls).toBe(3);
    expect(queued).toHaveLength(1);
    expect(errors).toEqual([{ type: 'render-frame', message: 'boom', recoverable: true }]);
  });

  it('stops scheduling once the state is no longer initialized', () => {
    const state = { initialized: true, startTime: 0, currentTime: 0, animationId: null } as unknown as WebGPUFrameState;
    const renderer = new WebGPUFrameRenderer();
    jest.spyOn(renderer, 'renderFrame').mockImplementation(() => {
      state.initialized = false;
      throw new Error('device gone');
    });

    renderer.startRenderLoop(state);
    expect(queued).toHaveLength(0);
  });
});
