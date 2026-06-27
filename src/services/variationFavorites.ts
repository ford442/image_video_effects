// ═══════════════════════════════════════════════════════════════════════════════
//  variationFavorites.ts
//  Persist starred variation chains to localStorage.
//
//  Modeled on the vjHistory.ts / vjPresets.ts pattern:
//    - prepend newest, cap at MAX_FAVORITES
//    - safe parse with [] fallback
//    - crypto.randomUUID for ids, Date.now for timestamps
// ═══════════════════════════════════════════════════════════════════════════════

import { SharedChain } from './layerChainShare';

export interface VariationFavorite {
  id: string;
  name: string;
  chain: SharedChain;
  seed?: string;
  timestamp: number;
}

const STORAGE_KEY = 'variation_favorites';
const MAX_FAVORITES = 50;

function generateId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  // Fallback for test environments without crypto (e.g. jsdom/Node).
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

export function saveFavorite(
  entry: Omit<VariationFavorite, 'id' | 'timestamp'>
): VariationFavorite {
  const favorites = loadFavorites();
  const newFavorite: VariationFavorite = {
    ...entry,
    id: generateId(),
    timestamp: Date.now(),
  };
  favorites.unshift(newFavorite);
  if (favorites.length > MAX_FAVORITES) {
    favorites.length = MAX_FAVORITES;
  }
  localStorage.setItem(STORAGE_KEY, JSON.stringify(favorites));
  return newFavorite;
}

function isValidFavorite(value: unknown): value is VariationFavorite {
  if (!value || typeof value !== 'object') return false;
  const fav = value as Record<string, unknown>;
  if (typeof fav.id !== 'string') return false;
  if (typeof fav.name !== 'string') return false;
  if (!fav.chain || typeof fav.chain !== 'object') return false;
  const chain = fav.chain as Record<string, unknown>;
  if (!Array.isArray(chain.slots)) return false;
  return true;
}

export function loadFavorites(): VariationFavorite[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(isValidFavorite);
  } catch {
    return [];
  }
}

export function clearFavorites(): void {
  localStorage.removeItem(STORAGE_KEY);
}

export function deleteFavorite(id: string): void {
  const favorites = loadFavorites().filter(f => f.id !== id);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(favorites));
}
