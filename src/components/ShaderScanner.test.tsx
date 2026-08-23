import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import ShaderScanner from './ShaderScanner';
import { ShaderEntry } from '../renderer/types';
import {
  clearAdoptedRendererDevice,
  registerAdoptedRendererDevice,
} from '../utils/adoptedGpuDevice';

jest.mock('../utils/fetchShaderWgsl', () => ({
  fetchShaderWgsl: jest.fn().mockResolvedValue('@compute @workgroup_size(16, 16) fn main() {}'),
}));

describe('ShaderScanner device policy', () => {
  const requestAdapter = jest.fn();
  const requestDevice = jest.fn();

  beforeEach(() => {
    clearAdoptedRendererDevice();
    window.webgpuProbe = {
      ok: true,
      finishedAt: new Date().toISOString(),
      userAgent: 'test',
      userAgentBrands: [],
      attempts: [],
    };

    const mockDevice = {
      createShaderModule: jest.fn().mockReturnValue({
        getCompilationInfo: jest.fn().mockResolvedValue({ messages: [] }),
      }),
      features: new Set(['subgroups']),
    } as unknown as GPUDevice;
    registerAdoptedRendererDevice(mockDevice, true);

    const nav = navigator as unknown as {
      gpu?: { requestAdapter: typeof requestAdapter; requestDevice: typeof requestDevice };
    };
    nav.gpu = { requestAdapter, requestDevice };
  });

  afterEach(() => {
    delete window.webgpuProbe;
    clearAdoptedRendererDevice();
  });

  it('never calls requestAdapter or requestDevice when adopted device exists', async () => {
    const shaders: ShaderEntry[] = [
      { id: 'test-shader', name: 'Test', url: 'shaders/test.wgsl', category: 'image' },
    ];

    render(<ShaderScanner shaders={shaders} isOpen onClose={() => {}} />);
    fireEvent.click(screen.getByRole('button', { name: /Start Scan/i }));

    await waitFor(() => {
      expect(screen.getByText(/Test/)).toBeInTheDocument();
    });

    expect(requestAdapter).not.toHaveBeenCalled();
    expect(requestDevice).not.toHaveBeenCalled();
  });
});
