/**
 * StorageUIComponents.tsx
 *
 * Reusable UI components for the Storage Browser.
 * Includes spinners, star ratings, status indicators, and item cards.
 */

import React, { useState } from 'react';
import { ShaderItem, ImageItem, VideoItem } from '../services/StorageService';

// ═══════════════════════════════════════════════════════════════════════════════
//  Gold Spinner Component
// ═══════════════════════════════════════════════════════════════════════════════

export const GoldSpinner: React.FC<{ size?: 'small' | 'medium' | 'large' }> = ({ size = 'medium' }) => {
  const sizeMap = { small: 30, medium: 50, large: 70 };
  const spinnerSize = sizeMap[size];

  return <div className="loading-spinner" style={{ width: spinnerSize, height: spinnerSize }} />;
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Star Rating Component - Gold Filled Stars
// ═══════════════════════════════════════════════════════════════════════════════

export interface StarRatingProps {
  rating: number | null;
  maxStars?: number;
  size?: 'small' | 'medium' | 'large';
  interactive?: boolean;
  onRate?: (rating: number) => void;
}

export const StarRating: React.FC<StarRatingProps> = ({
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
            <feGaussianBlur stdDeviation="1.5" result="coloredBlur" />
            <feMerge>
              <feMergeNode in="coloredBlur" />
              <feMergeNode in="SourceGraphic" />
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
//  Connection Status Component
// ═══════════════════════════════════════════════════════════════════════════════

export const ConnectionStatus: React.FC<{
  isConnected: boolean;
  message?: string;
  isChecking?: boolean;
  error?: string;
  onRetry?: () => Promise<boolean>;
}> = ({ isConnected, message = 'Connected', isChecking = false, error, onRetry }) => {
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '8px',
        fontSize: '12px',
        color: isConnected ? '#2ed573' : error ? '#ff6b6b' : '#a0a0b0',
      }}
    >
      <div
        style={{
          width: '8px',
          height: '8px',
          borderRadius: '50%',
          background: isConnected ? '#2ed573' : error ? '#ff6b6b' : '#a0a0b0',
          animation: isChecking ? 'pulse 2s infinite' : isConnected ? 'pulse 3s infinite' : 'none',
        }}
      />
      {isChecking ? '⟳ Checking...' : error ? `✕ ${error}` : message}
      {error && onRetry && (
        <button
          onClick={onRetry}
          style={{
            background: 'transparent',
            border: 'none',
            color: '#ff6b6b',
            cursor: 'pointer',
            fontSize: '12px',
            marginLeft: '4px',
          }}
        >
          Retry
        </button>
      )}
    </div>
  );
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Item Cards (Shader, Image, Video)
// ═══════════════════════════════════════════════════════════════════════════════

export interface ShaderCardProps {
  shader: ShaderItem;
  isSelected: boolean;
  onSelect: (shader: ShaderItem) => void;
  onRate?: (rating: number) => void;
  onPreview?: () => void;
}

export const ShaderCard: React.FC<ShaderCardProps> = ({
  shader,
  isSelected,
  onSelect,
  onRate,
  onPreview,
}) => {
  return (
    <div
      className={`storage-item-card ${isSelected ? 'selected' : ''}`}
      onClick={() => onSelect(shader)}
      style={{
        cursor: 'pointer',
        padding: '12px',
        borderRadius: '8px',
        background: isSelected ? 'rgba(255, 215, 0, 0.15)' : 'rgba(255, 255, 255, 0.05)',
        border: `1px solid ${isSelected ? 'rgba(255, 215, 0, 0.3)' : 'rgba(255, 215, 0, 0.1)'}`,
        transition: 'all 0.2s',
      }}
    >
      <h4 style={{ margin: '0 0 8px', fontSize: '14px', color: '#FFD700' }}>{shader.name}</h4>
      <p style={{ margin: '0 0 8px', fontSize: '12px', color: '#a0a0b0' }}>{shader.type}</p>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <StarRating rating={shader.rating} size="small" interactive={!!onRate} onRate={onRate} />
        {onPreview && (
          <button
            onClick={(e) => {
              e.stopPropagation();
              onPreview();
            }}
            style={{
              background: 'rgba(255, 215, 0, 0.2)',
              border: '1px solid rgba(255, 215, 0, 0.3)',
              color: '#FFD700',
              padding: '4px 12px',
              borderRadius: '4px',
              cursor: 'pointer',
              fontSize: '12px',
            }}
          >
            Preview
          </button>
        )}
      </div>
    </div>
  );
};

export interface ImageCardProps {
  image: ImageItem;
  isSelected: boolean;
  onSelect: (image: ImageItem) => void;
}

export const ImageCard: React.FC<ImageCardProps> = ({ image, isSelected, onSelect }) => {
  return (
    <div
      className={`storage-item-card ${isSelected ? 'selected' : ''}`}
      onClick={() => onSelect(image)}
      style={{
        cursor: 'pointer',
        padding: '12px',
        borderRadius: '8px',
        background: isSelected ? 'rgba(255, 215, 0, 0.15)' : 'rgba(255, 255, 255, 0.05)',
        border: `1px solid ${isSelected ? 'rgba(255, 215, 0, 0.3)' : 'rgba(255, 215, 0, 0.1)'}`,
      }}
    >
      <h4 style={{ margin: '0 0 8px', fontSize: '14px', color: '#FFD700' }}>
        Image
      </h4>
      <p style={{ margin: '0', fontSize: '12px', color: '#a0a0b0', wordBreak: 'break-all' }}>
        {image.url.substring(0, 50)}...
      </p>
    </div>
  );
};

export interface VideoCardProps {
  video: VideoItem;
  isSelected: boolean;
  onSelect: (video: VideoItem) => void;
}

export const VideoCard: React.FC<VideoCardProps> = ({ video, isSelected, onSelect }) => {
  return (
    <div
      className={`storage-item-card ${isSelected ? 'selected' : ''}`}
      onClick={() => onSelect(video)}
      style={{
        cursor: 'pointer',
        padding: '12px',
        borderRadius: '8px',
        background: isSelected ? 'rgba(255, 215, 0, 0.15)' : 'rgba(255, 255, 255, 0.05)',
        border: `1px solid ${isSelected ? 'rgba(255, 215, 0, 0.3)' : 'rgba(255, 215, 0, 0.1)'}`,
      }}
    >
      <h4 style={{ margin: '0 0 8px', fontSize: '14px', color: '#FFD700' }}>{video.title}</h4>
      <p style={{ margin: '0', fontSize: '12px', color: '#a0a0b0' }}>Video</p>
    </div>
  );
};
