// ═══════════════════════════════════════════════════════════════════════════════
//  StoragePanel.tsx — thin facade composing storage/panels/* (browse, detail, ratings, upload)

import React, { useState, useEffect } from 'react';
import { useStorage } from '../../hooks/useStorage';
import { ShaderItem, ImageItem, VideoItem, EffectConfigRecord, getStorageClient } from '../../services/storage';
import { STORAGE_VPS_HOST, STORAGE_VPS_PORT, STATIC_NGINX_URL } from '../../config/appConfig';
import { ConnectionStatus } from './StorageUIComponents';
import { StorageListBrowser, StorageTabType, SortField, SortDirection } from './panels/StorageListBrowser';
import { StorageDetailPanel, LibraryPreviewItem } from './panels/StorageDetailPanel';
import { useShaderRating } from './panels/StorageRatings';
import './StoragePanel.css';

interface StorageBrowserProps {
  onSelectShader?: (shader: ShaderItem) => void;
  onSelectImage?: (image: ImageItem) => void;
  onSelectVideo?: (video: VideoItem) => void;
  onLoadEffectConfig?: (config: EffectConfigRecord) => void;
  initialTab?: StorageTabType;
}

export const StoragePanel: React.FC<StorageBrowserProps> = ({
  onSelectShader,
  onSelectImage,
  onSelectVideo,
  onLoadEffectConfig: _onLoadEffectConfig,
  initialTab = 'shaders',
}) => {
  const storage = useStorage();
  const [activeTab, setActiveTab] = useState<StorageTabType>(initialTab);
  const [searchInput, setSearchInput] = useState('');
  const [searchQuery, setSearchQuery] = useState('');
  const [sortField, setSortField] = useState<SortField>('name');
  const [sortDirection, setSortDirection] = useState<SortDirection>('asc');
  const [selectedItem, setSelectedItem] = useState<string | null>(null);
  const [libraryItems, setLibraryItems] = useState<LibraryPreviewItem[]>([]);
  const [isLoadingLibrary, setIsLoadingLibrary] = useState(false);
  const [libraryTypeFilter, setLibraryTypeFilter] = useState<'all' | 'song' | 'sample' | 'shader'>('all');
  const [libraryError, setLibraryError] = useState<string | undefined>();
  const [previewItem, setPreviewItem] = useState<LibraryPreviewItem | null>(null);
  const [isPreviewOpen, setIsPreviewOpen] = useState(false);

  const handleShaderRate = useShaderRating(storage.rateShader, storage.refreshShaders);

  useEffect(() => {
    if (storage.isConnected) storage.refreshAll();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [storage.isConnected]);

  useEffect(() => {
    const timer = window.setTimeout(() => setSearchQuery(searchInput), 250);
    return () => window.clearTimeout(timer);
  }, [searchInput]);

  useEffect(() => {
    if (activeTab !== 'library') return;
    setIsLoadingLibrary(true);
    setLibraryError(undefined);
    getStorageClient()
      .listLibrary()
      .then((items) => setLibraryItems(items))
      .catch((error: unknown) => {
        setLibraryError(error instanceof Error ? error.message : 'Failed to load library');
      })
      .finally(() => setIsLoadingLibrary(false));
  }, [activeTab]);

  const toggleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDirection(prev => (prev === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortField(field);
      setSortDirection('asc');
    }
  };

  const openPreview = (item: LibraryPreviewItem) => {
    setPreviewItem(item);
    setIsPreviewOpen(true);
  };

  return (
    <div className="storage-browser">
      <div className="browser-header">
        <h2>◈ VPS Storage Manager</h2>
        <ConnectionStatus
          isConnected={storage.isConnected}
          isChecking={storage.isCheckingConnection}
          error={storage.connectionError}
          onRetry={storage.checkConnection}
        />
      </div>

      <div className="toast-container">
        {storage.toasts.map(toast => (
          <div key={toast.id} className={`toast ${toast.type}`}>
            <span className="toast-message">{toast.message}</span>
            <button className="toast-close" onClick={() => storage.dismissToast(toast.id)}>×</button>
          </div>
        ))}
      </div>

      <div className="browser-toolbar">
        <div className="tab-buttons">
          {([
            ['shaders', `Shaders (${storage.shaders.length})`],
            ['images', `Images (${storage.images.length})`],
            ['videos', `Videos (${storage.videos.length})`],
            ['library', `Library (${libraryItems.length})`],
            ['audio', `Audio (${storage.audio.length})`],
            ['operations', 'Operations'],
          ] as const).map(([tab, label]) => (
            <button
              key={tab}
              className={activeTab === tab ? 'active' : ''}
              onClick={() => setActiveTab(tab)}
            >
              {label}
              {tab === 'operations' && storage.activeOperations.length > 0 && (
                <span className="badge">{storage.activeOperations.length}</span>
              )}
            </button>
          ))}
        </div>

        <div className="search-box">
          <input
            type="text"
            placeholder={`Search ${activeTab}...`}
            value={searchInput}
            onChange={e => setSearchInput(e.target.value)}
          />
          {searchInput && (
            <button className="clear-search" onClick={() => setSearchInput('')}>×</button>
          )}
        </div>

        <button
          className="refresh-btn"
          onClick={storage.refreshAll}
          disabled={!storage.isConnected}
          title="Refresh all data"
        >
          ↻ Refresh
        </button>
      </div>

      <div className="browser-content">
        <StorageListBrowser
          activeTab={activeTab}
          searchQuery={searchQuery}
          sortField={sortField}
          sortDirection={sortDirection}
          selectedItem={selectedItem}
          onSelectItem={setSelectedItem}
          onToggleSort={toggleSort}
          onPreview={openPreview}
          onSelectShader={onSelectShader}
          onSelectImage={onSelectImage}
          onSelectVideo={onSelectVideo}
          onShaderRate={handleShaderRate}
          onUpload={storage.uploadFiles}
          isConnected={storage.isConnected}
          shaders={storage.shaders}
          images={storage.images}
          videos={storage.videos}
          audio={storage.audio}
          isLoadingShaders={storage.isLoadingShaders}
          isLoadingImages={storage.isLoadingImages}
          isLoadingVideos={storage.isLoadingVideos}
          libraryItems={libraryItems}
          isLoadingLibrary={isLoadingLibrary}
          libraryError={libraryError}
          libraryTypeFilter={libraryTypeFilter}
          onLibraryTypeFilter={setLibraryTypeFilter}
          onClearSearch={() => setSearchInput('')}
          operations={storage.operations}
          onClearCompleted={storage.clearCompleted}
        />
        <StorageDetailPanel
          isOpen={isPreviewOpen}
          item={previewItem}
          onClose={() => setIsPreviewOpen(false)}
        />
      </div>

      <div className="browser-footer">
        <span>VPS: {STORAGE_VPS_HOST}:{STORAGE_VPS_PORT}</span>
        <span>•</span>
        <span>Static: {STATIC_NGINX_URL}</span>
        {storage.lastError && <span className="error-text">Error: {storage.lastError}</span>}
      </div>
    </div>
  );
};

/** @deprecated Use StoragePanel */
export const StorageBrowser = StoragePanel;

export default StoragePanel;
