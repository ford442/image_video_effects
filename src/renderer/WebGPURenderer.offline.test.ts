/**
 * Offline render on the TS renderer (#1401): stepped clock, exact frame times, live input
 * kept out, the live size / clock / quality policy restored afterwards. The GPU work itself
 * is stubbed (frame.ts and resources have their own tests); a real device runs it in
 * tests/golden-frames.swiftshader.spec.ts.
 */

import type { Mock } from 'vitest';
import { WebGPURenderer } from './WebGPURenderer';
import { DEFAULT_CONFIG } from './Renderer';
import type { WebGPUFrameState } from './webgpu/frameState';
import { getModulationRuntime, resetModulationRuntime } from '../modulation/runtime';

class FakeVideoFrame {
  readonly timestamp: number;
  readonly duration: number | null;
  closed = false;
  constructor(_source: unknown, init: { timestamp: number; duration?: number }) {
    this.timestamp = init.timestamp;
    this.duration = init.duration ?? null;
  }
  close() {
    this.closed = true;
  }
}

interface Internals {
  device: GPUDevice | null;
  frameState?: WebGPUFrameState;
  presentCanvas: { width: number; height: number } | null;
  canvasW: number;
  canvasH: number;
  scaledW: number;
  scaledH: number;
  resolutionScale: number;
  adaptiveQuality: boolean;
  currentTime: number;
  mouseX: number;
  mouseYShader: number;
  mouseDown: boolean;
  ripples: unknown[];
  inputSource: string;
  clock: { mode: string; now(): number };
  frameRenderer: {
    renderFrame(state: WebGPUFrameState): void;
    stopRenderLoop(state: WebGPUFrameState): void;
    startRenderLoop(state: WebGPUFrameState): void;
    startCrossfade(state: WebGPUFrameState, ms: number): boolean;
  };
  rebuildComputeBindGroup(): void;
  afterFrameSubmit(): void;
  slotZoomParams: number[][];
}

function setup() {
  const r = new WebGPURenderer(DEFAULT_CONFIG);
  const i = r as unknown as Internals;
  const onSubmittedWorkDone = vi.fn(async () => undefined);
  i.device = { limits: { maxTextureDimension2D: 8192 }, queue: { onSubmittedWorkDone } } as unknown as GPUDevice;
  const state = { initialized: true, animationId: 7 } as unknown as WebGPUFrameState;
  i.frameState = state;
  r.initialized = true;
  i.presentCanvas = { width: 1920, height: 1080 };
  i.canvasW = 1920;
  i.canvasH = 1080;
  i.resolutionScale = 0.5;
  i.adaptiveQuality = true;
  i.inputSource = 'generative';
  const recreate = vi.spyOn(r.resources, 'recreateScaleTextures').mockImplementation(() => ({}) as never);
  vi.spyOn(i, 'rebuildComputeBindGroup').mockImplementation(() => undefined);
  const stop = vi.spyOn(i.frameRenderer, 'stopRenderLoop').mockImplementation((s) => {
    (s as { animationId: number | null }).animationId = null;
  });
  const start = vi.spyOn(i.frameRenderer, 'startRenderLoop').mockImplementation((s) => {
    (s as { animationId: number | null }).animationId = 8;
  });
  vi.spyOn(i.frameRenderer, 'startCrossfade').mockImplementation(() => false);
  const seen: Array<{ time: number; mouse: [number, number]; down: boolean; ripples: number }> = [];
  const render = vi.spyOn(i.frameRenderer, 'renderFrame').mockImplementation(() => {
    r.beforeFrame();
    seen.push({ time: i.currentTime, mouse: [i.mouseX, i.mouseYShader], down: i.mouseDown, ripples: i.ripples.length });
    i.afterFrameSubmit(); // what the real frame does right after queue.submit
  });
  return { r, i, state, recreate, stop, start, render, seen, onSubmittedWorkDone };
}

beforeEach(() => {
  vi.stubGlobal('VideoFrame', FakeVideoFrame);
  vi.spyOn(console, 'log').mockImplementation(() => undefined);
  resetModulationRuntime();
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('WebGPURenderer offline render (#1401)', () => {
  it('begin stops the loop, steps a fresh clock and resizes the render target with fresh textures', async () => {
    const { r, i, state, recreate, stop, onSubmittedWorkDone } = setup();
    const reset = vi.spyOn(getModulationRuntime(), 'resetState');
    const info = await r.beginOfflineRender({ width: 3840, height: 2160, fps: 60 });
    expect(stop).toHaveBeenCalledWith(state);
    expect(onSubmittedWorkDone).toHaveBeenCalled();
    expect(i.clock.mode).toBe('stepped');
    expect(i.adaptiveQuality).toBe(false);
    expect(i.presentCanvas).toEqual({ width: 3840, height: 2160 });
    expect(recreate).toHaveBeenCalledWith(expect.anything(), 3840, 2160, i.scaledW, i.scaledH, expect.any(String));
    expect(reset).toHaveBeenCalled();
    expect(info).toMatchObject({ width: 3840, height: 2160, fps: 60, maxTextureDimension2D: 8192 });
    expect(r.isOfflineRenderActive()).toBe(true);
  });

  it('rejects sizes beyond the device limit and bad fps', async () => {
    const { r } = setup();
    await expect(r.beginOfflineRender({ width: 9000, height: 100, fps: 30 })).rejects.toThrow(RangeError);
    await expect(r.beginOfflineRender({ width: 640, height: 360, fps: 0 })).rejects.toThrow(RangeError);
    expect(r.isOfflineRenderActive()).toBe(false);
  });

  it('renderFrameAt renders exactly that time and returns the presented frame stamped with it', async () => {
    const { r, seen } = setup();
    await r.beginOfflineRender({ width: 640, height: 360, fps: 30 });
    const frames: FakeVideoFrame[] = [];
    for (let n = 0; n < 4; n++) frames.push((await r.renderFrameAt(n / 30, { mouse: [0.25, 0.75], mouseDown: true })) as unknown as FakeVideoFrame);
    expect(seen.map((f) => f.time)).toEqual([0, 1 / 30, 2 / 30, 3 / 30]);
    expect(frames.map((f) => f.timestamp)).toEqual([0, 33_333, 66_667, 100_000]);
    expect(frames.every((f) => f.duration === 33_333)).toBe(true);
    expect(seen[0]).toMatchObject({ mouse: [0.25, 0.75], down: true });
  });

  it('absent snapshot fields are neutral: an offline frame never inherits live input', async () => {
    const { r, i, seen } = setup();
    await r.beginOfflineRender({ width: 640, height: 360, fps: 30 });
    r.updateMouse(0.9, 0.1);
    r.setParam('mouseDown', 1);
    r.addRipple(0.5, 0.5);
    const ring = vi.fn();
    r.setBeforeFrame(ring);
    await r.renderFrameAt(0, {});
    expect(seen[0]).toEqual({ time: 0, mouse: [0.5, 0.5], down: false, ripples: 0 });
    expect(ring).not.toHaveBeenCalled();
    await r.renderFrameAt(0, { slotParams: [[2, 0.1, 0.2, 0.3, 0.4]] });
    expect(i.slotZoomParams[2]).toEqual([0.1, 0.2, 0.3, 0.4]);
  });

  it('live recorders get no frame while a job runs; renderFrameAt without begin throws', async () => {
    const { r } = setup();
    await expect(r.renderFrameAt(0)).rejects.toThrow(/no offline render is active/);
    await r.beginOfflineRender({ width: 640, height: 360, fps: 30 });
    expect(await r.grabPresentedFrame(0)).toBeNull();
  });

  it('defers live quality-policy changes to the end, then restores size, clock and loop', async () => {
    const { r, i, state, recreate, start } = setup();
    await r.beginOfflineRender({ width: 3840, height: 2160, fps: 60, resolutionScale: 1 });
    recreate.mockClear();
    r.setResolutionScale(0.75); // the page's adaptive policy reacting to the slow job
    r.setAdaptiveQuality(false);
    expect(i.resolutionScale).toBe(1);
    expect(recreate).not.toHaveBeenCalled();

    await r.endOfflineRender();
    expect(r.isOfflineRenderActive()).toBe(false);
    expect(i.clock.mode).toBe('realtime');
    expect(i.presentCanvas).toEqual({ width: 1920, height: 1080 });
    expect(i.resolutionScale).toBe(0.75);
    expect(i.adaptiveQuality).toBe(false);
    expect(recreate).toHaveBeenCalledWith(expect.anything(), 1920, 1080, i.scaledW, i.scaledH, expect.any(String));
    expect(start).toHaveBeenCalledWith(state);
    expect((state as { animationId: number | null }).animationId).toBe(8);
  });

  it('a target that cannot be allocated fails the begin and hands the live picture back', async () => {
    const { r, i, recreate, start } = setup();
    recreate.mockImplementationOnce(() => {
      throw new Error('out of memory');
    });
    await expect(r.beginOfflineRender({ width: 7680, height: 4320, fps: 30 })).rejects.toThrow('out of memory');
    expect(r.isOfflineRenderActive()).toBe(false);
    expect(i.clock.mode).toBe('realtime');
    expect(i.presentCanvas).toEqual({ width: 1920, height: 1080 });
    expect(start).toHaveBeenCalled();
  });

  it('a frame that never reaches submit answers null instead of hanging', async () => {
    const { r, render } = setup();
    await r.beginOfflineRender({ width: 64, height: 64, fps: 24 });
    render.mockImplementationOnce(() => undefined); // e.g. no canvas texture this time
    expect(await r.renderFrameAt(0)).toBeNull();
    (render as Mock).mockImplementationOnce(() => {
      throw new Error('encode failed');
    });
    await expect(r.renderFrameAt(1 / 24)).rejects.toThrow('encode failed');
  });
});
