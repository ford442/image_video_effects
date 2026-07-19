/**
 * CommunityGallery.tsx
 *
 * Live community preset-pack gallery. Fetches published shader chains from the
 * storage backend and restores them via the same SharedChain apply path used by
 * share-link hydration. Also publishes the current chain to the gallery.
 */

import React, { useEffect, useRef, useState, useCallback } from 'react';
import { SharedChain } from '../services/layerChainShare';
import {
  CommunityPack,
  publishPack,
  listCommunityPacks,
  recordPresetPackPlay,
  decodeChain,
} from '../services/communityGallery';

interface ThumbnailManifestEntry {
  thumbnail_url: string;
}

type ThumbnailManifest = Record<string, ThumbnailManifestEntry>;

function getPackThumbnailUrl(
  pack: CommunityPack,
  manifest: ThumbnailManifest
): string | undefined {
  const decoded = pack.chain ? decodeChain(pack.chain) : null;
  const firstShaderId = decoded?.slots.find(s => s.shaderId)?.shaderId;
  if (!firstShaderId) return undefined;
  const entry = manifest[firstShaderId];
  return entry?.thumbnail_url ? `./${entry.thumbnail_url}` : undefined;
}

export interface CommunityGalleryProps {
  open: boolean;
  onToggle: () => void;
  onApplySharedChain: (chain: SharedChain) => void;
  /** Returns the chain currently loaded in the app, or null if none is available. */
  getCurrentChain: () => SharedChain | null;
}

export const CommunityGallery: React.FC<CommunityGalleryProps> = ({
  open,
  onToggle,
  onApplySharedChain,
  getCurrentChain,
}) => {
  const [packs, setPacks] = useState<CommunityPack[]>([]);
  const [status, setStatus] = useState<'idle' | 'loading' | 'loaded' | 'error'>('idle');
  const [isPublishing, setIsPublishing] = useState(false);
  const [publishFormOpen, setPublishFormOpen] = useState(false);
  const [publishName, setPublishName] = useState('');
  const [publishDescription, setPublishDescription] = useState('');
  const [publishAuthor, setPublishAuthor] = useState('');
  const [publishStatus, setPublishStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle');
  const [publishError, setPublishError] = useState<string | null>(null);
  const [thumbnailManifest, setThumbnailManifest] = useState<ThumbnailManifest>({});
  const fetchStartedRef = useRef(false);
  const manifestLoadedRef = useRef(false);

  const loadPacks = useCallback(async () => {
    setStatus('loading');
    try {
      const data = await listCommunityPacks({ limit: 50, sortBy: 'play_count' });
      setPacks(data.packs);
      setStatus('loaded');
    } catch (err) {
      console.warn('[CommunityGallery] failed to load community packs:', err);
      setStatus('error');
    }
  }, []);

  useEffect(() => {
    if (!open || manifestLoadedRef.current) return;
    manifestLoadedRef.current = true;
    fetch('./thumbnails/manifest.json')
      .then(r => (r.ok ? r.json() : {}))
      .then(setThumbnailManifest)
      .catch(() => setThumbnailManifest({}));
  }, [open]);

  useEffect(() => {
    if (!open || fetchStartedRef.current) return;
    fetchStartedRef.current = true;
    loadPacks();
  }, [open, loadPacks]);

  const handleApply = useCallback(
    async (pack: CommunityPack) => {
      const chain = decodeChain(pack.chain);
      if (!chain) {
        console.warn('[CommunityGallery] failed to decode chain for pack', pack.id);
        return;
      }
      try {
        await recordPresetPackPlay(pack.id);
      } catch (err) {
        // Non-fatal: apply should still work even if play-count recording fails.
        console.warn('[CommunityGallery] failed to record play:', err);
      }
      onApplySharedChain(chain);
    },
    [onApplySharedChain]
  );

  const openPublishForm = useCallback(() => {
    const current = getCurrentChain();
    if (!current) {
      setPublishError('No chain is currently loaded to publish.');
      return;
    }
    setPublishFormOpen(true);
    setPublishError(null);
    setPublishStatus('idle');
    if (!publishName) setPublishName('My Preset Pack');
  }, [getCurrentChain, publishName]);

  const closePublishForm = useCallback(() => {
    setPublishFormOpen(false);
    setPublishError(null);
    setPublishStatus('idle');
  }, []);

  const handlePublish = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault();
      const current = getCurrentChain();
      if (!current) {
        setPublishError('No chain is currently loaded to publish.');
        return;
      }
      const name = publishName.trim();
      if (!name) {
        setPublishError('Name is required.');
        return;
      }

      setIsPublishing(true);
      setPublishStatus('loading');
      setPublishError(null);
      try {
        const result = await publishPack({
          name,
          description: publishDescription.trim(),
          author: publishAuthor.trim() || undefined,
          chain: current,
        });
        setPacks(prev => [result.pack, ...prev.filter(p => p.id !== result.pack.id)]);
        setPublishStatus('success');
        setPublishFormOpen(false);
        setPublishName('');
        setPublishDescription('');
        setPublishAuthor('');
        await loadPacks();
      } catch (err) {
        console.warn('[CommunityGallery] failed to publish pack:', err);
        setPublishStatus('error');
        setPublishError(err instanceof Error ? err.message : 'Publish failed.');
      } finally {
        setIsPublishing(false);
      }
    },
    [getCurrentChain, publishName, publishDescription, publishAuthor, loadPacks]
  );

  return (
    <div className="control-group glass-panel" style={{ padding: '12px', marginTop: '10px' }}>
      <div
        className="gold-section-header"
        style={{
          fontSize: '12px',
          marginTop: '0',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          cursor: 'pointer',
        }}
        onClick={onToggle}
      >
        <span>Community Gallery</span>
        <span
          style={{
            transform: open ? 'rotate(180deg)' : 'rotate(0deg)',
            transition: 'transform 0.2s',
          }}
        >
          ▼
        </span>
      </div>
      {open && (
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            gap: '8px',
            maxHeight: '360px',
            overflowY: 'auto',
            marginTop: '8px',
          }}
        >
          {!publishFormOpen && (
            <button
              className="gold-outline-btn"
              style={{ fontSize: '11px', padding: '4px 8px' }}
              onClick={openPublishForm}
              disabled={isPublishing}
            >
              Publish current chain
            </button>
          )}

          {publishError && !publishFormOpen && (
            <div style={{ fontSize: '11px', color: '#ff8080', textAlign: 'center' }}>
              {publishError}
            </div>
          )}

          {publishFormOpen && (
            <form
              onSubmit={handlePublish}
              style={{
                display: 'flex',
                flexDirection: 'column',
                gap: '6px',
                padding: '8px',
                background: 'rgba(20, 20, 30, 0.6)',
                border: '1px solid rgba(255, 215, 0, 0.2)',
                borderRadius: '6px',
              }}
            >
              <input
                type="text"
                placeholder="Pack name"
                value={publishName}
                onChange={e => setPublishName(e.target.value)}
                style={{ fontSize: '11px', padding: '4px 6px' }}
              />
              <input
                type="text"
                placeholder="Author (optional)"
                value={publishAuthor}
                onChange={e => setPublishAuthor(e.target.value)}
                style={{ fontSize: '11px', padding: '4px 6px' }}
              />
              <textarea
                placeholder="Description (optional)"
                value={publishDescription}
                onChange={e => setPublishDescription(e.target.value)}
                rows={2}
                style={{ fontSize: '11px', padding: '4px 6px', resize: 'none' }}
              />
              {publishError && (
                <div style={{ fontSize: '10px', color: '#ff8080' }}>{publishError}</div>
              )}
              <div style={{ display: 'flex', gap: '6px' }}>
                <button
                  type="submit"
                  className="gold-outline-btn"
                  style={{ fontSize: '11px', padding: '3px 8px', flex: 1 }}
                  disabled={isPublishing}
                >
                  {isPublishing ? 'Publishing…' : 'Publish'}
                </button>
                <button
                  type="button"
                  className="gold-outline-btn"
                  style={{ fontSize: '11px', padding: '3px 8px', flex: 1 }}
                  onClick={closePublishForm}
                  disabled={isPublishing}
                >
                  Cancel
                </button>
              </div>
            </form>
          )}

          {status === 'loading' && (
            <div
              style={{
                fontSize: '12px',
                color: '#a0a0b0',
                fontStyle: 'italic',
                textAlign: 'center',
              }}
            >
              Loading community packs…
            </div>
          )}
          {status === 'error' && (
            <div
              style={{
                fontSize: '12px',
                color: '#ff8080',
                fontStyle: 'italic',
                textAlign: 'center',
              }}
            >
              Couldn’t load community packs.
            </div>
          )}
          {status === 'loaded' && packs.length === 0 && !publishFormOpen && (
            <div
              style={{
                fontSize: '12px',
                color: '#a0a0b0',
                fontStyle: 'italic',
                textAlign: 'center',
              }}
            >
              No community packs yet — be the first!
            </div>
          )}

          {packs.map(pack => {
            const idDisplay = pack.chain
              ? decodeChain(pack.chain)?.slots
                  .filter(s => s.shaderId)
                  .map(s => s.shaderId)
                  .slice(0, 3)
                  .join(', ') ?? ''
              : '';
            const thumbUrl = getPackThumbnailUrl(pack, thumbnailManifest);
            return (
              <div
                key={pack.id}
                style={{
                  background: 'rgba(20, 20, 30, 0.6)',
                  border: '1px solid rgba(255, 215, 0, 0.1)',
                  borderRadius: '6px',
                  padding: '8px',
                }}
              >
                <div style={{ display: 'flex', gap: '8px' }}>
                  {thumbUrl && (
                    <img
                      src={thumbUrl}
                      alt=""
                      style={{
                        width: 56,
                        height: 56,
                        objectFit: 'cover',
                        borderRadius: '4px',
                        flexShrink: 0,
                        border: '1px solid rgba(255, 215, 0, 0.15)',
                      }}
                    />
                  )}
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div
                      style={{
                        fontSize: '12px',
                        color: '#FFD700',
                        fontWeight: 500,
                        marginBottom: '4px',
                      }}
                    >
                      {pack.name}
                    </div>
                    <div
                      style={{
                        fontSize: '10px',
                        color: 'rgba(255,255,255,0.45)',
                        marginBottom: '4px',
                      }}
                    >
                      {pack.author || 'Anonymous'}
                      {pack.date ? ` · ${pack.date}` : ''}
                      {pack.play_count > 0 ? ` · ▶ ${pack.play_count}` : ''}
                    </div>
                    <div
                      style={{
                        fontSize: '10px',
                        color: 'rgba(255,255,255,0.5)',
                        marginBottom: '6px',
                      }}
                    >
                      {pack.description}
                    </div>
                    <div
                      style={{
                        fontSize: '10px',
                        color: 'rgba(255,255,255,0.4)',
                        marginBottom: '6px',
                        fontStyle: 'italic',
                      }}
                    >
                      {idDisplay}
                    </div>
                  </div>
                </div>
                <button
                  className="gold-outline-btn"
                  style={{ fontSize: '11px', padding: '3px 8px', width: '100%', marginTop: '6px' }}
                  onClick={() => handleApply(pack)}
                >
                  Load Pack
                </button>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default CommunityGallery;
