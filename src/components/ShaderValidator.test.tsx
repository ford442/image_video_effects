import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import ShaderValidator from './ShaderValidator';
import {
  clearAdoptedRendererDevice,
  registerAdoptedRendererDevice,
} from '../utils/adoptedGpuDevice';

describe('ShaderValidator device policy', () => {
  const requestAdapter = jest.fn();
  const requestDevice = jest.fn();
  let mockDestroy: jest.Mock;

  beforeEach(() => {
    clearAdoptedRendererDevice();
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
      destroy: mockDestroy,
    } as unknown as GPUDevice;
    registerAdoptedRendererDevice(mockDevice, false);

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
    clearAdoptedRendererDevice();
    jest.restoreAllMocks();
  });

  it('never calls requestAdapter, requestDevice, or device.destroy when adopted device exists', async () => {
    render(<ShaderValidator />);
    fireEvent.click(screen.getByText(/Run Full Validation/));

    await waitFor(() => {
      expect(requestAdapter).not.toHaveBeenCalled();
      expect(requestDevice).not.toHaveBeenCalled();
    });

    expect(mockDestroy).not.toHaveBeenCalled();
  });
});
