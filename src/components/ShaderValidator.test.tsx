import type { Mock } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import ShaderValidator from './ShaderValidator';
import { runWebGpuBootProbe } from '../renderer/webgpuBootProbe';
import {
  getRendererDevice,
  publishRendererDevice,
  resetRendererDeviceRegistryForTests,
} from '../renderer/deviceRegistry';

// naga is the primary validator now, so the component never reaches the device
// path without it. A trivial stub is enough here — the real artifact is
// exercised in ShaderValidator.naga.test.tsx. Plain function, not vi.fn():
// CRA's resetMocks would strip a vi.fn implementation between tests.
vi.mock('../renderer/webgpuBootProbe', async () => ({
  ...(await vi.importActual<Record<string, unknown>>('../renderer/webgpuBootProbe')),
  runWebGpuBootProbe: vi.fn(),
}));

vi.mock('../utils/nagaWasm', async () => ({
  ...(await vi.importActual<Record<string, unknown>>('../utils/nagaWasm')),
  loadNagaValidator: () => Promise.resolve({ validate: () => ({ ok: true }) }),
}));

describe('ShaderValidator device policy', () => {
  const requestAdapter = vi.fn();
  const requestDevice = vi.fn();
  let mockDestroy: Mock;

  beforeEach(() => {
    resetRendererDeviceRegistryForTests();
    window.webgpuProbe = {
      ok: true,
      finishedAt: new Date().toISOString(),
      userAgent: 'test',
      userAgentBrands: [],
      attempts: [],
    };

    mockDestroy = vi.fn();
    const mockDevice = {
      createShaderModule: vi.fn().mockReturnValue({
        getCompilationInfo: vi.fn().mockResolvedValue({ messages: [] }),
      }),
      features: new Set<string>(),
      destroy: mockDestroy,
    } as unknown as GPUDevice;
    publishRendererDevice(mockDevice, { supportsSubgroups: false });

    const nav = navigator as unknown as {
      gpu?: { requestAdapter: typeof requestAdapter; requestDevice: typeof requestDevice };
    };
    nav.gpu = { requestAdapter, requestDevice };

    global.fetch = vi.fn().mockImplementation(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes('/shader-lists/')) {
        return {
          ok: true,
          status: 200,
          json: async () => [],
        } as Response;
      }
      return {
        ok: true,
        status: 200,
        text: async () => '@compute @workgroup_size(1) fn main() {}',
      } as Response;
    });
  });

  afterEach(() => {
    delete window.webgpuProbe;
    resetRendererDeviceRegistryForTests();
    vi.restoreAllMocks();
  });

  it('never calls requestAdapter, requestDevice, or device.destroy when the renderer device is registered', async () => {
    render(<ShaderValidator />);
    // Opt into the GPU pass: otherwise validation is GPU-less and this would
    // pass without ever exercising the GPU compile pass.
    fireEvent.click(screen.getByLabelText(/Also compile on the GPU/));
    fireEvent.click(screen.getByText(/Run Full Validation/));

    await waitFor(() => expect(requestAdapter).not.toHaveBeenCalled());
    expect(requestDevice).not.toHaveBeenCalled();

    expect(mockDestroy).not.toHaveBeenCalled();
  });

  it('on the standalone page (no renderer) it probes its own device, keeps it out of the registry and destroys it', async () => {
    resetRendererDeviceRegistryForTests();
    delete window.webgpuProbe;
    let resolveLost: (v: unknown) => void = () => {};
    const ownDestroy = vi.fn(() => resolveLost({ reason: 'destroyed', message: '' }));
    const ownDevice = {
      createShaderModule: vi.fn().mockReturnValue({
        getCompilationInfo: vi.fn().mockResolvedValue({ messages: [] }),
      }),
      features: new Set<string>(),
      lost: new Promise((r) => { resolveLost = r; }),
      destroy: ownDestroy,
    } as unknown as GPUDevice;
    (runWebGpuBootProbe as Mock).mockResolvedValue({
      ok: true,
      finishedAt: '',
      userAgent: 'test',
      userAgentBrands: [],
      attempts: [],
      handoff: { device: ownDevice, supportsSubgroups: false },
    });

    render(<ShaderValidator />);
    fireEvent.click(screen.getByLabelText(/Also compile on the GPU/));
    fireEvent.click(screen.getByText(/Run Full Validation/));

    await waitFor(() => expect(ownDestroy).toHaveBeenCalledTimes(1));
    expect(getRendererDevice()).toBeNull();
    expect(requestDevice).not.toHaveBeenCalled();
  });
});
