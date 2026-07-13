import React, { useMemo, useState, useCallback, useEffect } from 'react';
import { SharedChain } from '../services/layerChainShare';
import { CatalogShader } from '../services/shaderCatalog';
import {
  generateChainVariations,
  breedVariations,
  VariationOptions,
  ChainVariation,
} from '../services/variationExplorer';
import {
  VariationFavorite,
  saveFavorite,
  loadFavorites,
  deleteFavorite,
} from '../services/variationFavorites';
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

function generateRandomSeed(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
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
  const [remixBaseChain, setRemixBaseChain] = useState<SharedChain>(baseChain);
  const [seed, setSeed] = useState<string>(options.seed ?? hashChain(baseChain));
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [variationsOverride, setVariationsOverride] = useState<ChainVariation[] | null>(null);
  const [favorites, setFavorites] = useState<VariationFavorite[]>(() => loadFavorites());

  const effectiveOptions = useMemo<VariationOptions>(
    () => ({
      paramJitter: options.paramJitter ?? true,
      shaderSwap: options.shaderSwap ?? 'sameCategory',
      seed,
    }),
    [options.paramJitter, options.shaderSwap, seed]
  );

  const generatedVariations = useMemo(() => {
    if (!catalog || catalog.length === 0) return [];
    return generateChainVariations(remixBaseChain, count, catalog, effectiveOptions);
  }, [remixBaseChain, catalog, count, effectiveOptions]);

  const displayVariations = variationsOverride ?? generatedVariations;

  const refreshFavorites = useCallback(() => {
    setFavorites(loadFavorites());
  }, []);

  useEffect(() => {
    refreshFavorites();
  }, [refreshFavorites]);

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
    setSeed(generateRandomSeed());
    setSelected(new Set());
    setVariationsOverride(null);
  }, []);

  const handleReseedFromChain = useCallback(() => {
    setRemixBaseChain(baseChain);
    setSeed(options.seed ?? hashChain(baseChain));
    setSelected(new Set());
    setVariationsOverride(null);
  }, [baseChain, options.seed]);

  const handleStar = useCallback(
    (variation: ChainVariation, index: number) => {
      saveFavorite({
        name: `Variation #${index + 1}`,
        chain: variation.chain,
        seed,
      });
      refreshFavorites();
    },
    [seed, refreshFavorites]
  );

  const handleBreed = useCallback(() => {
    if (selected.size !== 2) return;
    const [aIndex, bIndex] = Array.from(selected).sort((x, y) => x - y);
    const parentA = displayVariations[aIndex]?.chain;
    const parentB = displayVariations[bIndex]?.chain;
    if (!parentA || !parentB) return;

    const children = breedVariations(parentA, parentB, count, catalog, effectiveOptions);
    setVariationsOverride(children);
    setSelected(new Set());
  }, [selected, displayVariations, count, catalog, effectiveOptions]);

  const handleLoadFavorite = useCallback(
    (favorite: VariationFavorite) => {
      setRemixBaseChain(favorite.chain);
      setSeed(favorite.seed ?? hashChain(favorite.chain));
      setSelected(new Set());
      setVariationsOverride(null);
    },
    []
  );

  const handleDeleteFavorite = useCallback(
    (id: string) => {
      deleteFavorite(id);
      refreshFavorites();
    },
    [refreshFavorites]
  );

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
            marginBottom: '12px',
            flexWrap: 'wrap',
            alignItems: 'center',
          }}
        >
          <button className="gold-btn" onClick={handleShuffle} type="button" data-testid="shuffle-variations">
            🎲 Shuffle
          </button>
          <button
            className="gold-outline-btn"
            onClick={handleReseedFromChain}
            type="button"
            data-testid="reseed-from-chain"
          >
            ↺ Reseed from chain
          </button>
          {selected.size === 2 && (
            <button className="gold-btn" onClick={handleBreed} type="button" data-testid="breed-selected">
              🧬 Breed selected
            </button>
          )}
          <label
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '8px',
              color: '#a0a0b0',
              fontSize: '13px',
            }}
          >
            Seed:
            <input
              type="text"
              inputMode="numeric"
              value={seed}
              onChange={e => {
                setSeed(e.target.value);
                setVariationsOverride(null);
              }}
              data-testid="seed-input"
              style={{
                background: 'rgba(0,0,0,0.3)',
                border: '1px solid #555',
                borderRadius: '4px',
                color: '#FFD700',
                padding: '4px 8px',
                width: '120px',
              }}
            />
          </label>
          {selected.size > 0 && (
            <span style={{ color: '#a0a0b0', alignSelf: 'center' }}>
              A/B selected: {Array.from(selected).map(i => `#${i + 1}`).join(', ')}
            </span>
          )}
        </div>

        {favorites.length > 0 && (
          <div style={{ marginBottom: '16px' }} data-testid="favorites-strip">
            <div style={{ color: '#FFD700', fontSize: '13px', marginBottom: '8px' }}>⭐ Favorites</div>
            <div
              style={{
                display: 'flex',
                gap: '8px',
                overflowX: 'auto',
                paddingBottom: '4px',
              }}
            >
              {favorites.map(favorite => (
                <div
                  key={favorite.id}
                  className="glass-panel"
                  style={{
                    flex: '0 0 auto',
                    padding: '8px 12px',
                    borderRadius: '8px',
                    display: 'flex',
                    alignItems: 'center',
                    gap: '8px',
                  }}
                  data-testid={`favorite-item-${favorite.id}`}
                >
                  <span style={{ color: '#d0d0e0', fontSize: '12px', maxWidth: '140px' }}>
                    {favorite.name}
                    {favorite.seed && (
                      <span style={{ color: '#a0a0b0' }}> (s:{favorite.seed})</span>
                    )}
                  </span>
                  <button
                    className="gold-outline-btn"
                    style={{ fontSize: '11px', padding: '2px 8px' }}
                    onClick={() => handleLoadFavorite(favorite)}
                    type="button"
                    data-testid={`load-favorite-${favorite.id}`}
                  >
                    Load
                  </button>
                  <button
                    className="gold-outline-btn"
                    style={{ fontSize: '11px', padding: '2px 8px' }}
                    onClick={() => handleDeleteFavorite(favorite.id)}
                    type="button"
                    data-testid={`delete-favorite-${favorite.id}`}
                  >
                    ×
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        {displayVariations.length === 0 ? (
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
            {displayVariations.map((variation, index) => (
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
                    className="gold-outline-btn"
                    style={{ fontSize: '13px' }}
                    onClick={() => handleStar(variation, index)}
                    aria-label={`Star variation ${index + 1}`}
                    type="button"
                    data-testid={`star-variation-${index}`}
                  >
                    ☆
                  </button>
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
