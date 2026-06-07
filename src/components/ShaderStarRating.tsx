// ═══════════════════════════════════════════════════════════════════════════════
//  ShaderStarRating.tsx
//  Star rating component for shaders
// ═══════════════════════════════════════════════════════════════════════════════

import React, { useState } from 'react';
import './ShaderStarRating.css';

interface ShaderStarRatingProps {
  shaderId: string;
  stars: number;
  ratingCount: number;
  onRate: (shaderId: string, rating: number) => Promise<void>;
  size?: 'small' | 'medium' | 'large';
  readonly?: boolean;
}

export const ShaderStarRating: React.FC<ShaderStarRatingProps> = ({
  shaderId,
  stars,
  ratingCount,
  onRate,
  size = 'small',
  readonly = false,
}) => {
  const [hoverRating, setHoverRating] = useState(0);
  const [isRating, setIsRating] = useState(false);

  const sizeMap = {
    small: 14,
    medium: 20,
    large: 28,
  };

  const starSize = sizeMap[size];

  const handleRate = async (rating: number) => {
    if (readonly || isRating) return;
    setIsRating(true);
    await onRate(shaderId, rating);
    setIsRating(false);
  };

  const displayStars = hoverRating || stars;
  const fullStars = Math.floor(displayStars);
  const hasHalfStar = displayStars % 1 >= 0.5;

  return (
    <div className={`star-rating size-${size}`}>
      <div className="stars-container">
        {[1, 2, 3, 4, 5].map((star) => {
          const filled = star <= fullStars;
          const half = star === fullStars + 1 && hasHalfStar;
          
          return (
            <button
              key={star}
              className={`star ${filled ? 'filled' : ''} ${half ? 'half' : ''}`}
              style={{ width: starSize, height: starSize }}
              onMouseEnter={() => !readonly && setHoverRating(star)}
              onMouseLeave={() => setHoverRating(0)}
              onClick={() => handleRate(star)}
              disabled={readonly || isRating}
              title={readonly ? `${stars.toFixed(1)} stars` : `Rate ${star} stars`}
            >
              <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                {half ? (
                  <>
                    <defs>
                      <linearGradient id={`half-grad-${shaderId}`}>
                        <stop offset="50%" stopColor="#ffd700" />
                        <stop offset="50%" stopColor="#333" />
                      </linearGradient>
                    </defs>
                    <path
                      d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"
                      fill={`url(#half-grad-${shaderId})`}
                      stroke="#ffd700"
                      strokeWidth="1"
                    />
                  </>
                ) : (
                  <path
                    d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"
                    fill={filled ? '#ffd700' : '#333'}
                    stroke={filled ? '#ffd700' : '#555'}
                    strokeWidth="1"
                  />
                )}
              </svg>
            </button>
          );
        })}
      </div>
      
      <span className="rating-text">
        {stars > 0 ? (
          <>
            <strong>{stars.toFixed(1)}</strong>
            <span className="rating-count">({ratingCount})</span>
          </>
        ) : (
          <span className="no-rating">No ratings</span>
        )}
      </span>
    </div>
  );
};

export default ShaderStarRating;
