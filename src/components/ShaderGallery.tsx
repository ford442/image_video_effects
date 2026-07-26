import React, { useState, useMemo, useEffect, useRef, useCallback } from 'react';
import { createPortal } from 'react-dom';
import { ShaderMegaMenuOption } from './ShaderMegaMenu';
import { ShaderStarRating } from './ShaderStarRating';
import { ShaderThumbPlaceholder } from './ShaderThumbPlaceholder';
import { useThumbnailManifest } from '../hooks/useThumbnailManifest';
import './ShaderGallery.css';

export interface ShaderGalleryProps {
  /** Flat list of shaders to browse (already filtered to the desired categories). */
  options: ShaderMegaMenuOption[];
  /** Currently selected shader id. */
  value?: string;
  /** Called with the chosen shader id. */
  onSelect: (id: string) => void;
  /** Called to close the gallery (e.g. backdrop click / Escape / explicit close button). */
  onClose: () => void;
}

/** Number of grid items rendered initially / per "load more" batch. */
const BATCH_SIZE = 60;

export const ShaderGallery: React.FC<ShaderGalleryProps> = ({ options, value, onSelect, onClose }) => {
  const { manifest, hasThumbnail } = useThumbnailManifest();
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('');
  const [previewOnly, setPreviewOnly] = useState(false);
  const [visibleCount, setVisibleCount] = useState(BATCH_SIZE);
  const sentinelRef = useRef<HTMLDivElement>(null);

  const categories = useMemo(() => {
    const set = new Set<string>();
    for (const o of options) set.add(o.category || 'other');
    return Array.from(set);
  }, [options]);

  const filtered = useMemo(() => {
    const q = search.toLowerCase();
    return options.filter(o => {
      if (category && (o.category || 'other') !== category) return false;
      if (previewOnly && !hasThumbnail(o.id)) return false;
      if (q && !o.name.toLowerCase().includes(q) && !o.id.toLowerCase().includes(q)) return false;
      return true;
    });
  }, [options, search, category, previewOnly, hasThumbnail]);

  // Reset pagination when filters change
  useEffect(() => {
    setVisibleCount(BATCH_SIZE);
  }, [search, category, previewOnly]);

  const visible = filtered.slice(0, visibleCount);
  const hasMore = visibleCount < filtered.length;

  // Infinite scroll: grow visibleCount when the sentinel enters view
  const loadMore = useCallback(() => {
    setVisibleCount(c => Math.min(c + BATCH_SIZE, filtered.length));
  }, [filtered.length]);

  useEffect(() => {
    if (!hasMore) return;
    const el = sentinelRef.current;
    if (!el) return;
    const observer = new IntersectionObserver(entries => {
      if (entries[0]?.isIntersecting) loadMore();
    }, { rootMargin: '400px' });
    observer.observe(el);
    return () => observer.disconnect();
  }, [hasMore, loadMore]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') onClose();
  };

  const countLabel = previewOnly
    ? `${filtered.length} shader${filtered.length === 1 ? '' : 's'} (preview only)`
    : `${filtered.length} shader${filtered.length === 1 ? '' : 's'}`;

  return createPortal(
    <div className="shader-gallery-backdrop" onClick={onClose}>
      <div className="shader-gallery-modal" onClick={e => e.stopPropagation()} onKeyDown={handleKeyDown}>
        <div className="shader-gallery-header">
          <h3>🖼️ Shader Gallery</h3>
          <button className="shader-gallery-close" onClick={onClose} aria-label="Close">×</button>
        </div>

        <div className="shader-gallery-filters">
          <input
            type="text"
            className="shader-gallery-search"
            placeholder="Search shaders..."
            value={search}
            onChange={e => setSearch(e.target.value)}
            autoFocus
          />
          <select
            className="shader-gallery-category"
            value={category}
            onChange={e => setCategory(e.target.value)}
          >
            <option value="">All Categories ({options.length})</option>
            {categories.map(c => (
              <option key={c} value={c}>{c}</option>
            ))}
          </select>
          <label className="shader-gallery-preview-toggle">
            <input
              type="checkbox"
              checked={previewOnly}
              onChange={e => setPreviewOnly(e.target.checked)}
            />
            Has preview
          </label>
          <span className="shader-gallery-count">{countLabel}</span>
        </div>

        <div className="shader-gallery-grid">
          {visible.length === 0 ? (
            <div className="shader-gallery-empty">No shaders match your search.</div>
          ) : (
            visible.map(opt => {
              const thumb = manifest[opt.id];
              return (
                <div
                  key={opt.id}
                  className={`shader-gallery-card${opt.id === value ? ' selected' : ''}`}
                  onClick={() => onSelect(opt.id)}
                  title={opt.name}
                >
                  <div className="shader-gallery-thumb-wrap">
                    {thumb ? (
                      <img
                        src={`./${thumb.thumbnail_url}`}
                        alt={opt.name}
                        className="shader-gallery-thumb"
                        loading="lazy"
                      />
                    ) : (
                      <ShaderThumbPlaceholder
                        name={opt.name}
                        category={opt.category}
                        className="shader-gallery-thumb-placeholder"
                        showName={false}
                      />
                    )}
                    {(opt.stars !== undefined && opt.stars > 0) && (
                      <div className="shader-gallery-stars-overlay">
                        <ShaderStarRating
                          shaderId={opt.id}
                          stars={opt.stars}
                          ratingCount={opt.ratingCount || 0}
                          onRate={async () => {}}
                          size="small"
                          readonly
                        />
                      </div>
                    )}
                  </div>
                  <div className="shader-gallery-name">{opt.name}</div>
                </div>
              );
            })
          )}
        </div>

        {hasMore && <div ref={sentinelRef} className="shader-gallery-sentinel" />}
      </div>
    </div>,
    document.body
  );
};

export default ShaderGallery;
