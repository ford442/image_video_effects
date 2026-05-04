// ═══════════════════════════════════════════════════════════════════════════════
//  StorageBrowser.tsx
//  Visual readout page for the VPS Storage API
//  Browse shaders, images, videos with ratings and management features
//  GOLD AND DARK GLASS THEME
// ═══════════════════════════════════════════════════════════════════════════════

import React, { useState, useEffect, useMemo } from 'react';
import { useStorage } from '../hooks/useStorage';
import { ShaderItem, ImageItem, VideoItem } from '../services/StorageService';
import { STORAGE_VPS_HOST, STORAGE_VPS_PORT, STORAGE_API_URL, STATIC_NGINX_URL } from '../config/appConfig';
import { DragDropUpload } from './DragDropUpload';
import './StorageBrowser.css';

// ═══════════════════════════════════════════════════════════════════════════════
//  Types
// ═══════════════════════════════════════════════════════════════════════════════

type TabType = 'shaders' | 'images' | 'videos' | 'audio' | 'library' | 'operations';
type SortField = 'name' | 'date' | 'rating' | 'tags';
type SortDirection = 'asc' | 'desc';

interface LibraryItem {
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

interface StorageBrowserProps {
  onSelectShader?: (shader: ShaderItem) => void;
  onSelectImage?: (image: ImageItem) => void;
  onSelectVideo?: (video: VideoItem) => void;
  onLoadEffectConfig?: (config: any) => void;
  initialTab?: TabType;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Gold Spinner Component
// ═══════════════════════════════════════════════════════════════════════════════

const GoldSpinner: React.FC<{ size?: 'small' | 'medium' | 'large' }> = ({ size = 'medium' }) => {
  const sizeMap = { small: 30, medium: 50, large: 70 };
  const spinnerSize = sizeMap[size];
  
  return (
    <div 
      className="loading-spinner"
      style={{ width: spinnerSize, height: spinnerSize }}
    />
  );
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Star Rating Component - Gold Filled Stars
// ═══════════════════════════════════════════════════════════════════════════════

interface StarRatingProps {
  rating: number | null;
  maxStars?: number;
  size?: 'small' | 'medium' | 'large';
  interactive?: boolean;
  onRate?: (rating: number) => void;
}

const StarRating: React.FC<StarRatingProps> = ({
  rating,
  maxStars = 5,
  size = 'small',
  interactive = false,
  onRate,
}) => {
  const [hoverRating, setHoverRating] = useState(0);
  
  const displayRating = hoverRating || (rating ?? 0);
  const fullStars = Math.floor(displayRating);
  const hasHalfStar = displayRating % 1 >= 0.5;
  
  const sizeMap = { small: 16, medium: 22, large: 28 };
  const starSize = sizeMap[size];
  
  // Gold gradient for filled stars
  const goldGradient = 'url(#goldGradient)';
  const emptyColor = 'rgba(100, 100, 110, 0.5)';
  
  return (
    <div className={`star-rating ${interactive ? 'interactive' : ''}`}>
      <svg width="0" height="0" style={{ position: 'absolute' }}>
        <defs>
          <linearGradient id="goldGradient" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#ffd700" />
            <stop offset="50%" stopColor="#ffec8b" />
            <stop offset="100%" stopColor="#b8860b" />
          </linearGradient>
          <linearGradient id="goldHalfGradient" x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="50%" stopColor="url(#goldGradient)" />
            <stop offset="50%" stopColor={emptyColor} />
          </linearGradient>
          <filter id="goldGlow">
            <feGaussianBlur stdDeviation="1.5" result="coloredBlur"/>
            <feMerge>
              <feMergeNode in="coloredBlur"/>
              <feMergeNode in="SourceGraphic"/>
            </feMerge>
          </filter>
        </defs>
      </svg>
      
      {Array.from({ length: maxStars }, (_, i) => {
        const starValue = i + 1;
        const filled = starValue <= fullStars;
        const half = starValue === fullStars + 1 && hasHalfStar;
        
        return (
          <button
            key={i}
            className={`star ${filled ? 'filled' : ''} ${half ? 'half' : ''}`}
            style={{ width: starSize, height: starSize }}
            disabled={!interactive}
            onMouseEnter={() => interactive && setHoverRating(starValue)}
            onMouseLeave={() => interactive && setHoverRating(0)}
            onClick={() => interactive && onRate?.(starValue)}
          >
            <svg viewBox="0 0 24 24" fill="none">
              {half ? (
                <>
                  <defs>
                    <linearGradient id={`half-grad-${i}`} x1="0%" y1="0%" x2="100%" y2="0%">
                      <stop offset="50%" stopColor="#ffd700" />
                      <stop offset="50%" stopColor="rgba(100, 100, 110, 0.5)" />
                    </linearGradient>
                  </defs>
                  <path
                    d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"
                    fill={`url(#half-grad-${i})`}
                  />
                </>
              ) : (
                <path
                  d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"
                  fill={filled ? goldGradient : emptyColor}
                  filter={filled ? 'url(#goldGlow)' : undefined}
                />
              )}
            </svg>
          </button>
        );
      })}
      {rating !== null && rating !== undefined && (
        <span className="rating-value">{rating.toFixed(1)}</span>
      )}
    </div>
  );
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Connection Status Component - Gold for Connected, Red for Error
// ═══════════════════════════════════════════════════════════════════════════════

const ConnectionStatus: React.FC<{
  isConnected: boolean;
  isChecking: boolean;
  error?: string;
  onRetry: () => void;
}> = ({ isConnected, isChecking, error, onRetry }) => {
  if (isChecking) {
    return (
      <div className="connection-status checking">
        <span className="status-icon">⟳</span>
        <span>Checking connection...</span>
      </div>
    );
  }
  
  if (!isConnected) {
    return (
      <div className="connection-status error">
        <span className="status-icon">✕</span>
        <span>Not connected to VPS</span>
        {error && <span className="error-detail">{error}</span>}
        <button onClick={onRetry} className="retry-btn">Retry</button>
      </div>
    );
  }
  
  return (
    <div className="connection-status connected">
      <span className="status-icon">◉</span>
      <span>Connected to VPS Storage</span>
    </div>
  );
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Shader Card Component - Glass Card with Gold Border on Hover
// ═══════════════════════════════════════════════════════════════════════════════

interface ShaderCardProps {
  shader: ShaderItem & { thumbnail_url?: string };
  isSelected: boolean;
  onSelect: () => void;
  onRate: (rating: number) => void;
  onPreview: () => void;
}

const ShaderCard: React.FC<ShaderCardProps> = ({ shader, isSelected, onSelect, onRate, onPreview }) => {
  const [showDetails, setShowDetails] = useState(false);
  
  const formatDate = (dateStr: string) => {
    if (!dateStr) return 'Unknown';
    try {
      return new Date(dateStr).toLocaleDateString();
    } catch {
      return dateStr;
    }
  };
  
  return (
    <div 
      className={`storage-card shader-card ${isSelected ? 'selected' : ''} ${shader.has_errors ? 'has-errors' : ''}`}
      onClick={onSelect}
    >
      {shader.thumbnail_url ? (
        <div className="shader-thumb-wrap">
          <img src={shader.thumbnail_url} alt={shader.name} className="shader-thumb" />
        </div>
      ) : null}

      <div className="card-header">
        <h4 className="card-title">{shader.name}</h4>
        {shader.has_errors && <span className="error-badge" title="Has errors">⚠</span>}
      </div>
      
      <div className="card-meta">
        <span className="meta-item">{shader.format}</span>
        <span className="meta-item">{shader.author || 'Unknown'}</span>
        <span className="meta-item">{formatDate(shader.date)}</span>
      </div>
      
      <p className="card-description">{shader.description || 'No description'}</p>
      
      <div className="card-tags">
        {shader.tags.slice(0, 5).map((tag, i) => (
          <span key={i} className="tag">{tag}</span>
        ))}
        {shader.tags.length > 5 && (
          <span className="tag more">+{shader.tags.length - 5}</span>
        )}
      </div>
      
      <div className="card-actions">
        <div className="card-rating" onClick={e => e.stopPropagation()}>
          <StarRating 
            rating={shader.stars || shader.rating} 
            interactive 
            onRate={onRate}
          />
        </div>
        <button className="preview-btn small" onClick={e => { e.stopPropagation(); onPreview(); }}>
          Preview
        </button>
      </div>
      
      <button 
        className="details-toggle"
        onClick={e => { e.stopPropagation(); setShowDetails(!showDetails); }}
      >
        {showDetails ? '▲ Hide details' : '▼ Show details'}
      </button>
      
      {showDetails && (
        <div className="card-details">
          <div className="detail-row">
            <span className="detail-label">ID:</span>
            <code className="detail-value">{shader.id}</code>
          </div>
          <div className="detail-row">
            <span className="detail-label">Filename:</span>
            <code className="detail-value">{shader.filename}</code>
          </div>
          <div className="detail-row">
            <span className="detail-label">Source:</span>
            <span className="detail-value">{shader.source}</span>
          </div>
          {shader.url && (
            <div className="detail-row">
              <span className="detail-label">URL:</span>
              <a 
                href={shader.url} 
                target="_blank" 
                rel="noopener noreferrer"
                className="detail-value link"
                onClick={e => e.stopPropagation()}
              >
                Open ↗
              </a>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Image Card Component
// ═══════════════════════════════════════════════════════════════════════════════

interface ImageCardProps {
  image: ImageItem;
  isSelected: boolean;
  onSelect: () => void;
}

const ImageCard: React.FC<ImageCardProps> = ({ image, isSelected, onSelect }) => {
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState(false);
  
  return (
    <div 
      className={`storage-card image-card ${isSelected ? 'selected' : ''}`}
      onClick={onSelect}
    >
      <div className="image-preview">
        {!loaded && !error && (
          <div className="image-placeholder">
            <div className="spinner" />
            <span>Loading...</span>
          </div>
        )}
        {error && (
          <div className="image-placeholder error">
            <span>⚠ Failed to load</span>
          </div>
        )}
        <img
          src={image.url}
          alt={image.description || 'Storage image'}
          onLoad={() => setLoaded(true)}
          onError={() => setError(true)}
          style={{ opacity: loaded ? 1 : 0 }}
        />
      </div>
      
      <div className="card-content">
        <p className="image-description">{image.description || 'Untitled'}</p>
        
        <div className="card-tags">
          {image.tags.slice(0, 4).map((tag, i) => (
            <span key={i} className="tag">{tag}</span>
          ))}
        </div>
        
        <a 
          href={image.url}
          target="_blank"
          rel="noopener noreferrer"
          className="open-link"
          onClick={e => e.stopPropagation()}
        >
          Open in new tab ↗
        </a>
      </div>
    </div>
  );
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Video Card Component
// ═══════════════════════════════════════════════════════════════════════════════

interface VideoCardProps {
  video: VideoItem;
  isSelected: boolean;
  onSelect: () => void;
}

const VideoCard: React.FC<VideoCardProps> = ({ video, isSelected, onSelect }) => {
  const formatDuration = (seconds?: number) => {
    if (!seconds) return '--:--';
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };
  
  return (
    <div 
      className={`storage-card video-card ${isSelected ? 'selected' : ''}`}
      onClick={onSelect}
    >
      <div className="video-preview">
        <div className="video-icon">▶</div>
        <span className="video-duration">{formatDuration(video.duration)}</span>
      </div>
      
      <div className="card-content">
        <h4 className="card-title">{video.title}</h4>
        <p className="video-artist">{video.artist || 'Unknown artist'}</p>
        
        <a 
          href={video.url}
          target="_blank"
          rel="noopener noreferrer"
          className="open-link"
          onClick={e => e.stopPropagation()}
        >
          Play ↗
        </a>
      </div>
    </div>
  );
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Operations Panel Component
// ═══════════════════════════════════════════════════════════════════════════════

const OperationsPanel: React.FC<{
  operations: any[];
  onClearCompleted: () => void;
}> = ({ operations, onClearCompleted }) => {
  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'pending': return '◷';
      case 'in_progress': return '↻';
      case 'completed': return '✓';
      case 'error': return '✕';
      default: return '?';
    }
  };
  
  const getStatusClass = (status: string) => {
    switch (status) {
      case 'pending': return 'pending';
      case 'in_progress': return 'in-progress';
      case 'completed': return 'completed';
      case 'error': return 'error';
      default: return '';
    }
  };
  
  const formatTime = (timestamp: number) => {
    return new Date(timestamp).toLocaleTimeString();
  };
  
  return (
    <div className="operations-panel">
      <div className="operations-header">
        <h3>Recent Operations</h3>
        <button onClick={onClearCompleted} className="clear-btn">
          Clear Completed
        </button>
      </div>
      
      {operations.length === 0 ? (
        <div className="operations-empty">No recent operations</div>
      ) : (
        <div className="operations-list">
          {operations.map(op => (
            <div key={op.id} className={`operation-item ${getStatusClass(op.status)}`}>
              <span className="operation-icon">{getStatusIcon(op.status)}</span>
              <div className="operation-info">
                <span className="operation-type">{op.type}</span>
                {op.itemName && <span className="operation-item-name">{op.itemName}</span>}
                {op.message && <span className="operation-message">{op.message}</span>}
              </div>
              <span className="operation-time">{formatTime(op.timestamp)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Main Storage Browser Component
// ═══════════════════════════════════════════════════════════════════════════════

export const StorageBrowser: React.FC<StorageBrowserProps> = ({
  onSelectShader,
  onSelectImage,
  onSelectVideo,
  onLoadEffectConfig,
  initialTab = 'shaders',
}) => {
  const storage = useStorage();
  const [activeTab, setActiveTab] = useState<TabType>(initialTab);
  const [searchInput, setSearchInput] = useState('');
  const [searchQuery, setSearchQuery] = useState('');
  const [sortField, setSortField] = useState<SortField>('name');
  const [sortDirection, setSortDirection] = useState<SortDirection>('asc');
  const [selectedItem, setSelectedItem] = useState<string | null>(null);
  const [libraryItems, setLibraryItems] = useState<LibraryItem[]>([]);
  const [isLoadingLibrary, setIsLoadingLibrary] = useState(false);
  const [libraryTypeFilter, setLibraryTypeFilter] = useState<'all' | 'song' | 'sample' | 'shader'>('all');
  const [libraryError, setLibraryError] = useState<string | undefined>();
  
  // Load initial data
  useEffect(() => {
    if (storage.isConnected) {
      storage.refreshAll();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [storage.isConnected]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      setSearchQuery(searchInput);
    }, 250);
    return () => window.clearTimeout(timer);
  }, [searchInput]);

  useEffect(() => {
    if (activeTab !== 'library') return;
    setIsLoadingLibrary(true);
    setLibraryError(undefined);

    fetch(`${STORAGE_API_URL}/api/songs`)
      .then(async res => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
      })
      .then((items: LibraryItem[]) => setLibraryItems(items))
      .catch(error => {
        setLibraryError(error instanceof Error ? error.message : 'Failed to load library');
      })
      .finally(() => setIsLoadingLibrary(false));
  }, [activeTab]);
  
  // Filter and sort shaders
  const filteredShaders = useMemo(() => {
    let result = [...storage.shaders];
    
    // Filter by search
    if (searchQuery) {
      const q = searchQuery.toLowerCase();
      result = result.filter(s => 
        s.name.toLowerCase().includes(q) ||
        s.description.toLowerCase().includes(q) ||
        s.tags.some(t => t.toLowerCase().includes(q))
      );
    }
    
    // Sort
    result.sort((a, b) => {
      let comparison = 0;
      switch (sortField) {
        case 'name':
          comparison = a.name.localeCompare(b.name);
          break;
        case 'date':
          comparison = new Date(a.date || 0).getTime() - new Date(b.date || 0).getTime();
          break;
        case 'rating':
          comparison = (a.rating || 0) - (b.rating || 0);
          break;
        case 'tags':
          comparison = a.tags.length - b.tags.length;
          break;
      }
      return sortDirection === 'asc' ? comparison : -comparison;
    });
    
    return result;
  }, [storage.shaders, searchQuery, sortField, sortDirection]);
  
  // Filter images
  const filteredImages = useMemo(() => {
    if (!searchQuery) return storage.images;
    const q = searchQuery.toLowerCase();
    return storage.images.filter(img =>
      (img.description || '').toLowerCase().includes(q) ||
      img.tags.some(t => t.toLowerCase().includes(q))
    );
  }, [storage.images, searchQuery]);
  
  // Filter videos
  const filteredVideos = useMemo(() => {
    if (!searchQuery) return storage.videos;
    const q = searchQuery.toLowerCase();
    return storage.videos.filter(v =>
      v.title.toLowerCase().includes(q) ||
      v.artist.toLowerCase().includes(q)
    );
  }, [storage.videos, searchQuery]);
  
  // Filter audio
  const filteredAudio = useMemo(() => {
    if (!searchQuery) return storage.audio;
    const q = searchQuery.toLowerCase();
    return storage.audio.filter(a =>
      a.title.toLowerCase().includes(q) ||
      a.artist.toLowerCase().includes(q)
    );
  }, [storage.audio, searchQuery]);
  
  // Handle sort toggle
  const toggleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDirection(prev => prev === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('asc');
    }
  };
  
  // Handle shader select
  const handleShaderSelect = (shader: ShaderItem) => {
    setSelectedItem(shader.id);
    onSelectShader?.(shader);
  };
  
  // Handle shader rate
  const handleShaderRate = async (shaderId: string, rating: number) => {
    await storage.rateShader(shaderId, rating);
    storage.refreshShaders().catch(() => {});
  };
  
  // Handle file upload
  const handleUpload = async (files: File[], type: 'image' | 'video' | 'audio' | 'shader') => {
    return storage.uploadFiles(files, type);
  };
  
  // Render tab content
  const LibraryCard: React.FC<{ item: LibraryItem; onPreview: () => void }> = ({ item, onPreview }) => (
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

  const [isPreviewOpen, setIsPreviewOpen] = useState(false);
  const [previewItem, setPreviewItem] = useState<LibraryItem | null>(null);

  const renderPreviewModal = () => {
    if (!isPreviewOpen || !previewItem) return null;
    return (
      <div className="preview-modal-backdrop" onClick={() => setIsPreviewOpen(false)}>
        <div className="preview-modal" onClick={e => e.stopPropagation()}>
          <button className="close-modal" onClick={() => setIsPreviewOpen(false)}>×</button>
          <div className="preview-grid">
            <div className="preview-panel preview-thumbnail">
              <h3>{previewItem.name}</h3>
              {previewItem.thumbnail_url ? (
                <img src={previewItem.thumbnail_url} alt={previewItem.name} />
              ) : (
                <div className="thumbnail-fallback">No thumbnail available</div>
              )}
              <div className="preview-meta">
                <span>{previewItem.type}</span>
                {previewItem.author && <span>{previewItem.author}</span>}
                {previewItem.updated_at && <span>{new Date(previewItem.updated_at).toLocaleDateString()}</span>}
              </div>
            </div>
            <div className="preview-panel preview-webgpu">
              <h3>Live WebGPU preview</h3>
              <div className="webgpu-preview-placeholder">
                <div className="preview-live-label">Live WebGPU renderer</div>
                <div className="preview-placeholder-canvas" />
              </div>
              <p className="preview-copy">This preview is connected to the storage browser and can be used with the live canvas.</p>
            </div>
          </div>
        </div>
      </div>
    );
  };

  const libraryTypes = useMemo(() => {
    const counts = libraryItems.reduce((acc, item) => {
      acc[item.type] = (acc[item.type] || 0) + 1;
      return acc;
    }, {} as Record<string, number>);
    return counts;
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

  const renderTabContent = () => {
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
                      onClick={() => setLibraryTypeFilter(type)}
                    >
                      {type === 'all' ? 'All' : type.charAt(0).toUpperCase() + type.slice(1)}
                      {type !== 'all' && libraryTypes[type] ? ` (${libraryTypes[type]})` : ''}
                    </button>
                  ))}
                </div>
                <div className="library-summary">
                  {isLoadingLibrary ? (
                    <span>Loading library…</span>
                  ) : (
                    <span>{filteredLibrary.length} items matched</span>
                  )}
                </div>
              </div>

              <div className="library-actions">
                <button onClick={() => setSearchInput('')} className="secondary-btn">Clear Search</button>
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
                  <LibraryCard
                    key={item.id}
                    item={item}
                    onPreview={() => {
                      setPreviewItem(item);
                      setIsPreviewOpen(true);
                    }}
                  />
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
                <button 
                  className={sortField === 'name' ? 'active' : ''}
                  onClick={() => toggleSort('name')}
                >
                  Name {sortField === 'name' && (sortDirection === 'asc' ? '▲' : '▼')}
                </button>
                <button 
                  className={sortField === 'rating' ? 'active' : ''}
                  onClick={() => toggleSort('rating')}
                >
                  Rating {sortField === 'rating' && (sortDirection === 'asc' ? '▲' : '▼')}
                </button>
                <button 
                  className={sortField === 'date' ? 'active' : ''}
                  onClick={() => toggleSort('date')}
                >
                  Date {sortField === 'date' && (sortDirection === 'asc' ? '▲' : '▼')}
                </button>
              </div>
            </div>
            
            {/* Drag & Drop Upload */}
            <DragDropUpload
              type="shader"
              onUpload={handleUpload}
              disabled={!storage.isConnected}
            />
            
            {storage.isLoadingShaders ? (
              <div className="loading-state">
                <GoldSpinner size="medium" />
                <span>Loading shaders...</span>
              </div>
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
                    onSelect={() => handleShaderSelect(shader)}
                    onRate={(rating) => handleShaderRate(shader.id, rating)}
                    onPreview={() => {
                      setPreviewItem({
                        id: shader.id,
                        name: shader.name,
                        type: 'shader',
                        description: shader.description,
                        author: shader.author,
                        filename: shader.filename,
                        tags: shader.tags,
                        thumbnail_url: shader.thumbnail_url,
                      });
                      setIsPreviewOpen(true);
                    }}
                  />
                ))}
              </div>
            )}
          </div>
        );
        
      case 'images':
        return (
          <div className="tab-content">
            <div className="content-header">
              <span className="item-count">{filteredImages.length} images</span>
            </div>
            
            {/* Drag & Drop Upload */}
            <DragDropUpload
              type="image"
              onUpload={handleUpload}
              disabled={!storage.isConnected}
            />
            
            {storage.isLoadingImages ? (
              <div className="loading-state">
                <GoldSpinner size="medium" />
                <span>Loading images...</span>
              </div>
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
                    onSelect={() => {
                      setSelectedItem(`img-${i}`);
                      onSelectImage?.(image);
                    }}
                  />
                ))}
              </div>
            )}
          </div>
        );
        
      case 'videos':
        return (
          <div className="tab-content">
            <div className="content-header">
              <span className="item-count">{filteredVideos.length} videos</span>
            </div>
            
            {/* Drag & Drop Upload */}
            <DragDropUpload
              type="video"
              onUpload={handleUpload}
              disabled={!storage.isConnected}
            />
            
            {storage.isLoadingVideos ? (
              <div className="loading-state">
                <GoldSpinner size="medium" />
                <span>Loading videos...</span>
              </div>
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
                    onSelect={() => {
                      setSelectedItem(video.id);
                      onSelectVideo?.(video);
                    }}
                  />
                ))}
              </div>
            )}
          </div>
        );
        
      case 'audio':
        return (
          <div className="tab-content">
            <div className="content-header">
              <span className="item-count">{filteredAudio.length} audio files</span>
            </div>
            
            {/* Drag & Drop Upload */}
            <DragDropUpload
              type="audio"
              onUpload={handleUpload}
              disabled={!storage.isConnected}
            />
            
            {storage.isLoadingVideos ? (
              <div className="loading-state">
                <GoldSpinner size="medium" />
                <span>Loading audio...</span>
              </div>
            ) : filteredAudio.length === 0 ? (
              <div className="empty-state">
                <div className="empty-state-icon">⚆</div>
                <span>{searchQuery ? 'No audio files match your search' : 'No audio files available'}</span>
              </div>
            ) : (
              <div className="cards-grid">
                {filteredAudio.map(audio => (
                  <VideoCard
                    key={audio.id}
                    video={audio}
                    isSelected={selectedItem === audio.id}
                    onSelect={() => {
                      setSelectedItem(audio.id);
                      onSelectVideo?.(audio);
                    }}
                  />
                ))}
              </div>
            )}
          </div>
        );
        
      case 'operations':
        return (
          <OperationsPanel
            operations={storage.operations}
            onClearCompleted={storage.clearCompleted}
          />
        );
        
      default:
        return null;
    }
  };
  
  return (
    <div className="storage-browser">
      {/* Header */}
      <div className="browser-header">
        <h2>◈ VPS Storage Manager</h2>
        <ConnectionStatus
          isConnected={storage.isConnected}
          isChecking={storage.isCheckingConnection}
          error={storage.connectionError}
          onRetry={storage.checkConnection}
        />
      </div>
      
      {/* Toast notifications */}
      <div className="toast-container">
        {storage.toasts.map(toast => (
          <div key={toast.id} className={`toast ${toast.type}`}>
            <span className="toast-message">{toast.message}</span>
            <button 
              className="toast-close"
              onClick={() => storage.dismissToast(toast.id)}
            >
              ×
            </button>
          </div>
        ))}
      </div>
      
      {/* Toolbar */}
      <div className="browser-toolbar">
        <div className="tab-buttons">
          <button 
            className={activeTab === 'shaders' ? 'active' : ''}
            onClick={() => setActiveTab('shaders')}
          >
            Shaders ({storage.shaders.length})
          </button>
          <button 
            className={activeTab === 'images' ? 'active' : ''}
            onClick={() => setActiveTab('images')}
          >
            Images ({storage.images.length})
          </button>
          <button 
            className={activeTab === 'videos' ? 'active' : ''}
            onClick={() => setActiveTab('videos')}
          >
            Videos ({storage.videos.length})
          </button>
          <button 
            className={activeTab === 'library' ? 'active' : ''}
            onClick={() => setActiveTab('library')}
          >
            Library ({libraryItems.length})
          </button>
          <button 
            className={activeTab === 'audio' ? 'active' : ''}
            onClick={() => setActiveTab('audio')}
          >
            Audio ({storage.audio.length})
          </button>
          <button 
            className={activeTab === 'operations' ? 'active' : ''}
            onClick={() => setActiveTab('operations')}
          >
            Operations
            {storage.activeOperations.length > 0 && (
              <span className="badge">{storage.activeOperations.length}</span>
            )}
          </button>
        </div>
        
        <div className="search-box">
          <input
            type="text"
            placeholder={`Search ${activeTab}...`}
            value={searchInput}
            onChange={e => setSearchInput(e.target.value)}
          />
          {searchInput && (
            <button className="clear-search" onClick={() => setSearchInput('')}>
              ×
            </button>
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
      
      {/* Content */}
      <div className="browser-content">
        {renderTabContent()}
        {renderPreviewModal()}
      </div>
      
      {/* Footer */}
      <div className="browser-footer">
        <span>VPS: {STORAGE_VPS_HOST}:{STORAGE_VPS_PORT}</span>
        <span>•</span>
        <span>Static: {STATIC_NGINX_URL}</span>
        {storage.lastError && (
          <span className="error-text">Error: {storage.lastError}</span>
        )}
      </div>
    </div>
  );
};

export default StorageBrowser;
