import React from 'react';
import { RenderQualityMode } from '../../config/performancePolicy';

export interface RenderQualityPanelProps {
  qualityMode: RenderQualityMode;
  onQualityChange: (mode: RenderQualityMode) => void;
  maxActiveSlots: number;
  internalResolution: number;
  scale: number;
  adaptive: boolean;
  targetFps: number;
}

const MODES: Array<{ id: RenderQualityMode; label: string; hint: string }> = [
  { id: 'battery', label: '🔋 Battery', hint: '0.5× · 1 slot · 30 FPS target' },
  { id: 'balanced', label: '⚖️ Balanced', hint: '0.75× · 2 slots · 60 FPS' },
  { id: 'ultra', label: '✨ Ultra', hint: '1.0× · 3 slots · full res' },
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
      Internal: {internalResolution}² ({Math.round(scale * 100)}%)
      {' · '}
      Slots: {maxActiveSlots}
      {adaptive && ` · Auto ${targetFps} FPS`}
    </div>
  </div>
);

export default RenderQualityPanel;
