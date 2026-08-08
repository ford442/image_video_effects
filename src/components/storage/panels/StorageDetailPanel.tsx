import React from 'react';

export interface LibraryPreviewItem {
  id: string;
  name: string;
  type: string;
  description?: string;
  author?: string;
  filename?: string;
  tags?: string[];
  updated_at?: string;
  thumbnail_url?: string;
}

interface StorageDetailPanelProps {
  isOpen: boolean;
  item: LibraryPreviewItem | null;
  onClose: () => void;
}

/** Preview modal for library/shader cards — no direct network calls. */
export const StorageDetailPanel: React.FC<StorageDetailPanelProps> = ({
  isOpen,
  item,
  onClose,
}) => {
  if (!isOpen || !item) return null;

  return (
    <div className="preview-modal-backdrop" onClick={onClose}>
      <div className="preview-modal" onClick={e => e.stopPropagation()}>
        <button className="close-modal" onClick={onClose}>×</button>
        <div className="preview-grid">
          <div className="preview-panel preview-thumbnail">
            <h3>{item.name}</h3>
            {item.thumbnail_url ? (
              <img src={item.thumbnail_url} alt={item.name} />
            ) : (
              <div className="thumbnail-fallback">No thumbnail available</div>
            )}
            <div className="preview-meta">
              <span>{item.type}</span>
              {item.author && <span>{item.author}</span>}
              {item.updated_at && <span>{new Date(item.updated_at).toLocaleDateString()}</span>}
            </div>
          </div>
          <div className="preview-panel preview-webgpu">
            <h3>Live WebGPU preview</h3>
            <div className="webgpu-preview-placeholder">
              <div className="preview-live-label">Live WebGPU renderer</div>
              <div className="preview-placeholder-canvas" />
            </div>
            <p className="preview-copy">
              This preview is connected to the storage browser and can be used with the live canvas.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};
