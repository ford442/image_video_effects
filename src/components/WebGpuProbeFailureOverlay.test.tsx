import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
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

  it('has no Retry button for a boot-probe failure', () => {
    render(<WebGpuProbeFailureOverlay probe={fixture} />);
    expect(screen.queryByTestId('webgpu-retry')).toBeNull();
  });

  it('shows a busy device-lost card while recovering (no actions)', () => {
    render(<WebGpuProbeFailureOverlay probe={null} deviceLoss={{ state: 'recovering', reason: 'unknown', onRetry: jest.fn() }} />);
    const overlay = screen.getByTestId('webgpu-device-lost');
    expect(overlay).toHaveAttribute('data-recovery-state', 'recovering');
    expect(overlay).toHaveAttribute('aria-busy', 'true');
    expect(screen.getByText('GPU device lost')).toBeInTheDocument();
    expect(screen.getByText(/Restoring the renderer/)).toBeInTheDocument();
    expect(screen.queryByTestId('webgpu-retry')).toBeNull();
    expect(screen.queryByTestId('webgpu-probe-failure')).toBeNull();
  });

  it('offers Retry with the probe diagnostics after a failed recovery', () => {
    const onRetry = jest.fn();
    render(
      <WebGpuProbeFailureOverlay
        probe={fixture}
        deviceLoss={{ state: 'failed', reason: 'unknown', error: 'renderer init failed', onRetry }}
      />,
    );
    expect(screen.getByTestId('webgpu-device-lost')).toHaveAttribute('data-recovery-state', 'failed');
    expect(screen.getByText('renderer init failed')).toBeInTheDocument();
    expect(screen.getByText(/HighPerformance/)).toBeInTheDocument();
    fireEvent.click(screen.getByTestId('webgpu-retry'));
    expect(onRetry).toHaveBeenCalledTimes(1);
  });
});
