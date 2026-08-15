import React from 'react';
import { render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { WebGpuProbeFailureOverlay } from './WebGpuProbeFailureOverlay';
import type { WebGpuProbeSerializable } from '../renderer/webgpuBootProbe';

const fixture: WebGpuProbeSerializable = {
  ok: false,
  finishedAt: '2026-08-15T00:00:00.000Z',
  userAgent: 'TestAgent/1.0',
  userAgentBrands: [{ brand: 'Chromium', version: '120' }],
  attempts: [
    {
      label: 'HighPerformance',
      powerPreference: 'high-performance',
      forceFallbackAdapter: false,
      adapterPresent: false,
      error: 'requestAdapter returned null',
      failedStage: 'requestAdapter',
    },
  ],
  failedStage: 'requestAdapter',
  lastError: 'Failed to obtain a WebGPU adapter after all fallback attempts',
  backend: 'webgpu',
};

describe('WebGpuProbeFailureOverlay', () => {
  it('mounts failure summary and attempt log', () => {
    render(<WebGpuProbeFailureOverlay probe={fixture} />);
    expect(screen.getByTestId('webgpu-probe-failure')).toBeInTheDocument();
    expect(screen.getByText('WebGPU required')).toBeInTheDocument();
    expect(
      screen.getByText(/Failed to obtain a WebGPU adapter after all fallback attempts/),
    ).toBeInTheDocument();
    expect(screen.getByText(/HighPerformance/)).toBeInTheDocument();
    expect(screen.getByText(/Chromium\/120/)).toBeInTheDocument();
  });
});
