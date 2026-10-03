/**
 * #1311 WP-A — WebGPURenderer lifecycle pins (no GPU: device/frame modules are mocked).
 */
import { WebGPURenderer } from './WebGPURenderer';
import { DEFAULT_CONFIG } from './Renderer';
import * as deviceModule from './webgpu/device';

jest.mock('./webgpu/device', () => ({
  initializeWebGPUDevice: jest.fn(),
  attachDeviceLostHandler: jest.fn(),
  buildCanvasConfigureOptions: () => ({}),
}));
jest.mock('./webgpu/frame', () => ({
  WebGPUFrameRenderer: class { startRenderLoop() {} stopRenderLoop() {} },
  createFrameState: () => ({}),
  createRendererFrameHost: () => ({}),
  computeScaledDimensions: () => ({ scaledW: 1024, scaledH: 1024 }),
}));

type Listener = (ev: Event) => void;

export function makeFakeDevice() {
  let resolveLost!: (info: { reason: string; message: string }) => void;
  const lost = new Promise<{ reason: string; message: string }>((r) => { resolveLost = r; });
  const listeners: Record<string, Listener[]> = {};
  const device = {
    lost,
    destroy: jest.fn(() => resolveLost({ reason: 'destroyed', message: '' })),
    addEventListener: jest.fn((type: string, fn: Listener) => { (listeners[type] ||= []).push(fn); }),
    dispatch(type: string, ev: Event) { (listeners[type] || []).forEach((fn) => fn(ev)); },
  };
  return device;
}

function outcomeFor(device: unknown) {
  return {
    ok: true,
    device,
    context: { unconfigure: jest.fn(), configure: jest.fn() },
    canvasFormat: 'bgra8unorm',
    canvasCopySrc: false,
    canvasColorOptIns: {},
    canvasW: 1024,
    canvasH: 1024,
    supportsSubgroups: false,
    supportsDeepWorkgroup: false,
    hasF32Filterable: false,
    formatCapabilities: {},
  };
}

describe('WebGPURenderer lifecycle (#1311 WP-A)', () => {
  beforeEach(() => jest.clearAllMocks());

  it('a real device loss after the OOM retry still runs the recovery path', async () => {
    const dev1 = makeFakeDevice();
    const dev2 = makeFakeDevice();
    (deviceModule.initializeWebGPUDevice as jest.Mock)
      .mockResolvedValueOnce(outcomeFor(dev1))
      .mockResolvedValueOnce(outcomeFor(dev2));
    const lostHandlers: Array<() => void> = [];
    (deviceModule.attachDeviceLostHandler as jest.Mock).mockImplementation((_d, _c, onLost) => lostHandlers.push(onLost));

    const renderer = new WebGPURenderer(DEFAULT_CONFIG);
    jest.spyOn(renderer as any, 'setupGpuResources')
      .mockResolvedValueOnce('lost')
      .mockResolvedValueOnce('ok');
    jest.spyOn(renderer.gpuChores, 'attach').mockImplementation(() => undefined as any);
    const detach = jest.spyOn(renderer.gpuChores, 'detach').mockImplementation(() => undefined as any);

    expect(await renderer.init(document.createElement('canvas'))).toBe(true);
    expect(dev1.destroy).toHaveBeenCalled();
    expect(lostHandlers).toHaveLength(2);

    expect((renderer as any).initialized).toBe(true);
    detach.mockClear();
    lostHandlers[1]();
    expect(detach).toHaveBeenCalledWith('device lost');
    expect((renderer as any).initialized).toBe(false);
  });
});
