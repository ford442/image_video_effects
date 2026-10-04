import React from 'react';
import type { PassKind, PassTiming } from '../../../renderer/passTimings';

/**
 * Per-pass GPU time as one stacked bar (#1314 WP-4): every graph node, slot
 * step and fixed pass (video copy, input scale, chores, present) is a segment
 * sized by its smoothed GPU milliseconds, with the heaviest passes listed.
 */
export interface PassFlameStripProps {
  passes: PassTiming[];
  /** Where the numbers come from; wall-clock means no per-pass data. */
  source?: 'gpu-timestamp' | 'wall-clock';
  /** Rows in the "heaviest passes" list. */
  topN?: number;
}

const KIND_COLORS: Record<Exclude<PassKind, 'compute'>, string> = {
  present: '#6b7280',
  video: '#14b8a6',
  input: '#3b82f6',
  chores: '#a855f7',
};

const SLOT_COLORS = ['#f59e0b', '#ef4444', '#22c55e', '#ec4899', '#eab308', '#f97316'];

export function passColor(pass: Pick<PassTiming, 'kind' | 'slot'>): string {
  if (pass.kind !== 'compute') return KIND_COLORS[pass.kind];
  return SLOT_COLORS[(pass.slot ?? 0) % SLOT_COLORS.length];
}

function describe(pass: PassTiming): string {
  const where = pass.slot !== undefined ? `slot ${pass.slot + 1} · ` : '';
  const iterations = pass.iterations > 1 ? ` ×${pass.iterations}` : '';
  const scale = pass.scale < 1 ? ` @${Math.round(pass.scale * 100)}%` : '';
  return `${where}${pass.label}${iterations}${scale}`;
}

export const PassFlameStrip: React.FC<PassFlameStripProps> = ({ passes, source, topN = 5 }) => {
  const total = passes.reduce((sum, p) => sum + p.gpuMs, 0);
  if (passes.length === 0 || total <= 0) {
    return (
      <div data-testid="pass-flame-strip" style={{ marginTop: '6px', opacity: 0.8 }}>
        per-pass GPU: {source === 'gpu-timestamp' ? 'waiting for timestamps' : 'unavailable (no timestamp-query)'}
      </div>
    );
  }

  const heaviest = [...passes].sort((a, b) => b.gpuMs - a.gpuMs).slice(0, topN);
  return (
    <div data-testid="pass-flame-strip" style={{ marginTop: '6px' }}>
      <div style={{ color: '#FFD700' }}>
        Per-pass GPU · {total.toFixed(2)} ms
      </div>
      <div
        role="img"
        aria-label={`GPU time per pass, ${total.toFixed(2)} ms total`}
        style={{ display: 'flex', height: '10px', width: '100%', margin: '4px 0', borderRadius: '2px', overflow: 'hidden' }}
      >
        {passes.map((p) => (
          <div
            key={p.key}
            data-testid="pass-flame-segment"
            title={`${describe(p)}: ${p.gpuMs.toFixed(3)} ms`}
            style={{
              flexGrow: p.gpuMs,
              flexBasis: 0,
              minWidth: p.gpuMs > 0 ? '1px' : 0,
              background: passColor(p),
            }}
          />
        ))}
      </div>
      {heaviest.map((p) => (
        <div key={p.key} style={{ display: 'flex', gap: '6px', alignItems: 'center' }}>
          <span style={{ width: '8px', height: '8px', background: passColor(p), display: 'inline-block' }} />
          <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {describe(p)}
          </span>
          <span>{p.gpuMs.toFixed(2)} ms · {Math.round((p.gpuMs / total) * 100)}%</span>
        </div>
      ))}
    </div>
  );
};

export default PassFlameStrip;
