import {
  saveFavorite,
  loadFavorites,
  deleteFavorite,
  clearFavorites,
  VariationFavorite,
} from './variationFavorites';
import { SharedChain } from './layerChainShare';

const CHAIN_A: SharedChain = {
  v: 1,
  slots: [
    { shaderId: 'liquid-a', params: { zoomParam1: 0.7 } },
    { shaderId: 'distort-a' },
  ],
};

const CHAIN_B: SharedChain = {
  v: 1,
  slots: [{ shaderId: 'generative-a' }],
};

describe('variationFavorites', () => {
  beforeEach(() => {
    clearFavorites();
  });

  afterEach(() => {
    clearFavorites();
  });

  it('saves a favorite and prepends it', () => {
    const saved = saveFavorite({ name: 'First', chain: CHAIN_A, seed: 'abc' });
    expect(saved.name).toBe('First');
    expect(saved.chain).toEqual(CHAIN_A);
    expect(saved.seed).toBe('abc');
    expect(typeof saved.id).toBe('string');
    expect(typeof saved.timestamp).toBe('number');

    const favorites = loadFavorites();
    expect(favorites).toHaveLength(1);
    expect(favorites[0].id).toBe(saved.id);
  });

  it('survives a serialize → localStorage → deserialize cycle', () => {
    saveFavorite({ name: 'Round-trip', chain: CHAIN_B, seed: '123' });

    const raw = localStorage.getItem('variation_favorites');
    expect(raw).toBeTruthy();

    // Simulate a fresh load by clearing the in-memory cache (none here) and re-reading.
    const favorites = loadFavorites();
    expect(favorites).toHaveLength(1);
    expect(favorites[0].name).toBe('Round-trip');
    expect(favorites[0].chain).toEqual(CHAIN_B);
    expect(favorites[0].seed).toBe('123');
  });

  it('enforces the max-N cap (50)', () => {
    for (let i = 0; i < 52; i++) {
      saveFavorite({ name: `Favorite ${i}`, chain: CHAIN_A });
    }
    const favorites = loadFavorites();
    expect(favorites).toHaveLength(50);
    expect(favorites[0].name).toBe('Favorite 51');
    expect(favorites[49].name).toBe('Favorite 2');
  });

  it('deletes only the targeted favorite', () => {
    const a = saveFavorite({ name: 'A', chain: CHAIN_A });
    const b = saveFavorite({ name: 'B', chain: CHAIN_B });
    const c = saveFavorite({ name: 'C', chain: CHAIN_A });

    deleteFavorite(b.id);

    const favorites = loadFavorites();
    expect(favorites.map(f => f.id)).toEqual([c.id, a.id]);
  });

  it('clearFavorites empties storage', () => {
    saveFavorite({ name: 'A', chain: CHAIN_A });
    expect(loadFavorites()).toHaveLength(1);
    clearFavorites();
    expect(loadFavorites()).toHaveLength(0);
    expect(localStorage.getItem('variation_favorites')).toBeNull();
  });

  it('drops malformed entries during load', () => {
    const good: VariationFavorite = {
      id: 'good-id',
      name: 'Good',
      chain: CHAIN_A,
      timestamp: 1,
    };
    localStorage.setItem('variation_favorites', JSON.stringify([
      good,
      { id: 'bad', name: 'Bad' }, // missing chain
      null,
      { chain: { slots: [] } }, // missing id/name
    ]));

    const favorites = loadFavorites();
    expect(favorites).toHaveLength(1);
    expect(favorites[0].id).toBe('good-id');
  });
});
