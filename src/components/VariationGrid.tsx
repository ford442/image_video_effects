import React, { useMemo, useState, useCallback } from 'react';
import { SharedChain } from '../services/layerChainShare';
import { CatalogShader } from '../services/shaderCatalog';
import {
  generateChainVariations,
  VariationOptions,
  ChainVariation,
} from '../services/variationExplorer';
import '../styles/gold-glass-theme.css';

export interface VariationGridProps {
  /** The chain to use as the remix starting point. */
  baseChain: SharedChain;
  /** Shader catalog used for param ranges and same-category swaps. */
  catalog: CatalogShader[];
  /** How many variations to generate (default 6). */
  count?: number;
  /** Variation strategy (defaults to param jitter + same-category shader swaps). */
  options?: Partial<VariationOptions>;
  /** Called when the user clicks "Adopt" on a variation. */
  onAdopt: (chain: SharedChain) => void;
  /** Called to close the explorer overlay. */
  onClose: () => void;
}

const DEFAULT_COUNT = 6;

function hashChain(chain: SharedChain): string {
  let h = 0;
  const str = JSON.stringify(chain);
  for (let i = 0; i < str.length; i++) {
    h = (h << 5) - h + str.charCodeAt(i);
    h |= 0;
  }
  return Math.abs(h).toString(36);
}

function formatParams(params: Record<string, number>): string {
  const entries = Object.entries(params);
  if (entries.length === 0) return 'defaults';
  return entries
    .slice(0, 4)
    .map(([k, v]) => `${k}: ${v.toFixed(2)}`)
    .join(', ');
}

function previewStyle(variation: ChainVariation): React.CSSProperties {
  // Build a quick static color swatch from the variation's param values so
  // each thumbnail has a visually distinct fingerprint without touching the
  // renderer.
  let r = 0.5;
  let g = 0.5;
  let b = 0.5;
  variation.summary.slots.forEach(slot => {
    const p = slot.params || {};
    const vals = [
      p.zoomParam1 ?? 0.5,
      p.zoomParam2 ?? 0.5,
      p.zoomParam3 ?? 0.5,
      p.zoomParam4 ?? 0.5,
    ];
    r = (r + vals[0]) / 2;
    g = (g + (vals[1] ?? vals[2])) / 2;
    b = (b + (vals[3] ?? vals[2])) / 2;
  });
  return {
    background: `linear-gradient(135deg, rgb(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)}), rgba(20,20,30,0.9))`,
  };
}

export const VariationGrid: React.FC<VariationGridProps> = ({
  baseChain,
  catalog,
  count = DEFAULT_COUNT,
  options = {},
  onAdopt,
  onClose,
}) => {
  const [seed, setSeed] = useState<string>(
    options.seed ?? hashChain(baseChain)
  );
  const [selected, setSelected] = useState<Set<number>>(new Set());

  const effectiveOptions = useMemo<VariationOptions>(
    () => ({
      paramJitter: options.paramJitter ?? true,
      shaderSwap: options.shaderSwap ?? 'sameCategory',
      seed,
    }),
    [options.paramJitter, options.shaderSwap, seed]
  );

  const variations = useMemo(() => {
    if (!catalog || catalog.length === 0) return [];
    return generateChainVariations(baseChain, count, catalog, effectiveOptions);
  }, [baseChain, catalog, count, effectiveOptions]);

  const toggleSelected = useCallback((index: number) => {
    setSelected(prev => {
      const next = new Set(prev);
      if (next.has(index)) {
        next.delete(index);
      } else {
        next.add(index);
      }
      return next;
    });
  }, []);

  const handleShuffle = useCallback(() => {
    setSeed(`${Date.now()}-${Math.random().toString(36).slice(2)}`);
    setSelected(new Set());
  }, []);

  return (
    <div
      className="variation-grid-overlay"
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(0,0,0,0.85)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 1000,
        padding: '20px',
      }}
      data-testid="variation-grid-overlay"
    >
      <div
        className="glass-panel variation-grid-panel"
        style={{
          width: 'min(1100px, 95vw)',
          maxHeight: '90vh',
          overflow: 'auto',
          padding: '24px',
          borderRadius: '12px',
        }}
      >
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            marginBottom: '16px',
          }}
        >
          <h2 style={{ margin: 0, color: '#FFD700', fontSize: '1.25rem' }}>
            🔀 Chain Remix Explorer
          </h2>
          <button
            className="gold-outline-btn"
            onClick={onClose}
            aria-label="Close remix explorer"
            type="button"
          >
            ✕
          </button>
        </div>

        <div
          style={{
            display: 'flex',
            gap: '12px',
            marginBottom: '16px',
            flexWrap: 'wrap',
          }}
        >
          <button className="gold-btn" onClick={handleShuffle} type="button">
            🎲 Shuffle Variations
          </button>
          {selected.size > 0 && (
            <span style={{ color: '#a0a0b0', alignSelf: 'center' }}>
              A/B selected: {Array.from(selected).map(i => `#${i + 1}`).join(', ')}
            </span>
          )}
        </div>

        {variations.length === 0 ? (
          <div style={{ color: '#a0a0b0' }}>No variations available.</div>
        ) : (
          <div
            className="variation-grid"
            style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fill, minmax(240px, 1fr))',
              gap: '16px',
            }}
          >
            {variations.map((variation, index) => (
              <div
                key={`${seed}-${index}`}
                className="variation-card glass-panel"
                data-testid={`variation-card-${index}`}
                style={{
                  borderRadius: '10px',
                  padding: '12px',
                  display: 'flex',
                  flexDirection: 'column',
                  gap: '10px',
                  border: selected.has(index)
                    ? '2px solid #FFD700'
                    : '2px solid transparent',
                }}
              >
                <div
                  className="variation-preview"
                  style={{
                    height: '96px',
                    borderRadius: '8px',
                    ...previewStyle(variation),
                  }}
                  data-testid={`variation-preview-${index}`}
                />

                <div style={{ flex: 1 }}>
                  <div
                    style={{
                      color: '#FFD700',
                      fontWeight: 600,
                      fontSize: '14px',
                      marginBottom: '6px',
                    }}
                  >
                    Variation #{index + 1}
                  </div>
                  {variation.summary.slots.map((slot, slotIndex) => (
                    <div
                      key={slotIndex}
                      style={{
                        color: '#d0d0e0',
                        fontSize: '12px',
                        marginBottom: '4px',
                      }}
                      data-testid={`variation-summary-${index}-slot-${slotIndex}`}
                    >
                      Slot {slotIndex + 1}:{' '}
                      <strong>{slot.shaderId ?? 'none'}</strong>
                      <br />
                      <span style={{ color: '#a0a0b0' }}>
                        {formatParams(slot.params as Record<string, number>)}
                      </span>
                    </div>
                  ))}
                </div>

                <div
                  style={{
                    display: 'flex',
                    gap: '8px',
                    alignItems: 'center',
                  }}
                >
                  <label
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: '6px',
                      color: '#a0a0b0',
                      fontSize: '13px',
                      cursor: 'pointer',
                      userSelect: 'none',
                    }}
                  >
                    <input
                      type="checkbox"
                      checked={selected.has(index)}
                      onChange={() => toggleSelected(index)}
                      aria-label={`Select variation ${index + 1} for A/B`}
                    />
                    A/B
                  </label>
                  <button
                    className="gold-btn"
                    style={{ flex: 1, fontSize: '13px' }}
                    onClick={() => onAdopt(variation.chain)}
                    data-testid={`adopt-variation-${index}`}
                    type="button"
                  >
                    Adopt
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default VariationGrid;
