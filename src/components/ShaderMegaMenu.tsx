import React, { useState, useMemo, useRef, useEffect, useLayoutEffect } from 'react';
import ReactDOM from 'react-dom';
import './ShaderMegaMenu.css';

export interface ShaderMegaMenuOption {
  id: string;
  name: string;
  coordinate: number | null;
  category: string;
}

export interface ShaderMegaMenuProps {
  options: ShaderMegaMenuOption[];
  value: string;
  onChange: (id: string) => void;
  includeNone?: boolean;
  onClick?: (e: React.MouseEvent) => void;
}

const CATEGORY_ORDER = [
  'interactive-mouse',
  'artistic',
  'generative',
  'distortion',
  'image',
  'visual-effects',
  'retro-glitch',
  'liquid-effects',
  'simulation',
  'geometric',
  'lighting-effects',
];

const CATEGORY_LABELS: Record<string, string> = {
  'interactive-mouse': 'Interactive / Mouse',
  'artistic': 'Artistic',
  'generative': 'Generative',
  'distortion': 'Distortion & Warp',
  'image': 'Image Processing',
  'visual-effects': 'Visual Effects',
  'retro-glitch': 'Retro / Glitch',
  'liquid-effects': 'Liquid & Fluid',
  'simulation': 'Simulation',
  'geometric': 'Geometric',
  'lighting-effects': 'Lighting & Glow',
};

const NONE_ID = 'none';

export const ShaderMegaMenu: React.FC<ShaderMegaMenuProps> = ({
  options,
  value,
  onChange,
  includeNone = true,
  onClick,
}) => {
  const [isOpen, setIsOpen] = useState(false);
  const [search, setSearch] = useState('');
  const [focusedId, setFocusedId] = useState<string | null>(null);
  const [overlayPos, setOverlayPos] = useState({ top: 0, left: 0, width: 0 });

  const triggerRef = useRef<HTMLButtonElement>(null);
  const overlayRef = useRef<HTMLDivElement>(null);
  const searchInputRef = useRef<HTMLInputElement>(null);

  // Current selection display label
  const currentOption = options.find(o => o.id === value);
  const displayLabel = value === NONE_ID || !value
    ? 'None'
    : currentOption?.name ?? value;

  // Filter options by search
  const filteredOptions = useMemo(() => {
    if (!search) return options;
    const q = search.toLowerCase();
    return options.filter(o =>
      o.name.toLowerCase().includes(q) || o.id.toLowerCase().includes(q)
    );
  }, [options, search]);

  const isSearching = search.length > 0;

  // Group options by category (for non-search mode)
  const groups = useMemo(() => {
    const map = new Map<string, ShaderMegaMenuOption[]>();
    for (const opt of filteredOptions) {
      const cat = opt.category || 'other';
      if (!map.has(cat)) map.set(cat, []);
      map.get(cat)!.push(opt);
    }

    // Sort by CATEGORY_ORDER, then append unknown categories
    const ordered: Array<{ key: string; label: string; items: ShaderMegaMenuOption[] }> = [];
    for (const key of CATEGORY_ORDER) {
      if (map.has(key)) {
        ordered.push({ key, label: CATEGORY_LABELS[key] || key, items: map.get(key)! });
      }
    }
    for (const [key, items] of map.entries()) {
      if (!CATEGORY_ORDER.includes(key)) {
        ordered.push({ key, label: CATEGORY_LABELS[key] || key, items });
      }
    }
    return ordered;
  }, [filteredOptions]);

  // Flat item list for keyboard navigation (column-major order: all items in col0, then col1, etc.)
  const flatItems = useMemo(() => {
    const all: ShaderMegaMenuOption[] = [];
    if (includeNone) all.push({ id: NONE_ID, name: 'None', coordinate: null, category: '' });
    if (isSearching) {
      all.push(...filteredOptions);
    } else {
      for (const g of groups) all.push(...g.items);
    }
    return all;
  }, [groups, filteredOptions, isSearching, includeNone]);

  // Compute overlay position when opening
  useLayoutEffect(() => {
    if (!isOpen || !triggerRef.current) return;
    const rect = triggerRef.current.getBoundingClientRect();
    const overlayWidth = Math.min(window.innerWidth * 0.95, 1200);
    let left = rect.left;
    // Keep within viewport horizontally
    if (left + overlayWidth > window.innerWidth - 8) {
      left = window.innerWidth - overlayWidth - 8;
    }
    if (left < 8) left = 8;
    // Keep within viewport vertically
    let top = rect.bottom + 4;
    const spaceBelow = window.innerHeight - top - 8;
    if (spaceBelow < 300) {
      // Not enough room below — position above the trigger instead
      top = Math.max(8, rect.top - Math.min(window.innerHeight * 0.7, rect.top - 8));
    }
    setOverlayPos({ top, left, width: overlayWidth });
  }, [isOpen]);

  // Auto-focus search on open
  useEffect(() => {
    if (isOpen) {
      setTimeout(() => searchInputRef.current?.focus(), 10);
    } else {
      setSearch('');
      setFocusedId(null);
    }
  }, [isOpen]);

  // Click-outside to close
  useEffect(() => {
    if (!isOpen) return;
    const handler = (e: MouseEvent) => {
      if (
        !overlayRef.current?.contains(e.target as Node) &&
        !triggerRef.current?.contains(e.target as Node)
      ) {
        setIsOpen(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [isOpen]);

  // Scroll focused item into view
  useEffect(() => {
    if (!focusedId) return;
    const el = document.getElementById(`smm-item-${focusedId}`);
    el?.scrollIntoView({ block: 'nearest' });
  }, [focusedId]);

  const close = () => setIsOpen(false);

  const handleSelect = (id: string) => {
    onChange(id);
    close();
  };

  const handleTriggerClick = (e: React.MouseEvent) => {
    onClick?.(e);
    setIsOpen(o => !o);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (!isOpen) return;

    if (e.key === 'Escape') {
      e.preventDefault();
      close();
      return;
    }

    if (e.key === 'Enter' && focusedId) {
      e.preventDefault();
      handleSelect(focusedId);
      return;
    }

    if (e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
      e.preventDefault();
      const idx = focusedId ? flatItems.findIndex(i => i.id === focusedId) : -1;

      if (isSearching || e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        // Simple linear navigation in search mode or vertical arrows in column mode
        const next = e.key === 'ArrowDown'
          ? Math.min(idx + 1, flatItems.length - 1)
          : Math.max(idx - 1, 0);
        setFocusedId(flatItems[next]?.id ?? null);
        return;
      }

      if (!isSearching && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) {
        // Column-aware navigation: find which group and position within group
        if (idx < 0 || groups.length === 0) return;
        const noneOffset = includeNone ? 1 : 0;
        let cumulative = noneOffset;
        let groupIdx = -1;
        let posInGroup = 0;

        for (let g = 0; g < groups.length; g++) {
          if (idx < cumulative + groups[g].items.length) {
            groupIdx = g;
            posInGroup = idx - cumulative;
            break;
          }
          cumulative += groups[g].items.length;
        }

        if (groupIdx === -1) return;
        const targetGroup = e.key === 'ArrowRight'
          ? Math.min(groupIdx + 1, groups.length - 1)
          : Math.max(groupIdx - 1, 0);

        const targetItems = groups[targetGroup].items;
        const targetPos = Math.min(posInGroup, targetItems.length - 1);
        setFocusedId(targetItems[targetPos]?.id ?? null);
      }
    }
  };

  const overlay = isOpen ? (
    <div
      ref={overlayRef}
      className="smm-overlay"
      style={{ top: overlayPos.top, left: overlayPos.left, width: overlayPos.width, maxHeight: `calc(100vh - ${overlayPos.top}px - 8px)` }}
      onKeyDown={handleKeyDown}
    >
      {/* Search */}
      <div className="smm-search">
        <input
          ref={searchInputRef}
          type="text"
          placeholder="Search shaders..."
          value={search}
          onChange={e => setSearch(e.target.value)}
          onKeyDown={e => {
            if (e.key === 'Escape') { e.preventDefault(); close(); }
          }}
        />
      </div>

      {/* None option */}
      {includeNone && (
        <div className="smm-none-row">
          <div
            id={`smm-item-${NONE_ID}`}
            className={`smm-item smm-none-item${value === NONE_ID ? ' selected' : ''}${focusedId === NONE_ID ? ' focused' : ''}`}
            onMouseDown={() => handleSelect(NONE_ID)}
            onMouseEnter={() => setFocusedId(NONE_ID)}
          >
            None
          </div>
        </div>
      )}

      {/* Content */}
      {isSearching ? (
        <div className="smm-flat">
          {filteredOptions.length === 0 ? (
            <div className="smm-empty">No shaders match "{search}"</div>
          ) : (
            filteredOptions.map(opt => (
              <div
                key={opt.id}
                id={`smm-item-${opt.id}`}
                className={`smm-item${opt.id === value ? ' selected' : ''}${opt.id === focusedId ? ' focused' : ''}`}
                onMouseDown={() => handleSelect(opt.id)}
                onMouseEnter={() => setFocusedId(opt.id)}
              >
                <span className="smm-item-name">{opt.name}</span>
                {opt.coordinate !== null && (
                  <span className="smm-item-coord">#{opt.coordinate}</span>
                )}
              </div>
            ))
          )}
        </div>
      ) : (
        <div className="smm-columns">
          {groups.map(g => (
            <div key={g.key} className="smm-column">
              <div className="smm-col-header">
                {g.label}
                <span className="smm-col-count">({g.items.length})</span>
              </div>
              {g.items.map(opt => (
                <div
                  key={opt.id}
                  id={`smm-item-${opt.id}`}
                  className={`smm-item${opt.id === value ? ' selected' : ''}${opt.id === focusedId ? ' focused' : ''}`}
                  onMouseDown={() => handleSelect(opt.id)}
                  onMouseEnter={() => setFocusedId(opt.id)}
                  title={opt.coordinate !== null ? `#${opt.coordinate} — ${opt.name}` : opt.name}
                >
                  <span className="smm-item-name">{opt.name}</span>
                  {opt.coordinate !== null && (
                    <span className="smm-item-coord">#{opt.coordinate}</span>
                  )}
                </div>
              ))}
            </div>
          ))}
        </div>
      )}
    </div>
  ) : null;

  return (
    <div className="smm-wrapper">
      <button
        ref={triggerRef}
        className={`smm-trigger${isOpen ? ' open' : ''}`}
        onClick={handleTriggerClick}
        type="button"
      >
        <span className="smm-trigger-label" title={displayLabel}>{displayLabel}</span>
        <span className="smm-trigger-chevron">{isOpen ? '▲' : '▼'}</span>
      </button>
      {typeof document !== 'undefined' && ReactDOM.createPortal(overlay, document.body)}
    </div>
  );
};
