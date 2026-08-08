import React, { useMemo } from 'react';
import { ShaderItem, ImageItem, VideoItem } from '../../../services/storage';
import { GoldSpinner, ShaderCard, ImageCard, VideoCard } from '../StorageUIComponents';
import { StorageUploadPanel } from './StorageUploadPanel';
import { OperationsPanel } from './OperationsPanel';
import { LibraryPreviewItem } from './StorageDetailPanel';

export type StorageTabType = 'shaders' | 'images' | 'videos' | 'audio' | 'library' | 'operations';
export type SortField = 'name' | 'date' | 'rating' | 'tags';
export type SortDirection = 'asc' | 'desc';

export interface StorageListBrowserProps {
  activeTab: StorageTabType;
  searchQuery: string;
  sortField: SortField;
  sortDirection: SortDirection;
  selectedItem: string | null;
  onSelectItem: (id: string) => void;
  onToggleSort: (field: SortField) => void;
  onPreview: (item: LibraryPreviewItem) => void;
  onSelectShader?: (shader: ShaderItem) => void;
  onSelectImage?: (image: ImageItem) => void;
  onSelectVideo?: (video: VideoItem) => void;
  onShaderRate: (shaderId: string, rating: number) => Promise<void>;
  onUpload: (
    files: File[],
    type: 'image' | 'video' | 'audio' | 'shader',
    onProgress?: (completed: number, total: number) => void,
  ) => Promise<import('../../../services/storage').StorageSaveResponse[]>;
  isConnected: boolean;
  shaders: ShaderItem[];
  images: ImageItem[];
  videos: VideoItem[];
  audio: VideoItem[];
  isLoadingShaders: boolean;
  isLoadingImages: boolean;
  isLoadingVideos: boolean;
  libraryItems: LibraryPreviewItem[];
  isLoadingLibrary: boolean;
  libraryError?: string;
  libraryTypeFilter: 'all' | 'song' | 'sample' | 'shader';
  onLibraryTypeFilter: (type: 'all' | 'song' | 'sample' | 'shader') => void;
  onClearSearch: () => void;
  operations: Array<{
    id: string;
    type: string;
    status: string;
    itemName?: string;
    message?: string;
    timestamp: number;
  }>;
  onClearCompleted: () => void;
}

const LibraryCard: React.FC<{ item: LibraryPreviewItem; onPreview: () => void }> = ({
  item,
  onPreview,
}) => (
  <div className="library-card">
    <div className="library-thumb-wrap">
      {item.thumbnail_url ? (
        <img src={item.thumbnail_url} alt={item.name} className="library-thumb" />
      ) : (
        <div className="library-thumb-fallback">{item.type.toUpperCase()}</div>
      )}
    </div>
    <div className="library-content">
      <div className="library-title-row">
        <h3>{item.name}</h3>
        <span className="library-type-chip">{item.type}</span>
      </div>
      <p className="library-description">{item.description || 'No description available.'}</p>
      <div className="library-meta-row">
        {item.author && <span>{item.author}</span>}
        {item.updated_at && <span>{new Date(item.updated_at).toLocaleDateString()}</span>}
      </div>
      <div className="library-tags">
        {(item.tags || []).slice(0, 5).map(tag => (
          <span key={tag} className="tag">{tag}</span>
        ))}
      </div>
    </div>
    <button className="preview-btn" onClick={onPreview}>Preview</button>
  </div>
);

export const StorageListBrowser: React.FC<StorageListBrowserProps> = (props) => {
  const {
    activeTab,
    searchQuery,
    sortField,
    sortDirection,
    selectedItem,
    onSelectItem,
    onToggleSort,
    onPreview,
    onSelectShader,
    onSelectImage,
    onSelectVideo,
    onShaderRate,
    onUpload,
    isConnected,
    shaders,
    images,
    videos,
    audio,
    isLoadingShaders,
    isLoadingImages,
    isLoadingVideos,
    libraryItems,
    isLoadingLibrary,
    libraryError,
    libraryTypeFilter,
    onLibraryTypeFilter,
    onClearSearch,
    operations,
    onClearCompleted,
  } = props;

  const filteredShaders = useMemo(() => {
    let result = [...shaders];
    if (searchQuery) {
      const q = searchQuery.toLowerCase();
      result = result.filter(s =>
        s.name.toLowerCase().includes(q) ||
        s.description.toLowerCase().includes(q) ||
        s.tags.some(t => t.toLowerCase().includes(q)),
      );
    }
    result.sort((a, b) => {
      let comparison = 0;
      switch (sortField) {
        case 'name': comparison = a.name.localeCompare(b.name); break;
        case 'date': comparison = new Date(a.date || 0).getTime() - new Date(b.date || 0).getTime(); break;
        case 'rating': comparison = (a.rating || 0) - (b.rating || 0); break;
        case 'tags': comparison = a.tags.length - b.tags.length; break;
      }
      return sortDirection === 'asc' ? comparison : -comparison;
    });
    return result;
  }, [shaders, searchQuery, sortField, sortDirection]);

  const filteredImages = useMemo(() => {
    if (!searchQuery) return images;
    const q = searchQuery.toLowerCase();
    return images.filter(img =>
      (img.description || '').toLowerCase().includes(q) ||
      img.tags.some(t => t.toLowerCase().includes(q)),
    );
  }, [images, searchQuery]);

  const filteredVideos = useMemo(() => {
    if (!searchQuery) return videos;
    const q = searchQuery.toLowerCase();
    return videos.filter(v =>
      v.title.toLowerCase().includes(q) || v.artist.toLowerCase().includes(q),
    );
  }, [videos, searchQuery]);

  const filteredAudio = useMemo(() => {
    if (!searchQuery) return audio;
    const q = searchQuery.toLowerCase();
    return audio.filter(a =>
      a.title.toLowerCase().includes(q) || a.artist.toLowerCase().includes(q),
    );
  }, [audio, searchQuery]);

  const libraryTypes = useMemo(() => {
    return libraryItems.reduce((acc, item) => {
      acc[item.type] = (acc[item.type] || 0) + 1;
      return acc;
    }, {} as Record<string, number>);
  }, [libraryItems]);

  const filteredLibrary = useMemo(() => {
    return libraryItems.filter(item => {
      const matchesType = libraryTypeFilter === 'all' || item.type === libraryTypeFilter;
      const normalizedSearch = searchQuery.trim().toLowerCase();
      const matchesSearch = normalizedSearch.length === 0 || [item.name, item.description, item.author, item.filename]
        .filter(Boolean)
        .some(value => value?.toLowerCase().includes(normalizedSearch));
      return matchesType && matchesSearch;
    });
  }, [libraryItems, libraryTypeFilter, searchQuery]);

  switch (activeTab) {
    case 'library':
      return (
        <div className="library-panel">
          <div className="library-header">
            <div className="library-filters">
              <div className="filter-badges">
                {(['all', 'song', 'sample', 'shader'] as const).map(type => (
                  <button
                    key={type}
                    className={`filter-chip ${libraryTypeFilter === type ? 'active' : ''}`}
                    onClick={() => onLibraryTypeFilter(type)}
                  >
                    {type === 'all' ? 'All' : type.charAt(0).toUpperCase() + type.slice(1)}
                    {type !== 'all' && libraryTypes[type] ? ` (${libraryTypes[type]})` : ''}
                  </button>
                ))}
              </div>
              <div className="library-summary">
                {isLoadingLibrary ? <span>Loading library…</span> : <span>{filteredLibrary.length} items matched</span>}
              </div>
            </div>
            <div className="library-actions">
              <button onClick={onClearSearch} className="secondary-btn">Clear Search</button>
            </div>
          </div>
          {libraryError && <div className="error-text">{libraryError}</div>}
          {isLoadingLibrary ? (
            <div className="cards-grid library">
              {Array.from({ length: 8 }, (_, index) => (
                <div key={index} className="library-card skeleton">
                  <div className="card-thumb skeleton-box" />
                  <div className="card-body">
                    <div className="skeleton-line short" />
                    <div className="skeleton-line" />
                    <div className="skeleton-tags" />
                  </div>
                </div>
              ))}
            </div>
          ) : filteredLibrary.length === 0 ? (
            <div className="empty-state">No library items found</div>
          ) : (
            <div className="cards-grid library">
              {filteredLibrary.map(item => (
                <LibraryCard key={item.id} item={item} onPreview={() => onPreview(item)} />
              ))}
            </div>
          )}
        </div>
      );

    case 'shaders':
      return (
        <div className="tab-content">
          <div className="content-header">
            <span className="item-count">{filteredShaders.length} shaders</span>
            <div className="sort-controls">
              <span>Sort by:</span>
              {(['name', 'rating', 'date'] as const).map(field => (
                <button
                  key={field}
                  className={sortField === field ? 'active' : ''}
                  onClick={() => onToggleSort(field)}
                >
                  {field.charAt(0).toUpperCase() + field.slice(1)}{' '}
                  {sortField === field && (sortDirection === 'asc' ? '▲' : '▼')}
                </button>
              ))}
            </div>
          </div>
          <StorageUploadPanel type="shader" onUpload={onUpload} disabled={!isConnected} />
          {isLoadingShaders ? (
            <div className="loading-state"><GoldSpinner size="medium" /><span>Loading shaders...</span></div>
          ) : filteredShaders.length === 0 ? (
            <div className="empty-state">
              <div className="empty-state-icon">⚆</div>
              <span>{searchQuery ? 'No shaders match your search' : 'No shaders available'}</span>
            </div>
          ) : (
            <div className="cards-grid">
              {filteredShaders.map(shader => (
                <ShaderCard
                  key={shader.id}
                  shader={shader}
                  isSelected={selectedItem === shader.id}
                  onSelect={() => { onSelectItem(shader.id); onSelectShader?.(shader); }}
                  onRate={(rating) => onShaderRate(shader.id, rating)}
                  onPreview={() => onPreview({
                    id: shader.id,
                    name: shader.name,
                    type: 'shader',
                    description: shader.description,
                    author: shader.author,
                    filename: shader.filename,
                    tags: shader.tags,
                    thumbnail_url: shader.thumbnail_url,
                  })}
                />
              ))}
            </div>
          )}
        </div>
      );

    case 'images':
      return (
        <div className="tab-content">
          <div className="content-header"><span className="item-count">{filteredImages.length} images</span></div>
          <StorageUploadPanel type="image" onUpload={onUpload} disabled={!isConnected} />
          {isLoadingImages ? (
            <div className="loading-state"><GoldSpinner size="medium" /><span>Loading images...</span></div>
          ) : filteredImages.length === 0 ? (
            <div className="empty-state">
              <div className="empty-state-icon">⚆</div>
              <span>{searchQuery ? 'No images match your search' : 'No images available'}</span>
            </div>
          ) : (
            <div className="cards-grid images">
              {filteredImages.map((image, i) => (
                <ImageCard
                  key={i}
                  image={image}
                  isSelected={selectedItem === `img-${i}`}
                  onSelect={() => { onSelectItem(`img-${i}`); onSelectImage?.(image); }}
                />
              ))}
            </div>
          )}
        </div>
      );

    case 'videos':
      return (
        <div className="tab-content">
          <div className="content-header"><span className="item-count">{filteredVideos.length} videos</span></div>
          <StorageUploadPanel type="video" onUpload={onUpload} disabled={!isConnected} />
          {isLoadingVideos ? (
            <div className="loading-state"><GoldSpinner size="medium" /><span>Loading videos...</span></div>
          ) : filteredVideos.length === 0 ? (
            <div className="empty-state">
              <div className="empty-state-icon">⚆</div>
              <span>{searchQuery ? 'No videos match your search' : 'No videos available'}</span>
            </div>
          ) : (
            <div className="cards-grid">
              {filteredVideos.map(video => (
                <VideoCard
                  key={video.id}
                  video={video}
                  isSelected={selectedItem === video.id}
                  onSelect={() => { onSelectItem(video.id); onSelectVideo?.(video); }}
                />
              ))}
            </div>
          )}
        </div>
      );

    case 'audio':
      return (
        <div className="tab-content">
          <div className="content-header"><span className="item-count">{filteredAudio.length} audio files</span></div>
          <StorageUploadPanel type="audio" onUpload={onUpload} disabled={!isConnected} />
          {isLoadingVideos ? (
            <div className="loading-state"><GoldSpinner size="medium" /><span>Loading audio...</span></div>
          ) : filteredAudio.length === 0 ? (
            <div className="empty-state">
              <div className="empty-state-icon">⚆</div>
              <span>{searchQuery ? 'No audio files match your search' : 'No audio files available'}</span>
            </div>
          ) : (
            <div className="cards-grid">
              {filteredAudio.map(track => (
                <VideoCard
                  key={track.id}
                  video={track}
                  isSelected={selectedItem === track.id}
                  onSelect={() => { onSelectItem(track.id); onSelectVideo?.(track); }}
                />
              ))}
            </div>
          )}
        </div>
      );

    case 'operations':
      return <OperationsPanel operations={operations} onClearCompleted={onClearCompleted} />;

    default:
      return null;
  }
};
