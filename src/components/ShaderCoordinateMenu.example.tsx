// ═══════════════════════════════════════════════════════════════════════════════
//  ShaderCoordinateMenu - Usage Example
//  
//  This shows how to integrate the coordinate-based menu into the existing App.tsx
// ═══════════════════════════════════════════════════════════════════════════════

import React, { useState, useEffect } from 'react';
import { ShaderCoordinateMenu } from './components/ShaderCoordinateMenu';
import shaderCoordinates from '../shader_coordinates.json';

// ═══════════════════════════════════════════════════════════════════════════════
//  Data Preparation
// ═══════════════════════════════════════════════════════════════════════════════

// Convert the coordinate JSON to the format expected by the component
const prepareShaderData = () => {
  return Object.entries(shaderCoordinates).map(([id, data]) => ({
    id,
    name: data.name,
    coordinate: data.coordinate,
    category: data.category,
    features: data.features || [],
    tags: data.tags || [],
  }));
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Integration Example
// ═══════════════════════════════════════════════════════════════════════════════

interface ShaderSelectorProps {
  currentShaderId: string | null;
  onShaderSelect: (id: string) => void;
}

export const ShaderSelector: React.FC<ShaderSelectorProps> = ({
  currentShaderId,
  onShaderSelect,
}) => {
  const [shaders] = useState(() => prepareShaderData());
  const [recentIds, setRecentIds] = useState<string[]>(() => {
    // Load from localStorage
    const saved = localStorage.getItem('recentShaders');
    return saved ? JSON.parse(saved) : [];
  });
  const [favoriteIds, setFavoriteIds] = useState<string[]>(() => {
    const saved = localStorage.getItem('favoriteShaders');
    return saved ? JSON.parse(saved) : [];
  });

  // Track recent selections
  const handleSelect = (id: string) => {
    onShaderSelect(id);
    
    // Update recent list (keep last 10)
    setRecentIds(prev => {
      const filtered = prev.filter(r => r !== id);
      const updated = [id, ...filtered].slice(0, 10);
      localStorage.setItem('recentShaders', JSON.stringify(updated));
      return updated;
    });
  };

  // Toggle favorite
  const toggleFavorite = (id: string) => {
    setFavoriteIds(prev => {
      const isFav = prev.includes(id);
      const updated = isFav 
        ? prev.filter(f => f !== id)
        : [...prev, id];
      localStorage.setItem('favoriteShaders', JSON.stringify(updated));
      return updated;
    });
  };

  return (
    <ShaderCoordinateMenu
      shaders={shaders}
      selectedId={currentShaderId}
      onSelect={handleSelect}
      recentIds={recentIds}
      favoriteIds={favoriteIds}
    />
  );
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Direct URL Navigation by Coordinate
// ═══════════════════════════════════════════════════════════════════════════════

// Users can bookmark/share shaders by coordinate:
// http://localhost:3000#shader=coord:917

export const navigateByCoordinate = (coordinate: number): string | null => {
  const entry = Object.entries(shaderCoordinates).find(
    ([, data]) => data.coordinate === coordinate
  );
  return entry ? entry[0] : null;
};

// ═══════════════════════════════════════════════════════════════════════════════
//  AI VJ Integration
// ═══════════════════════════════════════════════════════════════════════════════

// The coordinate system enables smarter shader stacking:
// - Adjacent coordinates (±50) create smooth transitions
// - Complementary coordinates (±500) create contrast

export const findComplementaryShaders = (
  baseCoord: number, 
  range: number = 50,
  excludeId?: string
): string[] => {
  return Object.entries(shaderCoordinates)
    .filter(([id, data]) => {
      if (excludeId && id === excludeId) return false;
      const diff = Math.abs(data.coordinate - baseCoord);
      return diff <= range;
    })
    .map(([id]) => id);
};

// Example: Find shaders "opposite" on the spectrum for contrast
export const findOppositeShaders = (baseCoord: number): string[] => {
  const oppositeCoord = 1000 - baseCoord;
  return findComplementaryShaders(oppositeCoord, 100);
};

// ═══════════════════════════════════════════════════════════════════════════════
//  Migration from old category-based system
// ═══════════════════════════════════════════════════════════════════════════════

// Old: Drop-down by category
// New: Coordinate spectrum with multiple menu lenses

// The coordinate is stored in shader_coordinates.json
// This file should be:
// 1. Generated once during build (via assign_coordinates.py)
// 2. Imported by the frontend
// 3. Used to sort/filter in all menus

export default ShaderSelector;
