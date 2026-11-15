import { createFakeGpu, type FakeGpu } from '../testing/fakeGpu';
import { defaultOutputConfig } from '../../output/outputConfig';
import { directPresentBlocker } from './directPresent';
import { MAX_OUTPUTS, OutputPresenter, type OutputCanvas } from './outputs';

function fakeCanvas(label: string, gpu: FakeGpu) {
  const configured: GPUCanvasConfiguration[] = [];
  let unconfigured = 0;
  const ctx = {
    configure: vi.fn((c: GPUCanvasConfiguration) => { configured.push(c); }),
    unconfigure: vi.fn(() => { unconfigured++; }),
    getCurrentTexture: vi.fn(() => gpu.texture(`swap:${label}`)),
  };
  const canvas: OutputCanvas & { ctx: typeof ctx } = {
    width: 300,
    height: 150,
    ctx,
    getContext: () => ctx as unknown as GPUCanvasContext,
  };
  return { canvas, configured, unconfigured: () => unconfigured };
}

describe('OutputPresenter', () => {
  let gpu: FakeGpu;
  beforeEach(() => {
    gpu = createFakeGpu();
  });

  it('configures each output canvas on the shared device and sizes it', () => {
    const p = new OutputPresenter();
    const a = fakeCanvas('a', gpu);
    const result = p.attach(gpu.device, 'stage-1', a.canvas, { width: 1920, height: 1080 }, {}, 'bgra8unorm');
    expect(result).toEqual({ ok: true, format: 'bgra8unorm' });
    expect(a.configured[0]).toMatchObject({ device: gpu.device, format: 'bgra8unorm', alphaMode: 'opaque' });
    expect([a.canvas.width, a.canvas.height]).toEqual([1920, 1080]);
    expect(p.count).toBe(1);
  });

  it('encodes one present pass per output into the frame encoder, reading the program texture', () => {
    const p = new OutputPresenter();
    p.attach(gpu.device, 'a', fakeCanvas('a', gpu).canvas, { width: 64, height: 64 }, {}, 'bgra8unorm');
    p.attach(gpu.device, 'b', fakeCanvas('b', gpu).canvas, { width: 64, height: 64 }, {}, 'rgba8unorm');
    const program = gpu.texture('blitReadTex');
    const encoder = gpu.device.createCommandEncoder({ label: 'frame' });
    p.encode(encoder, program, false);
    const passes = gpu.ops.filter((o) => o.op === 'beginRenderPass');
    expect(passes.map((o) => o.op === 'beginRenderPass' && o.target)).toEqual(['swap:a', 'swap:b']);
    expect(gpu.ops.filter((o) => o.op === 'draw')).toHaveLength(2);
    // One pipeline per swapchain format.
    expect(gpu.counters.createRenderPipeline).toBe(2);
    expect(p.status().map((s) => s.framesPresented)).toEqual([1, 1]);
  });

  it('caches the bind group until the program texture changes, and writes the uniform only when dirty', () => {
    const p = new OutputPresenter();
    p.attach(gpu.device, 'a', fakeCanvas('a', gpu).canvas, { width: 64, height: 64 }, {}, 'bgra8unorm');
    const program = gpu.texture('program');
    const enc = () => gpu.device.createCommandEncoder({ label: 'frame' });
    p.encode(enc(), program, false);
    const bg = gpu.counters.createBindGroup;
    const wb = gpu.counters.writeBuffer;
    p.encode(enc(), program, false);
    expect(gpu.counters.createBindGroup).toBe(bg);
    expect(gpu.counters.writeBuffer).toBe(wb);
    p.setConfig('a', { ...defaultOutputConfig(), testPattern: 'grid' });
    p.encode(enc(), program, false);
    expect(gpu.counters.writeBuffer).toBe(wb + 1);
    // Generative input flips the program: a new uniform, same bind group.
    p.encode(enc(), program, true);
    expect(gpu.counters.writeBuffer).toBe(wb + 2);
    p.encode(enc(), gpu.texture('program-resized'), true);
    expect(gpu.counters.createBindGroup).toBe(bg + 1);
  });

  it('resizes, detaches (unconfigure) and releases', () => {
    const p = new OutputPresenter();
    const a = fakeCanvas('a', gpu);
    p.attach(gpu.device, 'a', a.canvas, { width: 64, height: 64 }, {}, 'bgra8unorm');
    p.setSize('a', 1280.4, 719.6);
    expect([a.canvas.width, a.canvas.height]).toEqual([1280, 720]);
    p.detach('a');
    expect(a.unconfigured()).toBe(1);
    expect(p.count).toBe(0);
    p.attach(gpu.device, 'b', fakeCanvas('b', gpu).canvas, { width: 1, height: 1 }, {}, 'bgra8unorm');
    p.releaseAll();
    expect(p.count).toBe(0);
  });

  it('replaces an output re-attached under the same id', () => {
    const p = new OutputPresenter();
    const first = fakeCanvas('first', gpu);
    p.attach(gpu.device, 'a', first.canvas, { width: 64, height: 64 }, {}, 'bgra8unorm');
    p.attach(gpu.device, 'a', fakeCanvas('second', gpu).canvas, { width: 64, height: 64 }, {}, 'bgra8unorm');
    expect(first.unconfigured()).toBe(1);
    expect(p.count).toBe(1);
  });

  it('refuses a canvas without a webgpu context and caps the number of outputs', () => {
    const p = new OutputPresenter();
    const bad: OutputCanvas = { width: 1, height: 1, getContext: () => null };
    expect(p.attach(gpu.device, 'x', bad, { width: 1, height: 1 }, {}, 'bgra8unorm').ok).toBe(false);
    for (let i = 0; i < MAX_OUTPUTS; i++) {
      expect(p.attach(gpu.device, `o${i}`, fakeCanvas(`o${i}`, gpu).canvas, { width: 1, height: 1 }, {}, 'bgra8unorm').ok).toBe(true);
    }
    expect(p.attach(gpu.device, 'one-too-many', fakeCanvas('z', gpu).canvas, { width: 1, height: 1 }, {}, 'bgra8unorm').ok).toBe(false);
  });

  it('skips an output whose swapchain cannot be acquired and reports why', () => {
    const p = new OutputPresenter();
    const a = fakeCanvas('a', gpu);
    a.canvas.ctx.getCurrentTexture.mockImplementation(() => { throw new Error('canvas gone'); });
    p.attach(gpu.device, 'a', a.canvas, { width: 64, height: 64 }, {}, 'bgra8unorm');
    p.encode(gpu.device.createCommandEncoder({ label: 'f' }), gpu.texture('p'), false);
    expect(gpu.ops.some((o) => o.op === 'beginRenderPass')).toBe(false);
    expect(p.status()[0]).toMatchObject({ framesPresented: 0, lastError: 'canvas gone' });
  });

  it('flags a degenerate corner pin as singular', () => {
    const p = new OutputPresenter();
    p.attach(gpu.device, 'a', fakeCanvas('a', gpu).canvas, { width: 64, height: 64 },
      { corners: [[0.5, 0.5], [0.5, 0.5], [0.5, 0.5], [0.5, 0.5]] }, 'bgra8unorm');
    p.encode(gpu.device.createCommandEncoder({ label: 'f' }), gpu.texture('p'), false);
    expect(p.status()[0]?.singular).toBe(true);
  });
});

describe('direct present with stage outputs', () => {
  it('is blocked while an output is attached (outputs read the working texture)', () => {
    const plan = {
      enabledCount: 1,
      parallel: [],
      chained: [{ slot: { layer: undefined }, program: { kind: 'chain', shaderIds: ['x'] } }],
      anyUsesHistory: false,
    } as never;
    const base = {
      storageReady: true, enabled: true, plan, scaledW: 8, scaledH: 8, canvasW: 8, canvasH: 8,
      inputSource: 'image', captureHold: false,
    };
    expect(directPresentBlocker(base)).toBeNull();
    expect(directPresentBlocker({ ...base, outputsAttached: true })).toBe('outputs');
  });
});
