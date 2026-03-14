// ═══════════════════════════════════════════════════════════════════════════════
//  ShaderCoordinateMenu.tsx
//  Coordinate-based shader selection system with keyboard navigation
//  
//  Core concept: Every shader has a persistent coordinate (0-1000).
//  Multiple menus provide different "lenses" on the same coordinate space.
//  Keyboard shortcut: Type any number to jump directly to that shader.
// ═══════════════════════════════════════════════════════════════════════════════

import React, { useState, useMemo, useCallback, useEffect, useRef } from 'react';
import './ShaderCoordinateMenu.css';

// ═══════════════════════════════════════════════════════════════════════════════
//  Types
// ═══════════════════════════════════════════════════════════════════════════════

interface ShaderCoord {
  id: string;
  name: string;
  coordinate: number;      // 0-1000, persistent
  category: string;
  features: string[];
  tags: string[];
}

interface MenuDefinition {
  id: string;
  label: string;
  type: 'spectrum' | 'grouped' | 'list';
  // For spectrum: define zones
  zones?: { label: string; min: number; max: number; color: string }[];
  // For grouped: define groupings
  groups?: { label: string; filter: (s: ShaderCoord) => boolean }[];
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Menu Definitions (The "Lenses")
// ═══════════════════════════════════════════════════════════════════════════════

const MENUS: MenuDefinition[] = [
  {
    id: 'by-visual-tempo',
    label: 'By Visual Tempo',
    type: 'spectrum',
    zones: [
      { label: '🌊 Ambient', min: 0, max: 100, color: '#1a5276' },
      { label: '🌿 Organic', min: 100, max: 250, color: '#1e8449' },
      { label: '👆 Interactive', min: 250, max: 400, color: '#2874a6' },
      { label: '🎨 Artistic', min: 400, max: 550, color: '#8e44ad' },
      { label: '✨ Visual FX', min: 550, max: 700, color: '#c0392b' },
      { label: '📺 Retro/Digital', min: 700, max: 850, color: '#d35400' },
      { label: '🌀 Extreme', min: 850, max: 1000, color: '#7d3c98' },
    ]
  },
  {
    id: 'by-input',
    label: 'By Input Type',
    type: 'grouped',
    groups: [
      { label: 'Standalone (Generative)', filter: s => s.category === 'generative' },
      { label: 'Mouse Driven', filter: s => s.features.includes('mouse-driven') },
      { label: 'Depth Aware', filter: s => s.features.includes('depth-aware') },
      { label: 'Audio Reactive', filter: s => s.features.includes('audio-reactive') },
      { label: 'Time Based', filter: s => !s.features.includes('mouse-driven') && s.category !== 'generative' },
    ]
  },
  {
    id: 'by-category',
    label: 'By Category',
    type: 'grouped',
    groups: [
      { label: 'Liquid & Fluid', filter: s => s.category === 'liquid-effects' },
      { label: 'Lighting & Glow', filter: s => s.category === 'lighting-effects' },
      { label: 'Distortion & Warp', filter: s => s.category === 'distortion' },
      { label: 'Glitch & Retro', filter: s => s.category === 'retro-glitch' },
      { label: 'Geometric', filter: s => s.category === 'geometric' },
      { label: 'Simulation', filter: s => s.category === 'simulation' },
      { label: 'Image Processing', filter: s => s.category === 'image' },
    ]
  },
  {
    id: 'numeric-index',
    label: 'By Number (0-1000)',
    type: 'list',
  }
];

// ═══════════════════════════════════════════════════════════════════════════════
//  Component
// ═══════════════════════════════════════════════════════════════════════════════

interface ShaderCoordinateMenuProps {
  shaders: ShaderCoord[];
  selectedId: string | null;
  onSelect: (id: string) => void;
  recentIds?: string[];
  favoriteIds?: string[];
  enableKeyboardNav?: boolean; // NEW: Enable number typing to jump
}

export const ShaderCoordinateMenu: React.FC<ShaderCoordinateMenuProps> = ({
  shaders,
  selectedId,
  onSelect,
  recentIds = [],
  favoriteIds = [],
  enableKeyboardNav = true,
}) => {
  const [activeMenuId, setActiveMenuId] = useState<string>('by-visual-tempo');
  const [searchQuery, setSearchQuery] = useState('');
  const [hoveredCoord, setHoveredCoord] = useState<number | null>(null);
  
  // NEW: Keyboard navigation state
  const [typedNumber, setTypedNumber] = useState<string>('');
  const [showNumberOverlay, setShowNumberOverlay] = useState(false);
  const numberTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const menuContentRef = useRef<HTMLDivElement>(null);

  const activeMenu = MENUS.find(m => m.id === activeMenuId) || MENUS[0];

  // NEW: Create a map for O(1) coordinate -> shader lookup
  const coordToShaderMap = useMemo(() => {
    const map = new Map<number, ShaderCoord>();
    shaders.forEach(s => map.set(s.coordinate, s));
    return map;
  }, [shaders]);

  // NEW: Find closest shader to a coordinate
  const findClosestShader = useCallback((targetCoord: number): ShaderCoord | null => {
    // First try exact match
    if (coordToShaderMap.has(targetCoord)) {
      return coordToShaderMap.get(targetCoord)!;
    }
    
    // Find closest by binary search
    let closest = shaders[0];
    let minDiff = Math.abs(shaders[0].coordinate - targetCoord);
    
    for (const shader of shaders) {
      const diff = Math.abs(shader.coordinate - targetCoord);
      if (diff < minDiff) {
        minDiff = diff;
        closest = shader;
      }
    }
    
    return closest || null;
  }, [shaders, coordToShaderMap]);

  // NEW: Keyboard navigation effect
  useEffect(() => {
    if (!enableKeyboardNav) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      // Ignore if typing in an input
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
        return;
      }

      const key = e.key;

      // Number keys 0-9
      if (/^[0-9]$/.test(key)) {
        e.preventDefault();
        
        // Clear existing timeout
        if (numberTimeoutRef.current) {
          clearTimeout(numberTimeoutRef.current);
        }

        // Append digit
        const newNumber = typedNumber + key;
        setTypedNumber(newNumber);
        setShowNumberOverlay(true);

        // Set timeout to execute jump
        numberTimeoutRef.current = setTimeout(() => {
          const coord = parseInt(newNumber, 10);
          if (!isNaN(coord) && coord >= 0 && coord <= 1000) {
            const shader = findClosestShader(coord);
            if (shader) {
              onSelect(shader.id);
              
              // Scroll to shader in the list
              const element = document.getElementById(`shader-card-${shader.id}`);
              if (element) {
                element.scrollIntoView({ behavior: 'smooth', block: 'center' });
              }
            }
          }
          setTypedNumber('');
          setShowNumberOverlay(false);
        }, 800); // 800ms to type full number

      } else if (key === 'Escape') {
        // Cancel number entry
        if (numberTimeoutRef.current) {
          clearTimeout(numberTimeoutRef.current);
        }
        setTypedNumber('');
        setShowNumberOverlay(false);
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      if (numberTimeoutRef.current) {
        clearTimeout(numberTimeoutRef.current);
      }
    };
  }, [enableKeyboardNav, typedNumber, findClosestShader, onSelect]);

  // Sort shaders by coordinate for consistent ordering
  const sortedShaders = useMemo(() => {
    return [...shaders].sort((a, b) => a.coordinate - b.coordinate);
  }, [shaders]);

  // Filter by search
  const filteredShaders = useMemo(() => {
    if (!searchQuery) return sortedShaders;
    const q = searchQuery.toLowerCase();
    return sortedShaders.filter(s => 
      s.name.toLowerCase().includes(q) ||
      s.id.toLowerCase().includes(q) ||
      s.tags.some(t => t.toLowerCase().includes(q))
    );
  }, [sortedShaders, searchQuery]);

  // Find neighbors for "more like this"
  const getNeighbors = useCallback((coord: number, range: number = 50) => {
    return sortedShaders.filter(s => 
      s.coordinate >= coord - range && 
      s.coordinate <= coord + range
    );
  }, [sortedShaders]);

  // Render different menu types
  const renderMenu = () => {
    switch (activeMenu.type) {
      case 'spectrum':
        return renderSpectrumMenu();
      case 'grouped':
        return renderGroupedMenu();
      case 'list':
        return renderNumericList();
      default:
        return renderSpectrumMenu();
    }
  };

  // ═══════════════════════════════════════════════════════════════════════════
  //  Spectrum Menu (Visual Tempo)
  // ═══════════════════════════════════════════════════════════════════════════
  const renderSpectrumMenu = () => {
    const zones = activeMenu.zones!;
    
    return (
      <div className="spectrum-menu">
        {/* The Spectrum Bar */}
        <div className="spectrum-bar">
          {zones.map(zone => {
            const width = ((zone.max - zone.min) / 1000) * 100;
            const zoneShaders = filteredShaders.filter(
              s => s.coordinate >= zone.min && s.coordinate < zone.max
            );
            return (
              <div
                key={zone.label}
                className="spectrum-zone"
                style={{ 
                  width: `${width}%`, 
                  backgroundColor: zone.color,
                  opacity: zoneShaders.length > 0 ? 1 : 0.3
                }}
                title={`${zone.label}: ${zoneShaders.length} shaders`}
              >
                <span className="zone-label">{zone.label}</span>
                <span className="zone-count">{zoneShaders.length}</span>
              </div>
            );
          })}
        </div>

        {/* Selected shader indicator on spectrum */}
        {selectedId && (
          <div className="spectrum-cursor">
            {(() => {
              const shader = shaders.find(s => s.id === selectedId);
              if (!shader) return null;
              const left = (shader.coordinate / 1000) * 100;
              return (
                <div 
                  className="cursor-marker"
                  style={{ left: `${left}%` }}
                  title={`#${shader.coordinate}: ${shader.name}`}
                >
                  ▲
                </div>
              );
            })()}
          </div>
        )}

        {/* Shader grid by zone */}
        <div className="zone-grids">
          {zones.map(zone => {
            const zoneShaders = filteredShaders.filter(
              s => s.coordinate >= zone.min && s.coordinate < zone.max
            );
            if (zoneShaders.length === 0) return null;
            
            return (
              <div key={zone.label} className="zone-section">
                <h3 style={{ color: zone.color }}>
                  {zone.label} 
                  <span className="coord-range">({zone.min}-{zone.max})</span>
                </h3>
                <div className="shader-grid">
                  {zoneShaders.map(shader => (
                    <ShaderCard
                      key={shader.id}
                      shader={shader}
                      isSelected={selectedId === shader.id}
                      isFavorite={favoriteIds.includes(shader.id)}
                      isRecent={recentIds.includes(shader.id)}
                      onClick={() => onSelect(shader.id)}
                      onHover={setHoveredCoord}
                    />
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    );
  };

  // ═══════════════════════════════════════════════════════════════════════════
  //  Grouped Menu (By Input/Category)
  // ═══════════════════════════════════════════════════════════════════════════
  const renderGroupedMenu = () => {
    const groups = activeMenu.groups!;
    
    return (
      <div className="grouped-menu">
        {groups.map(group => {
          const groupShaders = filteredShaders.filter(group.filter);
          if (groupShaders.length === 0) return null;
          
          // Sort by coordinate within group
          const sorted = [...groupShaders].sort((a, b) => a.coordinate - b.coordinate);
          
          return (
            <div key={group.label} className="group-section">
              <h3>
                {group.label}
                <span className="group-count">{groupShaders.length}</span>
              </h3>
              <div className="shader-grid">
                {sorted.map(shader => (
                  <ShaderCard
                    key={shader.id}
                    shader={shader}
                    isSelected={selectedId === shader.id}
                    isFavorite={favoriteIds.includes(shader.id)}
                    isRecent={recentIds.includes(shader.id)}
                    onClick={() => onSelect(shader.id)}
                    onHover={setHoveredCoord}
                    showCoordinate={true}
                  />
                ))}
              </div>
            </div>
          );
        })}
      </div>
    );
  };

  // ═══════════════════════════════════════════════════════════════════════════
  //  Numeric List (0-1000)
  // ═══════════════════════════════════════════════════════════════════════════
  const renderNumericList = () => {
    // Chunk into ranges of 100
    const chunks = [];
    for (let i = 0; i < 1000; i += 100) {
      const chunkShaders = filteredShaders.filter(
        s => s.coordinate >= i && s.coordinate < i + 100
      );
      if (chunkShaders.length > 0) {
        chunks.push({ start: i, end: i + 99, shaders: chunkShaders });
      }
    }

    return (
      <div className="numeric-menu">
        <div className="numeric-header">
          <span>Coordinate</span>
          <span>Name</span>
          <span>Category</span>
          <span>Tags</span>
        </div>
        {chunks.map(chunk => (
          <div key={chunk.start} className="numeric-chunk">
            <div className="chunk-header">{chunk.start}-{chunk.end}</div>
            {chunk.shaders.map(shader => (
              <div
                key={shader.id}
                className={`numeric-row ${selectedId === shader.id ? 'selected' : ''}`}
                onClick={() => onSelect(shader.id)}
                onMouseEnter={() => setHoveredCoord(shader.coordinate)}
                onMouseLeave={() => setHoveredCoord(null)}
              >
                <span className="coord-cell">{shader.coordinate}</span>
                <span className="name-cell">{shader.name}</span>
                <span className="category-cell">{shader.category}</span>
                <span className="tags-cell">{shader.tags.slice(0, 3).join(', ')}</span>
              </div>
            ))}
          </div>
        ))}
      </div>
    );
  };

  // ═══════════════════════════════════════════════════════════════════════════
  //  Main Render
  // ═══════════════════════════════════════════════════════════════════════════
  return (
    <div className="shader-coordinate-menu">
      {/* NEW: Number Input Overlay */}
      {showNumberOverlay && (
        <div className="number-overlay">
          <div className="number-display">
            <span className="number-typed">{typedNumber}</span>
            <span className="number-hint">Press numbers 0-9, ESC to cancel</span>
            {typedNumber && (() => {
              const coord = parseInt(typedNumber, 10);
              const shader = findClosestShader(coord);
              return shader ? (
                <span className="number-preview">
                  → #{shader.coordinate} {shader.name}
                </span>
              ) : null;
            })()}
          </div>
        </div>
      )}

      {/* Header */}
      <div className="menu-header">
        <h2>Shader Library <span className="shader-count">({shaders.length})</span></h2>
        
        {/* Search */}
        <input
          type="text"
          placeholder="Search shaders... (or type numbers to jump)"
          value={searchQuery}
          onChange={e => setSearchQuery(e.target.value)}
          className="search-input"
        />
      </div>

      {/* Menu Tabs */}
      <div className="menu-tabs">
        {MENUS.map(menu => (
          <button
            key={menu.id}
            className={`menu-tab ${activeMenuId === menu.id ? 'active' : ''}`}
            onClick={() => setActiveMenuId(menu.id)}
          >
            {menu.label}
          </button>
        ))}
      </div>

      {/* Main Content */}
      <div className="menu-content">
        {renderMenu()}
      </div>

      {/* Footer: More Like This */}
      {hoveredCoord && (
        <div className="similar-shaders">
          <h4>Similar shaders (±50 coordinate units):</h4>
          <div className="similar-list">
            {getNeighbors(hoveredCoord).slice(0, 5).map(s => (
              <span key={s.id} className="similar-chip">{s.name}</span>
            ))}
          </div>
        </div>
      )}

      {/* Selected shader info */}
      {selectedId && (
        <div className="selected-info">
          {(() => {
            const shader = shaders.find(s => s.id === selectedId);
            if (!shader) return null;
            return (
              <>
                <span className="info-coord">#{shader.coordinate}</span>
                <span className="info-name">{shader.name}</span>
                <span className="info-category">{shader.category}</span>
              </>
            );
          })()}
        </div>
      )}
    </div>
  );
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Shader Card Component
// ═══════════════════════════════════════════════════════════════════════════════

interface ShaderCardProps {
  shader: ShaderCoord;
  isSelected: boolean;
  isFavorite: boolean;
  isRecent: boolean;
  onClick: () => void;
  onHover: (coord: number | null) => void;
  showCoordinate?: boolean;
}

const ShaderCard: React.FC<ShaderCardProps> = ({
  shader,
  isSelected,
  isFavorite,
  isRecent,
  onClick,
  onHover,
  showCoordinate = false,
}) => {
  return (
    <div
      id={`shader-card-${shader.id}`}
      className={`shader-card ${isSelected ? 'selected' : ''} ${isFavorite ? 'favorite' : ''}`}
      onClick={onClick}
      onMouseEnter={() => onHover(shader.coordinate)}
      onMouseLeave={() => onHover(null)}
      title={`#${shader.coordinate}: ${shader.tags.join(', ')}`}
    >
      {isFavorite && <span className="badge fav">★</span>}
      {isRecent && <span className="badge recent">◷</span>}
      {showCoordinate && <span className="coord-badge">#{shader.coordinate}</span>}
      <span className="shader-name">{shader.name}</span>
      <span className="shader-tags">{shader.tags.slice(0, 2).join(', ')}</span>
    </div>
  );
};

export default ShaderCoordinateMenu;
