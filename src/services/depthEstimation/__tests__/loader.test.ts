import { loadTransformersModule } from '../../aiModels/transformersLoader';
import {
  isDepthWebGpuAvailable,
  loadDepthPipeline,
  resetDepthPipelineCache,
} from '../loader';

jest.mock('../../aiModels/transformersLoader');

const mockPipeline = jest.fn().mockResolvedValue({ predict: jest.fn() });

describe('depthEstimation/loader device policy', () => {
  const requestAdapter = jest.fn();

  beforeEach(() => {
    resetDepthPipelineCache();
    mockPipeline.mockClear();
    (loadTransformersModule as jest.Mock).mockResolvedValue({ pipeline: mockPipeline });
    window.webgpuProbe = {
      ok: true,
      finishedAt: new Date().toISOString(),
      userAgent: 'test',
      userAgentBrands: [],
      attempts: [],
    };
    const nav = navigator as unknown as { gpu?: { requestAdapter: typeof requestAdapter } };
    nav.gpu = { requestAdapter };
  });

  afterEach(() => {
    delete window.webgpuProbe;
    resetDepthPipelineCache();
    jest.clearAllMocks();
  });

  it('isDepthWebGpuAvailable uses probe gate without requestAdapter', () => {
    expect(isDepthWebGpuAvailable()).toBe(true);
    expect(requestAdapter).not.toHaveBeenCalled();
  });

  it('isDepthWebGpuAvailable is false when probe failed', () => {
    window.webgpuProbe = {
      ok: false,
      finishedAt: new Date().toISOString(),
      userAgent: 'test',
      userAgentBrands: [],
      attempts: [],
    };
    expect(isDepthWebGpuAvailable()).toBe(false);
    expect(requestAdapter).not.toHaveBeenCalled();
  });

  it('loadDepthPipeline never calls requestAdapter and prefers wasm when renderer is live', async () => {
    const result = await loadDepthPipeline({ rendererDeviceActive: true });

    expect(requestAdapter).not.toHaveBeenCalled();
    expect(result.backend).toBe('wasm');
    expect(mockPipeline).toHaveBeenCalledWith(
      'depth-estimation',
      expect.any(String),
      expect.not.objectContaining({ device: 'webgpu' }),
    );
  });
});
