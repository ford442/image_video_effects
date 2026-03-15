// ═══════════════════════════════════════════════════════════════════════════════
//  ShaderBrowserWithRatings.tsx
//  Coordinate-based shader browser with star ratings integration
// ═══════════════════════════════════════════════════════════════════════════════

import React, { useState, useMemo } from 'react';
import { useShaderRatings } from '../services/ShaderRatingIntegration';
import { ShaderStarRating } from './ShaderStarRating';
import './ShaderBrowserWithRatings.css';

interface ShaderBrowserWithRatingsProps {
  currentShaderId: string | null;
  onSelectShader: (id: string) => void;
}

type MenuView = 'zone' | 'rating' | 'popularity' | 'coordinate';

export const ShaderBrowserWithRatings: React.FC<ShaderBrowserWithRatingsProps> = ({
  currentShaderId,
  onSelectShader,
}) => {
  const { shaders, loading, rateShader, menus } = useShaderRatings();
  const [activeView, setActiveView] = useState<MenuView>('zone');
  const [searchQuery, setSearchQuery] = useState('');
  const [minRating, setMinRating] = useState(0);

  // Filter shaders by search and minimum rating
  const filteredShaders = useMemo(() => {
    let filtered = shaders;
    
    if (searchQuery) {
      const q = searchQuery.toLowerCase();
      filtered = filtered.filter(s => 
        s.name.toLowerCase().includes(q) ||
        s.tags.some(t => t.toLowerCase().includes(q))
      );
    }
    
    if (minRating > 0) {
      filtered = filtered.filter(s => s.stars >= minRating);
    }
    
    return filtered;
  }, [shaders, searchQuery, minRating]);

  // Get current menu groups based on view
  const menuGroups = useMemo(() => {
    const builder = { buildByZone: () => menus.byZone, buildByRating: () => menus.byRating, buildByPopularity: () => menus.byPopularity };
    
    switch (activeView) {
      case 'zone': return menus.byZone;
      case 'rating': return menus.byRating;
      case 'popularity': return menus.byPopularity;
      case 'coordinate':
        // Flat list sorted by coordinate
        return [{ label: 'All Shaders by Coordinate', shaders: [...shaders].sort((a, b) => a.coordinate - b.coordinate) }];
      default: return menus.byZone;
    }
  }, [activeView, menus, shaders]);

  if (loading) {
    return (
      <div className="shader-browser-loading">
        <div className="loading-spinner"></div>
        <span>Loading shader ratings...</span>
      </div>
    );
  }

  return (
    <div className="shader-browser-with-ratings">
      {/* Header */}
      <div className="browser-header">
        <h2>Shader Browser <span className="shader-count">({filteredShaders.length} / {shaders.length})</span></h2>
        
        {/* Search */}
        <input
          type="text"
          placeholder="Search shaders..."
          value={searchQuery}
          onChange={e => setSearchQuery(e.target.value)}
          className="search-input"
        />
      </div>

      {/* View Tabs */}
      <div className="view-tabs">
        {[
          { id: 'zone' as MenuView, label: '🌊 By Zone', icon: '🌊' },
          { id: 'rating' as MenuView, label: '⭐ By Rating', icon: '⭐' },
          { id: 'popularity' as MenuView, label: '🔥 By Popularity', icon: '🔥' },
          { id: 'coordinate' as MenuView, label: '🔢 By Number', icon: '🔢' },
        ].map(tab => (
          <button
            key={tab.id}
            className={`view-tab ${activeView === tab.id ? 'active' : ''}`}
            onClick={() => setActiveView(tab.id)}
          >
            <span className="tab-icon">{tab.icon}</span>
            <span className="tab-label">{tab.label}</span>
          </button>
        ))}
      </div>

      {/* Rating Filter (for zone view) */}
      {activeView === 'zone' && (
        <div className="rating-filter">
          <span>Min Rating:</span>
          <select value={minRating} onChange={e => setMinRating(Number(e.target.value))}>
            <option value={0}>Any</option>
            <option value={3}>⭐⭐⭐+</option>
            <option value={4}>⭐⭐⭐⭐+</option>
            <option value={4.5}>⭐⭐⭐⭐½+</option>
          </select>
        </div>
      )}

      {/* Shader Groups */}
      <div className="shader-groups">
        {menuGroups.map(group => (
          <div key={group.label} className="shader-group">
            <div className="group-header">
              <h3>{group.label}</h3>
              <span className="group-count">{group.shaders.length}</span>
            </div>
            
            <div className="shader-grid">
              {group.shaders.map(shader => (
                <ShaderCard
                  key={shader.id}
                  shader={shader}
                  isSelected={currentShaderId === shader.id}
                  onSelect={() => onSelectShader(shader.id)}
                  onRate={rateShader}
                />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Shader Card Component
// ═══════════════════════════════════════════════════════════════════════════════

interface ShaderCardProps {
  shader: {
    id: string;
    coordinate: number;
    name: string;
    category: string;
    stars: number;
    ratingCount: number;
    playCount: number;
    tags: string[];
    zone: string;
  };
  isSelected: boolean;
  onSelect: () => void;
  onRate: (id: string, rating: number) => Promise<any>;
}

const ShaderCard: React.FC<ShaderCardProps> = ({
  shader,
  isSelected,
  onSelect,
  onRate,
}) => {
  const [showRating, setShowRating] = useState(false);

  const zoneColors: Record<string, string> = {
    ambient: '#1a5276',
    organic: '#1e8449',
    interactive: '#2874a6',
    artistic: '#8e44ad',
    'visual-fx': '#c0392b',
    retro: '#d35400',
    extreme: '#7d3c98',
  };

  return (
    <div
      className={`shader-card-rating ${isSelected ? 'selected' : ''}`}
      onClick={onSelect}
      style={{ borderLeftColor: zoneColors[shader.zone] || '#666' }}
    >
      {/* Coordinate Badge */}
      <div className="coord-badge">
        #{shader.coordinate}
      </div>
      
      {/* Name */}
      <div className="shader-name">{shader.name}</div>
      
      {/* Category Tag */}
      <div className="category-tag">{shader.category}</div>
      
      {/* Stats Row */}
      <div className="stats-row">
        {shader.playCount > 0 && (
          <span className="play-count">▶ {shader.playCount}</span>
        )}
      </div>
      
      {/* Rating */}
      <div 
        className="rating-wrapper"
        onMouseEnter={() => setShowRating(true)}
        onMouseLeave={() => setShowRating(false)}
      >
        <ShaderStarRating
          shaderId={shader.id}
          stars={shader.stars}
          ratingCount={shader.ratingCount}
          onRate={onRate}
          size="small"
          readonly={!showRating && shader.ratingCount > 0}
        />
      </div>
      
      {/* Tags */}
      <div className="tags-row">
        {shader.tags.slice(0, 3).map(tag => (
          <span key={tag} className="tag">{tag}</span>
        ))}
      </div>
    </div>
  );
};

export default ShaderBrowserWithRatings;
