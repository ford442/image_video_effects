// ═══════════════════════════════════════════════════════════════════════════════
//  StorageBrowser.tsx
//  Visual readout page for the VPS Storage API
//  Browse shaders, images, videos with ratings and management features
// ═══════════════════════════════════════════════════════════════════════════════

import React, { useState, useEffect, useMemo } from 'react';
import { useStorage } from '../hooks/useStorage';
import { ShaderItem, ImageItem, VideoItem } from '../services/StorageService';
import './StorageBrowser.css';

// ═══════════════════════════════════════════════════════════════════════════════
//  Types
// ═══════════════════════════════════════════════════════════════════════════════

type TabType = 'shaders' | 'images' | 'videos' | 'audio' | 'operations';
type SortField = 'name' | 'date' | 'rating' | 'tags';
type SortDirection = 'asc' | 'desc';

interface StorageBrowserProps {
  onSelectShader?: (shader: ShaderItem) => void;
  onSelectImage?: (image: ImageItem) => void;
  onSelectVideo?: (video: VideoItem) => void;
  onLoadEffectConfig?: (config: any) => void;
  initialTab?: TabType;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Star Rating Component
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
  
  const sizeMap = { small: 14, medium: 18, large: 24 };
  const starSize = sizeMap[size];
  
  return (
    <div className={`star-rating ${interactive ? 'interactive' : ''}`}>
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
                    <linearGradient id={`half-grad-${i}`}>
                      <stop offset="50%" stopColor="#ffd700" />
                      <stop offset="50%" stopColor="#444" />
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
                  fill={filled ? '#ffd700' : '#444'}
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
//  Connection Status Component
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
        <span className="status-icon">⏳</span>
        <span>Checking connection...</span>
      </div>
    );
  }
  
  if (!isConnected) {
    return (
      <div className="connection-status error">
        <span className="status-icon">❌</span>
        <span>Not connected to VPS</span>
        {error && <span className="error-detail">{error}</span>}
        <button onClick={onRetry} className="retry-btn">Retry</button>
      </div>
    );
  }
  
  return (
    <div className="connection-status connected">
      <span className="status-icon">✅</span>
      <span>Connected to VPS Storage</span>
    </div>
  );
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Shader Card Component
// ═══════════════════════════════════════════════════════════════════════════════

interface ShaderCardProps {
  shader: ShaderItem;
  isSelected: boolean;
  onSelect: () => void;
  onRate: (rating: number) => void;
}

const ShaderCard: React.FC<ShaderCardProps> = ({ shader, isSelected, onSelect, onRate }) => {
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
      <div className="card-header">
        <h4 className="card-title">{shader.name}</h4>
        {shader.has_errors && <span className="error-badge" title="Has errors">⚠️</span>}
      </div>
      
      <div className="card-meta">
        <span className="meta-item">📁 {shader.format}</span>
        <span className="meta-item">👤 {shader.author || 'Unknown'}</span>
        <span className="meta-item">📅 {formatDate(shader.date)}</span>
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
      
      <div className="card-rating" onClick={e => e.stopPropagation()}>
        <StarRating 
          rating={shader.rating} 
          interactive 
          onRate={onRate}
        />
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
        {!loaded && !error && <div className="image-placeholder">Loading...</div>}
        {error && <div className="image-placeholder error">Failed to load</div>}
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
        <div className="video-icon">🎬</div>
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
      case 'pending': return '⏳';
      case 'in_progress': return '🔄';
      case 'completed': return '✅';
      case 'error': return '❌';
      default: return '❓';
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
  const [searchQuery, setSearchQuery] = useState('');
  const [sortField, setSortField] = useState<SortField>('name');
  const [sortDirection, setSortDirection] = useState<SortDirection>('asc');
  const [selectedItem, setSelectedItem] = useState<string | null>(null);
  
  // Load initial data
  useEffect(() => {
    if (storage.isConnected) {
      storage.refreshAll();
    }
  }, [storage.isConnected]);
  
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
  };
  
  // Render tab content
  const renderTabContent = () => {
    switch (activeTab) {
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
            
            {storage.isLoadingShaders ? (
              <div className="loading-state">Loading shaders...</div>
            ) : filteredShaders.length === 0 ? (
              <div className="empty-state">
                {searchQuery ? 'No shaders match your search' : 'No shaders available'}
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
            
            {storage.isLoadingImages ? (
              <div className="loading-state">Loading images...</div>
            ) : filteredImages.length === 0 ? (
              <div className="empty-state">
                {searchQuery ? 'No images match your search' : 'No images available'}
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
            
            {storage.isLoadingVideos ? (
              <div className="loading-state">Loading videos...</div>
            ) : filteredVideos.length === 0 ? (
              <div className="empty-state">
                {searchQuery ? 'No videos match your search' : 'No videos available'}
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
            
            {storage.isLoadingVideos ? (
              <div className="loading-state">Loading audio...</div>
            ) : filteredAudio.length === 0 ? (
              <div className="empty-state">
                {searchQuery ? 'No audio files match your search' : 'No audio files available'}
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
        <h2>📦 VPS Storage Manager</h2>
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
            🎨 Shaders ({storage.shaders.length})
          </button>
          <button 
            className={activeTab === 'images' ? 'active' : ''}
            onClick={() => setActiveTab('images')}
          >
            🖼️ Images ({storage.images.length})
          </button>
          <button 
            className={activeTab === 'videos' ? 'active' : ''}
            onClick={() => setActiveTab('videos')}
          >
            🎬 Videos ({storage.videos.length})
          </button>
          <button 
            className={activeTab === 'audio' ? 'active' : ''}
            onClick={() => setActiveTab('audio')}
          >
            🎵 Audio ({storage.audio.length})
          </button>
          <button 
            className={activeTab === 'operations' ? 'active' : ''}
            onClick={() => setActiveTab('operations')}
          >
            🔄 Operations
            {storage.activeOperations.length > 0 && (
              <span className="badge">{storage.activeOperations.length}</span>
            )}
          </button>
        </div>
        
        <div className="search-box">
          <input
            type="text"
            placeholder={`Search ${activeTab}...`}
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
          />
          {searchQuery && (
            <button className="clear-search" onClick={() => setSearchQuery('')}>
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
          🔄 Refresh
        </button>
      </div>
      
      {/* Content */}
      <div className="browser-content">
        {renderTabContent()}
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

// Import for footer display
import { STORAGE_VPS_HOST, STORAGE_VPS_PORT, STATIC_NGINX_URL } from '../config/appConfig';

export default StorageBrowser;
