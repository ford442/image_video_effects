import { CalibrationStore } from './calibrationStore';
import { defaultOutputConfig, nudgeCorner } from './outputConfig';
import { StageController, windowFeatures, type StageOutputBackend } from './stageController';
import {
  devicePixelSize,
  isValidOutputId,
  parseControlToStage,
  parseStageToControl,
  STAGE_TAG,
  stageUrl,
} from './stageProtocol';

const ORIGIN = 'http://app.test';

function memoryStore() {
  const data = new Map<string, string>();
  return new CalibrationStore({ getItem: (k) => data.get(k) ?? null, setItem: (k, v) => { data.set(k, v); } });
}

function setup(opts: { blockPopup?: boolean; backend?: StageOutputBackend | null; store?: CalibrationStore } = {}) {
  const listeners = new Set<(e: MessageEvent) => void>();
  const stages: Array<{ closed: boolean; postMessage: ReturnType<typeof vi.fn>; focus: () => void; close: () => void }> = [];
  const control = {
    location: { href: `${ORIGIN}/app/?foo=1#x`, origin: ORIGIN },
    open: vi.fn(() => {
      if (opts.blockPopup) return null;
      const w = { closed: false, postMessage: vi.fn(), focus: vi.fn(), close() { this.closed = true; } };
      stages.push(w);
      return w;
    }),
    addEventListener: (_t: string, l: (e: MessageEvent) => void) => listeners.add(l),
    removeEventListener: (_t: string, l: (e: MessageEvent) => void) => listeners.delete(l),
  };
  const attached = new Map<string, unknown>();
  const backend: StageOutputBackend = opts.backend === undefined ? {
    attachOutput: vi.fn(async (id: string, _c, _w, _h, config) => {
      attached.set(id, config);
      return { ok: true, format: 'bgra8unorm' as GPUTextureFormat };
    }),
    detachOutput: vi.fn((id: string) => { attached.delete(id); }),
    setOutputConfig: vi.fn(),
    setOutputSize: vi.fn(),
    getOutputStatus: vi.fn(() => []),
  } : (opts.backend as StageOutputBackend);
  const controller = new StageController({
    win: control as unknown as Window,
    getBackend: () => (opts.backend === null ? null : backend),
    store: opts.store ?? memoryStore(),
    pollMs: 60_000,
  });
  const fromStage = async (i: number, data: Record<string, unknown>, origin = ORIGIN) => {
    for (const l of listeners) l({ origin, source: stages[i], data: { px: STAGE_TAG, ...data } } as unknown as MessageEvent);
    await new Promise((r) => setTimeout(r, 0));
  };
  return { controller, control, stages, backend, attached, fromStage };
}

const canvas = () => ({}) as OffscreenCanvas;

describe('StageController', () => {
  afterEach(() => vi.restoreAllMocks());

  it('opens a stage, asks it for a canvas and attaches it with the stored layout', async () => {
    const store = memoryStore();
    const saved = nudgeCorner(defaultOutputConfig(), 0, 0.1, 0);
    store.saveLayout('stage-1', saved);
    const { controller, control, stages, backend, fromStage } = setup({ store });
    const id = controller.open();
    expect(id).toBe('stage-1');
    expect(control.open).toHaveBeenCalledWith(`${ORIGIN}/app/?mode=stage&output=stage-1`, 'pixelocity-stage-stage-1', 'popup,width=960,height=540');
    expect(controller.get('stage-1')?.state).toBe('opening');

    await fromStage(0, { type: 'hello', outputId: 'stage-1' });
    expect(stages[0]?.postMessage).toHaveBeenCalledWith({ px: STAGE_TAG, type: 'request-canvas', outputId: 'stage-1' }, ORIGIN);
    expect(controller.get('stage-1')?.state).toBe('attaching');

    const c = canvas();
    await fromStage(0, { type: 'canvas', outputId: 'stage-1', canvas: c, width: 1920, height: 1080, serial: 1 });
    expect(backend.attachOutput).toHaveBeenCalledWith('stage-1', c, 1920, 1080, saved);
    expect(controller.get('stage-1')).toMatchObject({ state: 'live', width: 1920, height: 1080 });
  });

  it('forwards resizes and config edits to the backend and persists the layout', async () => {
    const store = memoryStore();
    const { controller, backend, fromStage } = setup({ store });
    controller.open();
    await fromStage(0, { type: 'canvas', outputId: 'stage-1', canvas: canvas(), width: 800, height: 600, serial: 1 });
    await fromStage(0, { type: 'resize', outputId: 'stage-1', width: 1024, height: 768 });
    expect(backend.setOutputSize).toHaveBeenCalledWith('stage-1', 1024, 768);
    const next = { ...defaultOutputConfig(), testPattern: 'grid' as const };
    controller.setConfig('stage-1', next);
    expect(backend.setOutputConfig).toHaveBeenCalledWith('stage-1', next);
    expect(store.loadLayout('stage-1')?.testPattern).toBe('grid');
  });

  it('applies calibration keys forwarded from the stage window', async () => {
    const { controller, fromStage } = setup();
    controller.open();
    await fromStage(0, { type: 'canvas', outputId: 'stage-1', canvas: canvas(), width: 1000, height: 1000, serial: 1 });
    await fromStage(0, { type: 'key', outputId: 'stage-1', key: '2', shift: false, alt: false });
    await fromStage(0, { type: 'key', outputId: 'stage-1', key: 'ArrowLeft', shift: true, alt: false });
    const s = controller.get('stage-1');
    expect(s?.selected).toBe(1);
    expect(s?.config.corners[1]?.[0]).toBeCloseTo(0.99);
  });

  it('detaches when the stage says bye or its window closes', async () => {
    const { controller, stages, backend, fromStage } = setup();
    controller.open();
    await fromStage(0, { type: 'canvas', outputId: 'stage-1', canvas: canvas(), width: 10, height: 10, serial: 1 });
    await fromStage(0, { type: 'bye', outputId: 'stage-1' });
    expect(backend.detachOutput).toHaveBeenCalledWith('stage-1');
    expect(controller.get('stage-1')?.state).toBe('closed');
    // Reopening reuses the id and the window name.
    expect(controller.open({ id: 'stage-1' })).toBe('stage-1');
    expect(stages).toHaveLength(2);
  });

  it('re-requests a canvas from every open stage after a backend switch', async () => {
    const { controller, stages, fromStage } = setup();
    controller.open();
    controller.open();
    await fromStage(0, { type: 'canvas', outputId: 'stage-1', canvas: canvas(), width: 10, height: 10, serial: 1 });
    stages[1]?.close();
    stages[0]?.postMessage.mockClear();
    controller.reattachAll();
    expect(stages[0]?.postMessage).toHaveBeenCalledWith({ px: STAGE_TAG, type: 'request-canvas', outputId: 'stage-1' }, ORIGIN);
    expect(stages[1]?.postMessage).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'request-canvas' }), ORIGIN);
    expect(controller.get('stage-1')?.state).toBe('attaching');
  });

  it('reports a blocked popup, a missing backend and a failed attach', async () => {
    expect(setup({ blockPopup: true }).controller.open()).toBeNull();
    const blocked = setup({ blockPopup: true });
    blocked.controller.open({ id: 'wall' });
    expect(blocked.controller.get('wall')).toMatchObject({ state: 'failed' });

    const none = setup({ backend: null });
    none.controller.open();
    await none.fromStage(0, { type: 'canvas', outputId: 'stage-1', canvas: canvas(), width: 10, height: 10, serial: 1 });
    expect(none.controller.get('stage-1')?.state).toBe('failed');

    const failing: StageOutputBackend = {
      attachOutput: vi.fn(async () => ({ ok: false, error: 'nope' })),
      detachOutput: vi.fn(), setOutputConfig: vi.fn(), setOutputSize: vi.fn(), getOutputStatus: () => [],
    };
    const bad = setup({ backend: failing });
    bad.controller.open();
    await bad.fromStage(0, { type: 'canvas', outputId: 'stage-1', canvas: canvas(), width: 10, height: 10, serial: 1 });
    expect(bad.controller.get('stage-1')).toMatchObject({ state: 'failed', error: 'nope' });
  });

  it('ignores messages from another origin or another window', async () => {
    const { controller, backend, fromStage } = setup();
    controller.open();
    await fromStage(0, { type: 'canvas', outputId: 'stage-1', canvas: canvas(), width: 10, height: 10, serial: 1 }, 'http://evil.test');
    expect(backend.attachOutput).not.toHaveBeenCalled();
  });

  it('places the window on a chosen display', () => {
    expect(windowFeatures({ label: 'Projector', left: 1920, top: 0, width: 1280, height: 800, isPrimary: false }))
      .toBe('popup,left=1920,top=0,width=1280,height=800');
  });
});

describe('stageProtocol', () => {
  it('validates output ids', () => {
    expect(isValidOutputId('stage-1')).toBe(true);
    expect(isValidOutputId('Stage 1')).toBe(false);
    expect(isValidOutputId('-x')).toBe(false);
    expect(isValidOutputId('a'.repeat(40))).toBe(false);
  });

  it('parses stage → control messages and rejects junk', () => {
    expect(parseStageToControl({ px: STAGE_TAG, type: 'hello', outputId: 'stage-1' })).toEqual({ px: STAGE_TAG, type: 'hello', outputId: 'stage-1' });
    expect(parseStageToControl({ px: 'other', type: 'hello', outputId: 'stage-1' })).toBeNull();
    expect(parseStageToControl({ px: STAGE_TAG, type: 'resize', outputId: 'stage-1', width: 0, height: 5 })).toBeNull();
    expect(parseStageToControl({ px: STAGE_TAG, type: 'canvas', outputId: 'stage-1', canvas: null, width: 5, height: 5 })).toBeNull();
    expect(parseStageToControl({ px: STAGE_TAG, type: 'launch', outputId: 'stage-1' })).toBeNull();
  });

  it('parses control → stage messages for this output only', () => {
    expect(parseControlToStage({ px: STAGE_TAG, type: 'request-canvas', outputId: 'a' }, 'a')).toMatchObject({ type: 'request-canvas' });
    expect(parseControlToStage({ px: STAGE_TAG, type: 'request-canvas', outputId: 'b' }, 'a')).toBeNull();
    expect(parseControlToStage({ px: STAGE_TAG, type: 'identify', outputId: 'a', label: 7 }, 'a')).toMatchObject({ label: 'a' });
  });

  it('builds the stage URL from the app root and sizes in device pixels', () => {
    expect(stageUrl('wall', 'https://x.test/app/index.html?mode=remote#h')).toBe('https://x.test/app/index.html?mode=stage&output=wall');
    expect(devicePixelSize(960, 540, 2)).toEqual({ width: 1920, height: 1080 });
    expect(devicePixelSize(0, 0, NaN)).toEqual({ width: 1, height: 1 });
  });
});
