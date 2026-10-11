import React, { RefObject, Suspense, lazy, useState } from 'react';
import type { RendererManager } from '../../renderer/RendererManager';
import type { ShaderEntry } from '../../renderer/types';

// The workspace is a separate chunk: only this button (and the flag check in the caller) ships in main.js.
const GraphLabPanel = lazy(() => import(/* webpackChunkName: "graph-lab" */ './GraphLabPanel'));

export interface GraphLabLauncherProps {
  rendererRef: RefObject<RendererManager | null>;
  availableModes: ShaderEntry[];
  activeSlot: number;
  setStatus?: (status: string) => void;
}

// Inline on purpose: this button lives in main.js, the stylesheet ships with the lazy chunk.
const FAB_STYLE: React.CSSProperties = {
  position: 'fixed',
  left: 16,
  bottom: 16,
  zIndex: 60,
  padding: '8px 14px',
  borderRadius: 999,
  border: '1px solid rgba(255, 215, 0, 0.3)',
  background: 'rgba(20, 20, 25, 0.85)',
  color: '#ffd700',
  font: 'inherit',
  fontSize: 13,
  cursor: 'pointer',
};

/** Mounted only when `?graphlab` (or the remembered flag) is on. */
export function GraphLabLauncher({ rendererRef, availableModes, activeSlot, setStatus }: GraphLabLauncherProps) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button
        type="button"
        style={FAB_STYLE}
        aria-expanded={open}
        data-testid="graph-lab-toggle"
        onClick={() => setOpen((v) => !v)}
      >
        Graph Lab
      </button>
      {open && (
        <Suspense fallback={<div style={{ ...FAB_STYLE, left: 130 }}>Loading Graph Lab…</div>}>
          <GraphLabPanel
            rendererRef={rendererRef}
            availableModes={availableModes}
            activeSlot={activeSlot}
            setStatus={setStatus}
            onClose={() => setOpen(false)}
          />
        </Suspense>
      )}
    </>
  );
}
