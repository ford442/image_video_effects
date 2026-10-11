import React, { useCallback, useState } from 'react';
import type { WebGpuProbeSerializable } from '../renderer/webgpuBootProbe';
import './WebGpuProbeFailureOverlay.css';

/** A runtime GPUDevice loss being recovered (or that could not be recovered). */
export interface DeviceLossOverlayState {
  state: 'recovering' | 'failed';
  /** GPUDeviceLostInfo.reason ('unknown', 'simulated', …). */
  reason: string;
  /** Why the last recovery attempt failed. */
  error?: string | null;
  onRetry?: () => void;
}

interface WebGpuProbeFailureOverlayProps {
  /** Boot-probe diagnostics; null while a device loss is still being recovered. */
  probe: WebGpuProbeSerializable | null;
  deviceLoss?: DeviceLossOverlayState;
}

export function WebGpuProbeFailureOverlay({ probe, deviceLoss }: WebGpuProbeFailureOverlayProps) {
  const [showLog, setShowLog] = useState(true);
  const [copied, setCopied] = useState(false);

  const copyJson = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(JSON.stringify(probe, null, 2));
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      /* clipboard unavailable */
    }
  }, [probe]);

  const brands =
    probe && probe.userAgentBrands.length > 0
      ? probe.userAgentBrands.map((b) => `${b.brand}/${b.version}`).join(', ')
      : 'unavailable';

  const recovering = deviceLoss?.state === 'recovering';
  const title = deviceLoss ? 'GPU device lost' : 'WebGPU required';
  const summary = !deviceLoss
    ? 'Initialization failed — the renderer is blocked until a working WebGPU device is available.'
    : recovering
      ? `The GPU device was lost (${deviceLoss.reason}). Restoring the renderer…`
      : `The GPU device was lost (${deviceLoss.reason}) and the renderer could not be restored. ` +
        'Your shaders, parameters and image are kept — retry once the GPU is available again.';
  const error = deviceLoss ? deviceLoss.error ?? (recovering ? null : probe?.lastError) : probe?.lastError;

  return (
    <div
      className="webgpu-probe-failure-overlay"
      role="alert"
      aria-busy={recovering || undefined}
      data-testid={deviceLoss ? 'webgpu-device-lost' : 'webgpu-probe-failure'}
      data-recovery-state={deviceLoss?.state}
    >
      <div className="webgpu-probe-failure-overlay__card">
        <h2 className="webgpu-probe-failure-overlay__title">{title}</h2>
        <p className="webgpu-probe-failure-overlay__summary">{summary}</p>
        {error && <p className="webgpu-probe-failure-overlay__error">{error}</p>}
        {probe && !recovering && (
          <dl className="webgpu-probe-failure-overlay__meta">
            <dt>Failed stage</dt>
            <dd>{probe.failedStage ?? 'unknown'}</dd>
            <dt>User-Agent brands</dt>
            <dd>{brands}</dd>
            {probe.backend && (
              <>
                <dt>Backend</dt>
                <dd>{probe.backend}</dd>
              </>
            )}
          </dl>
        )}
        {!recovering && (deviceLoss?.onRetry || probe) && (
          <div className="webgpu-probe-failure-overlay__actions">
            {deviceLoss?.onRetry && (
              <button type="button" data-testid="webgpu-retry" onClick={deviceLoss.onRetry}>
                Retry
              </button>
            )}
            {probe && (
              <>
                <button type="button" onClick={() => setShowLog((v) => !v)}>
                  {showLog ? 'Hide attempt log' : 'Show attempt log'}
                </button>
                <button type="button" onClick={copyJson}>
                  {copied ? 'Copied' : 'Copy probe JSON'}
                </button>
              </>
            )}
          </div>
        )}
        {probe && !recovering && showLog && (
          <pre className="webgpu-probe-failure-overlay__log">
            {JSON.stringify(probe.attempts, null, 2)}
          </pre>
        )}
      </div>
    </div>
  );
}
