import React from 'react';
import { RenderQualityMode } from '../../../config/performancePolicy';
import { formatLabel, InternalColorFormat } from '../../../config/formatPolicy';

export interface RenderQualityPanelProps {
  qualityMode: RenderQualityMode;
  onQualityChange: (mode: RenderQualityMode) => void;
  maxActiveSlots: number;
  internalResolution: number;
  scale: number;
  adaptive: boolean;
  targetFps: number;
  colorFormat?: InternalColorFormat;
  estimatedTextureMiB?: number;
  /** Format the tier asked for, before any FP32 pin. */
  requestedColorFormat?: InternalColorFormat;
  /** True when an FP32-required shader is holding storage at rgba32float. */
  fp32Pinned?: boolean;
  fp32PinnedBy?: string[];
  maxPassesPerFrame?: number;
}

const MODES: Array<{ id: RenderQualityMode; label: string; hint: string }> = [
  { id: 'battery', label: '🔋 Battery', hint: '0.5× · FP16 · 1 slot · 30 FPS' },
  { id: 'balanced', label: '⚖️ Balanced', hint: '0.75× · FP16 · 2 slots · 60 FPS' },
  { id: 'ultra', label: '✨ Ultra', hint: '1.0× · FP32 · 3 slots · full res' },
  { id: 'auto', label: '🎯 Auto', hint: 'Adapts scale to hold 30/60 FPS' },
];

export const RenderQualityPanel: React.FC<RenderQualityPanelProps> = ({
  qualityMode,
  onQualityChange,
  maxActiveSlots,
  internalResolution,
  scale,
  adaptive,
  targetFps,
  colorFormat = 'rgba32float',
  estimatedTextureMiB,
  requestedColorFormat,
  fp32Pinned = false,
  fp32PinnedBy = [],
  maxPassesPerFrame,
}) => (
  <div className="control-group glass-panel" style={{ padding: '12px' }}>
    <div className="gold-section-header" style={{ fontSize: '12px', marginTop: 0 }}>
      Render Quality
    </div>
    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '6px', marginTop: '8px' }}>
      {MODES.map((mode) => (
        <button
          key={mode.id}
          type="button"
          onClick={() => onQualityChange(mode.id)}
          title={mode.hint}
          style={{
            fontSize: '11px',
            padding: '8px 6px',
            borderRadius: '6px',
            cursor: 'pointer',
            border: `1px solid ${qualityMode === mode.id ? '#FFD700' : 'rgba(255,215,0,0.25)'}`,
            background: qualityMode === mode.id ? 'rgba(255,215,0,0.18)' : 'rgba(0,0,0,0.2)',
            color: qualityMode === mode.id ? '#FFD700' : '#c0c0d0',
          }}
        >
          {mode.label}
        </button>
      ))}
    </div>
    <div style={{ fontSize: '10px', color: '#9090a8', marginTop: '8px', lineHeight: 1.5 }}>
      Tier: {qualityMode}
      {' · '}
      Internal: {internalResolution}² ({Math.round(scale * 100)}%)
      {' · '}
      {formatLabel(colorFormat)} ({colorFormat})
      {estimatedTextureMiB !== undefined && ` · ~${estimatedTextureMiB} MiB tex`}
      {' · '}
      Slots: {maxActiveSlots}
      {maxPassesPerFrame !== undefined && ` · ≤${maxPassesPerFrame} passes/frame`}
      {adaptive && ` · Auto ${targetFps} FPS`}
    </div>
    {fp32Pinned && (
      <div
        style={{ fontSize: '10px', color: '#ffd166', marginTop: '4px', lineHeight: 1.4 }}
        title={
          `Tier requested ${requestedColorFormat ?? 'rgba16float'}; storage held at rgba32float by: `
          + (fp32PinnedBy.length ? fp32PinnedBy.join(', ') : 'an FP32-required shader')
        }
      >
        ⚠ FP32 pinned — precision-critical shader active
        {requestedColorFormat && requestedColorFormat !== colorFormat
          && ` (tier wanted ${formatLabel(requestedColorFormat)})`}
      </div>
    )}
  </div>
);

export default RenderQualityPanel;
