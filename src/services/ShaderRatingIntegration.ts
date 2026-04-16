// ═══════════════════════════════════════════════════════════════════════════════
//  ShaderRatingIntegration.ts
//  Connects coordinate-based menus with Storage Manager star ratings
// ═══════════════════════════════════════════════════════════════════════════════

import shaderCoordinates from '../shader_coordinates.json';
import { STORAGE_API_URL } from '../config/appConfig';

const STORAGE_MANAGER_URL = STORAGE_API_URL;

// ═══════════════════════════════════════════════════════════════════════════════
//  Types
// ═══════════════════════════════════════════════════════════════════════════════

interface ShaderCoordData {
  coordinate: number;
  name: string;
  category: string;
  features: string[];
  tags: string[];
}

interface ShaderRating {
  id: string;
  stars: number;
  rating_count: number;
  play_count?: number;
  description?: string;
  author?: string;
  date?: string;
}

export interface EnrichedShader {
  id: string;
  coordinate: number;
  name: string;
  category: string;
  stars: number;
  ratingCount: number;
  playCount: number;
  features: string[];
  tags: string[];
  zone: string;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Rating Service
// ═══════════════════════════════════════════════════════════════════════════════

export class ShaderRatingService {
  private cache: Map<string, ShaderRating> = new Map();
  private readonly cacheDuration = 5 * 60 * 1000; // 5 minutes
  private lastFetch: number = 0;

  /**
   * Fetch all shader ratings from Storage Manager
   */
  async fetchAllRatings(): Promise<ShaderRating[]> {
    try {
      const response = await fetch(`${STORAGE_MANAGER_URL}/api/shaders?sort_by=rating`);
      if (!response.ok) throw new Error('Failed to fetch ratings');
      const ratings: ShaderRating[] = await response.json();
      
      // Update cache
      ratings.forEach(r => this.cache.set(r.id, r));
      this.lastFetch = Date.now();
      
      return ratings;
    } catch (error) {
      console.error('ShaderRatingService.fetchAllRatings:', error);
      return [];
    }
  }

  /**
   * Get rating for specific shader (from cache or fetch)
   */
  async getRating(shaderId: string): Promise<ShaderRating | null> {
    // Check cache freshness
    if (Date.now() - this.lastFetch > this.cacheDuration) {
      await this.fetchAllRatings();
    }
    
    return this.cache.get(shaderId) || null;
  }

  /**
   * Submit a star rating
   */
  async rateShader(shaderId: string, stars: number): Promise<ShaderRating | null> {
    try {
      const formData = new FormData();
      formData.append('stars', stars.toString());
      
      const response = await fetch(
        `${STORAGE_MANAGER_URL}/api/shaders/${shaderId}/rate`,
        { method: 'POST', body: formData }
      );
      
      if (!response.ok) throw new Error('Failed to submit rating');
      const updated = await response.json();

      // Update the individual cache entry and invalidate the list timestamp so
      // the next enrichWithRatings() / getRating() call fetches fresh data.
      this.cache.set(shaderId, updated);
      this.lastFetch = 0;

      return updated;
    } catch (error) {
      console.error('ShaderRatingService.rateShader:', error);
      return null;
    }
  }

  /**
   * Enrich coordinate data with ratings
   */
  async enrichWithRatings(): Promise<EnrichedShader[]> {
    const ratings = await this.fetchAllRatings();
    const ratingMap = new Map(ratings.map(r => [r.id, r]));
    
    return Object.entries(shaderCoordinates).map(([id, coordData]) => {
      const rating = ratingMap.get(id);
      const coord = (coordData as ShaderCoordData).coordinate;
      
      return {
        id,
        coordinate: coord,
        name: (coordData as ShaderCoordData).name,
        category: (coordData as ShaderCoordData).category,
        stars: rating?.stars || 0,
        ratingCount: rating?.rating_count || 0,
        playCount: rating?.play_count || 0,
        features: (coordData as ShaderCoordData).features || [],
        tags: (coordData as ShaderCoordData).tags || [],
        zone: this.getZoneFromCoordinate(coord),
      };
    });
  }

  private getZoneFromCoordinate(coord: number): string {
    if (coord < 100) return 'ambient';
    if (coord < 250) return 'organic';
    if (coord < 400) return 'interactive';
    if (coord < 550) return 'artistic';
    if (coord < 700) return 'visual-fx';
    if (coord < 850) return 'retro';
    return 'extreme';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Menu Generators with Ratings
// ═══════════════════════════════════════════════════════════════════════════════

export interface MenuGroup {
  label: string;
  shaders: EnrichedShader[];
}

export class CoordinateMenuBuilder {
  constructor(private shaders: EnrichedShader[]) {}

  /**
   * Build menu by visual zones (coordinates 0-1000)
   */
  buildByZone(): MenuGroup[] {
    const zones = [
      { label: '🌊 Ambient', min: 0, max: 100, color: '#1a5276' },
      { label: '🌿 Organic', min: 100, max: 250, color: '#1e8449' },
      { label: '👆 Interactive', min: 250, max: 400, color: '#2874a6' },
      { label: '🎨 Artistic', min: 400, max: 550, color: '#8e44ad' },
      { label: '✨ Visual FX', min: 550, max: 700, color: '#c0392b' },
      { label: '📺 Retro', min: 700, max: 850, color: '#d35400' },
      { label: '🌀 Extreme', min: 850, max: 1000, color: '#7d3c98' },
    ];

    return zones.map(zone => ({
      label: zone.label,
      shaders: this.shaders
        .filter(s => s.coordinate >= zone.min && s.coordinate < zone.max)
        .sort((a, b) => b.stars - a.stars), // Sort by rating within zone
    })).filter(g => g.shaders.length > 0);
  }

  /**
   * Build menu by star rating tiers
   */
  buildByRating(): MenuGroup[] {
    return [
      {
        label: '⭐⭐⭐⭐⭐ Top Rated (4.5+)',
        shaders: this.shaders.filter(s => s.stars >= 4.5).sort((a, b) => b.stars - a.stars),
      },
      {
        label: '⭐⭐⭐⭐ Highly Rated (4.0+)',
        shaders: this.shaders.filter(s => s.stars >= 4.0 && s.stars < 4.5).sort((a, b) => b.stars - a.stars),
      },
      {
        label: '⭐⭐⭐ Good (3.0+)',
        shaders: this.shaders.filter(s => s.stars >= 3.0 && s.stars < 4.0).sort((a, b) => b.stars - a.stars),
      },
      {
        label: '🆕 Unrated',
        shaders: this.shaders.filter(s => s.ratingCount === 0).sort((a, b) => a.coordinate - b.coordinate),
      },
    ].filter(g => g.shaders.length > 0);
  }

  /**
   * Build menu by popularity (play count)
   */
  buildByPopularity(): MenuGroup[] {
    const sorted = [...this.shaders].sort((a, b) => b.playCount - a.playCount);
    
    return [
      { label: '🔥 Hot (1000+ plays)', shaders: sorted.filter(s => s.playCount >= 1000) },
      { label: '💎 Popular (500+ plays)', shaders: sorted.filter(s => s.playCount >= 500 && s.playCount < 1000) },
      { label: '📈 Rising (100+ plays)', shaders: sorted.filter(s => s.playCount >= 100 && s.playCount < 500) },
      { label: '🌱 New', shaders: sorted.filter(s => s.playCount < 100) },
    ].filter(g => g.shaders.length > 0);
  }

  /**
   * Build personalized "For You" menu
   */
  buildForYou(userHistory: string[]): MenuGroup[] {
    // Get coordinates of recently used shaders
    const recentCoords = userHistory
      .map(id => this.shaders.find(s => s.id === id)?.coordinate)
      .filter((c): c is number => c !== undefined);
    
    const avgCoord = recentCoords.reduce((a, b) => a + b, 0) / recentCoords.length || 500;
    
    // Find similar shaders (±100 coordinate units)
    const similar = this.shaders.filter(s => 
      Math.abs(s.coordinate - avgCoord) < 100 && 
      !userHistory.includes(s.id)
    ).sort((a, b) => b.stars - a.stars);

    return [
      { label: '🎯 Similar to Your Taste', shaders: similar.slice(0, 20) },
      { label: '🔝 Top Rated Near You', shaders: similar.filter(s => s.stars >= 4).slice(0, 10) },
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  React Hook for Shader Ratings
// ═══════════════════════════════════════════════════════════════════════════════

import { useState, useEffect, useCallback } from 'react';

export function useShaderRatings() {
  const [service] = useState(() => new ShaderRatingService());
  const [shaders, setShaders] = useState<EnrichedShader[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    service.enrichWithRatings().then(data => {
      setShaders(data);
      setLoading(false);
    });
  }, [service]);

  const rateShader = useCallback(async (id: string, stars: number) => {
    const updated = await service.rateShader(id, stars);
    if (updated) {
      setShaders(prev => prev.map(s => 
        s.id === id 
          ? { ...s, stars: updated.stars, ratingCount: updated.rating_count }
          : s
      ));
    }
    return updated;
  }, [service]);

  const menuBuilder = new CoordinateMenuBuilder(shaders);

  return {
    shaders,
    loading,
    rateShader,
    menus: {
      byZone: menuBuilder.buildByZone(),
      byRating: menuBuilder.buildByRating(),
      byPopularity: menuBuilder.buildByPopularity(),
    },
  };
}

export default ShaderRatingService;
