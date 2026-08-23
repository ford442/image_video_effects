import React, { useCallback, useState } from 'react';
import type { WebGpuProbeSerializable } from '../renderer/webgpuBootProbe';
import './WebGpuProbeFailureOverlay.css';

interface WebGpuProbeFailureOverlayProps {
  probe: WebGpuProbeSerializable;
}

export function WebGpuProbeFailureOverlay({ probe }: WebGpuProbeFailureOverlayProps) {
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
    probe.userAgentBrands.length > 0
      ? probe.userAgentBrands.map((b) => `${b.brand}/${b.version}`).join(', ')
      : 'unavailable';

  return (
    <div
      className="webgpu-probe-failure-overlay"
      role="alert"
      data-testid="webgpu-probe-failure"
    >
      <div className="webgpu-probe-failure-overlay__card">
        <h2 className="webgpu-probe-failure-overlay__title">WebGPU required</h2>
        <p className="webgpu-probe-failure-overlay__summary">
          Initialization failed — the renderer is blocked until a working WebGPU device is available.
        </p>
        {probe.lastError && (
          <p className="webgpu-probe-failure-overlay__error">{probe.lastError}</p>
        )}
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
        <div className="webgpu-probe-failure-overlay__actions">
          <button type="button" onClick={() => setShowLog((v) => !v)}>
            {showLog ? 'Hide attempt log' : 'Show attempt log'}
          </button>
          <button type="button" onClick={copyJson}>
            {copied ? 'Copied' : 'Copy probe JSON'}
          </button>
        </div>
        {showLog && (
          <pre className="webgpu-probe-failure-overlay__log">
            {JSON.stringify(probe.attempts, null, 2)}
          </pre>
        )}
      </div>
    </div>
  );
}
