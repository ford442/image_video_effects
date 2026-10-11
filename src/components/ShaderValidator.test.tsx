import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import ShaderValidator from './ShaderValidator';
import { runWebGpuBootProbe } from '../renderer/webgpuBootProbe';
import {
  publishRendererDevice,
  resetRendererDeviceRegistryForTests,
} from '../renderer/deviceRegistry';

// naga is the primary validator now, so the component never reaches the device
// path without it. A trivial stub is enough here — the real artifact is
// exercised in ShaderValidator.naga.test.tsx. Plain function, not jest.fn():
// CRA's resetMocks would strip a jest.fn implementation between tests.
jest.mock('../renderer/webgpuBootProbe', () => ({
  ...jest.requireActual('../renderer/webgpuBootProbe'),
  runWebGpuBootProbe: jest.fn(),
}));

jest.mock('../utils/nagaWasm', () => ({
  ...jest.requireActual('../utils/nagaWasm'),
  loadNagaValidator: () => Promise.resolve({ validate: () => ({ ok: true }) }),
}));

describe('ShaderValidator device policy', () => {
  const requestAdapter = jest.fn();
  const requestDevice = jest.fn();
  let mockDestroy: jest.Mock;

  beforeEach(() => {
    resetRendererDeviceRegistryForTests();
    window.webgpuProbe = {
      ok: true,
      finishedAt: new Date().toISOString(),
      userAgent: 'test',
      userAgentBrands: [],
      attempts: [],
    };

    mockDestroy = jest.fn();
    const mockDevice = {
      createShaderModule: jest.fn().mockReturnValue({
        getCompilationInfo: jest.fn().mockResolvedValue({ messages: [] }),
      }),
      features: new Set<string>(),
      destroy: mockDestroy,
    } as unknown as GPUDevice;
    publishRendererDevice(mockDevice, { supportsSubgroups: false });

    const nav = navigator as unknown as {
      gpu?: { requestAdapter: typeof requestAdapter; requestDevice: typeof requestDevice };
    };
    nav.gpu = { requestAdapter, requestDevice };

    global.fetch = jest.fn().mockImplementation(async (input: RequestInfo | URL) => {
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
    jest.restoreAllMocks();
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
    const ownDestroy = jest.fn(() => resolveLost({ reason: 'destroyed', message: '' }));
    const ownDevice = {
      createShaderModule: jest.fn().mockReturnValue({
        getCompilationInfo: jest.fn().mockResolvedValue({ messages: [] }),
      }),
      features: new Set<string>(),
      lost: new Promise((r) => { resolveLost = r; }),
      destroy: ownDestroy,
    } as unknown as GPUDevice;
    (runWebGpuBootProbe as jest.Mock).mockResolvedValue({
      ok: true,
      finishedAt: '',
      userAgent: 'test',
      userAgentBrands: [],
      attempts: [],
      handoff: { device: ownDevice, supportsSubgroups: false },
    });
    const { getRendererDevice } = jest.requireActual('../renderer/deviceRegistry');

    render(<ShaderValidator />);
    fireEvent.click(screen.getByLabelText(/Also compile on the GPU/));
    fireEvent.click(screen.getByText(/Run Full Validation/));

    await waitFor(() => expect(ownDestroy).toHaveBeenCalledTimes(1));
    expect(getRendererDevice()).toBeNull();
    expect(requestDevice).not.toHaveBeenCalled();
  });
});
