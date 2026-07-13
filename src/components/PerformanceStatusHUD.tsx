import React from 'react';
import type { RendererType } from '../../renderer/RendererManager';

export interface PerformanceStatusHUDProps {
  backend: RendererType;
  internalWidth: number;
  internalHeight: number;
  scale: number;
  fps: number;
  qualityLabel: string;
}

const BACKEND_LABELS: Record<RendererType, string> = {
  webgpu: 'WebGPU',
  wasm: 'WASM',
  js: 'Canvas2D',
};

export const PerformanceStatusHUD: React.FC<PerformanceStatusHUDProps> = ({
  backend,
  internalWidth,
  internalHeight,
  scale,
  fps,
  qualityLabel,
}) => (
  <span
    className="performance-status-hud"
    title={`Quality: ${qualityLabel} · Internal ${internalWidth}×${internalHeight} (${Math.round(scale * 100)}%)`}
    style={{
      marginLeft: '12px',
      fontSize: '11px',
      color: '#8ec8ff',
      fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
      whiteSpace: 'nowrap',
    }}
  >
    {internalWidth}² · {BACKEND_LABELS[backend]}
    {fps > 0 && ` · ${Math.round(fps)} FPS`}
  </span>
);

export default PerformanceStatusHUD;
