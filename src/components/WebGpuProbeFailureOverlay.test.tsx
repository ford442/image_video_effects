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

  it('tells the user what to do and offers a reload for a boot-probe failure', () => {
    render(<WebGpuProbeFailureOverlay probe={fixture} />);
    expect(screen.getByTestId('webgpu-help')).toHaveTextContent(/Chrome or Edge/);
    expect(screen.getByTestId('webgpu-reload')).toBeInTheDocument();
  });

  it('keeps the attempt log collapsed on phones so the recovery actions stay on screen', () => {
    const original = window.matchMedia;
    window.matchMedia = ((query: string) => ({ matches: query.includes('max-width: 640px'), media: query })) as typeof window.matchMedia;
    try {
      render(<WebGpuProbeFailureOverlay probe={fixture} />);
      expect(screen.getByTestId('webgpu-reload')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Show attempt log' })).toBeInTheDocument();
      expect(screen.queryByText(/HighPerformance/)).toBeNull();
    } finally {
      window.matchMedia = original;
    }
  });

  it('has no Retry button for a boot-probe failure', () => {
    render(<WebGpuProbeFailureOverlay probe={fixture} />);
    expect(screen.queryByTestId('webgpu-retry')).toBeNull();
  });

  it('shows a busy device-lost card while recovering (no actions)', () => {
    render(<WebGpuProbeFailureOverlay probe={null} deviceLoss={{ state: 'recovering', reason: 'unknown', onRetry: vi.fn() }} />);
    const overlay = screen.getByTestId('webgpu-device-lost');
    expect(overlay).toHaveAttribute('data-recovery-state', 'recovering');
    expect(overlay).toHaveAttribute('aria-busy', 'true');
    expect(screen.getByText('GPU device lost')).toBeInTheDocument();
    expect(screen.getByText(/Restoring the renderer/)).toBeInTheDocument();
    expect(screen.queryByTestId('webgpu-retry')).toBeNull();
    expect(screen.queryByTestId('webgpu-probe-failure')).toBeNull();
  });

  it('offers Retry with the probe diagnostics after a failed recovery', () => {
    const onRetry = vi.fn();
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
