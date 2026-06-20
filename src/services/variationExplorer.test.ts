import {
  generateChainVariations,
  generateChainVariationChains,
  VariationOptions,
} from './variationExplorer';
import { SharedChain, MAX_SHARED_SLOTS, expandSharedChain } from './layerChainShare';
import { CatalogShader, CatalogParam } from './shaderCatalog';
import { SlotParams } from '../renderer/types';

function param(id: string, overrides: Partial<CatalogParam> = {}): CatalogParam {
  return {
    id,
    name: id,
    default: 0.5,
    min: 0,
    max: 1,
    step: 0.01,
    ...overrides,
  };
}

function shader(
  id: string,
  category: string,
  params: CatalogParam[]
): CatalogShader {
  return {
    id,
    name: id,
    category,
    tags: [],
    description: '',
    params,
    searchText: `${id} ${category}`,
  };
}

const CATALOG: CatalogShader[] = [
  shader('liquid-a', 'liquid-effects', [
    param('speed', { min: 0, max: 2, default: 0.5 }),
    param('scale', { min: 0.1, max: 0.9, default: 0.5 }),
    param('warp', { min: -1, max: 1, default: 0 }),
    param('hue', { min: 0, max: 360, default: 180 }),
  ]),
  shader('liquid-b', 'liquid-effects', [
    param('tension', { min: 0, max: 1 }),
    param('gravity', { min: 0, max: 1 }),
  ]),
  shader('liquid-c', 'liquid-effects', [
    param('ripple', { min: 0, max: 1 }),
  ]),
  shader('distort-a', 'distortion', [
    param('amount', { min: 0, max: 1 }),
    param('frequency', { min: 1, max: 10 }),
  ]),
  shader('distort-b', 'distortion', [
    param('strength', { min: 0, max: 1 }),
  ]),
  shader('generative-a', 'generative', [
    param('density', { min: 0, max: 100 }),
  ]),
];

const BASE_CHAIN: SharedChain = {
  v: 1,
  slots: [
    { shaderId: 'liquid-a', params: { zoomParam1: 0.7, zoomParam2: 0.6 } },
    { shaderId: 'distort-a', mode: 'parallel' },
    { shaderId: null },
  ],
};

const defaultsLookup = (shaderId: string) => {
  const s = CATALOG.find(x => x.id === shaderId);
  if (!s) return undefined;
  const out: Partial<SlotParams> = {};
  s.params.forEach((p, i) => {
    if (i === 0) out.zoomParam1 = p.default;
    if (i === 1) out.zoomParam2 = p.default;
    if (i === 2) out.zoomParam3 = p.default;
    if (i === 3) out.zoomParam4 = p.default;
  });
  return out;
};

describe('variationExplorer', () => {
  it('returns exactly N variations', () => {
    const result = generateChainVariationChains(BASE_CHAIN, 8, CATALOG, {
      paramJitter: true,
      shaderSwap: 'none',
      seed: 'test',
    });
    expect(result).toHaveLength(8);
  });

  it('preserves the base slot count (clamped to MAX_SHARED_SLOTS)', () => {
    const result = generateChainVariationChains(BASE_CHAIN, 4, CATALOG, {
      paramJitter: true,
      shaderSwap: 'none',
      seed: 'slots',
    });
    for (const chain of result) {
      expect(chain.slots).toHaveLength(BASE_CHAIN.slots.length);
    }
  });

  it('keeps shader ids unchanged when shaderSwap is none', () => {
    const result = generateChainVariationChains(BASE_CHAIN, 10, CATALOG, {
      paramJitter: true,
      shaderSwap: 'none',
      seed: 'ids',
    });
    for (const chain of result) {
      expect(chain.slots.map(s => s.shaderId)).toEqual([
        'liquid-a',
        'distort-a',
        null,
      ]);
    }
  });

  it('preserves enabled / mode flags from the base chain', () => {
    const chain: SharedChain = {
      v: 1,
      slots: [
        { shaderId: 'liquid-a', enabled: false, mode: 'parallel' },
        { shaderId: 'distort-a' },
      ],
    };
    const result = generateChainVariations(chain, 3, CATALOG, {
      paramJitter: false,
      shaderSwap: 'none',
      seed: 'flags',
    });
    for (const variation of result) {
      const first = variation.chain.slots[0];
      expect(first.enabled).toBe(false);
      expect(first.mode).toBe('parallel');
    }
  });

  it('keeps randomized params within each catalog param [min, max]', () => {
    const result = generateChainVariations(BASE_CHAIN, 20, CATALOG, {
      paramJitter: true,
      shaderSwap: 'sameCategory',
      seed: 'ranges',
    });
    for (const variation of result) {
      const expanded = expandSharedChain(variation.chain, defaultsLookup);
      for (let i = 0; i < variation.chain.slots.length; i++) {
        const slot = variation.chain.slots[i];
        if (!slot.shaderId) continue;
        const shaderMeta = CATALOG.find(s => s.id === slot.shaderId)!;
        const params = expanded.slotParams[i];
        const orderedIds = shaderMeta.params.map(p => p.id);
        const values = [
          { key: 'zoomParam1', val: params.zoomParam1 },
          { key: 'zoomParam2', val: params.zoomParam2 },
          { key: 'zoomParam3', val: params.zoomParam3 },
          { key: 'zoomParam4', val: params.zoomParam4 },
        ];
        for (let pIndex = 0; pIndex < shaderMeta.params.length; pIndex++) {
          const catalogParam = shaderMeta.params[pIndex];
          const slotKey = values[pIndex].key as keyof SlotParams;
          const val = params[slotKey];
          expect(val).toBeGreaterThanOrEqual(catalogParam.min);
          expect(val).toBeLessThanOrEqual(catalogParam.max);
        }
      }
    }
  });

  it('sameCategory swap never picks a shader from a different category', () => {
    const result = generateChainVariationChains(BASE_CHAIN, 30, CATALOG, {
      paramJitter: false,
      shaderSwap: 'sameCategory',
      seed: 'category',
    });
    for (const chain of result) {
      for (const slot of chain.slots) {
        if (!slot.shaderId) continue;
        const original = BASE_CHAIN.slots.find(s => s.shaderId && CATALOG.find(c => c.id === s.shaderId)?.category === CATALOG.find(c => c.id === slot.shaderId)?.category);
        expect(original).toBeDefined();
      }
    }
  });

  it('is deterministic for the same seed', () => {
    const opts: VariationOptions = {
      paramJitter: true,
      shaderSwap: 'sameCategory',
      seed: 'deterministic',
    };
    const first = generateChainVariationChains(BASE_CHAIN, 6, CATALOG, opts);
    const second = generateChainVariationChains(BASE_CHAIN, 6, CATALOG, opts);
    expect(first).toEqual(second);
  });

  it('produces different variations for different seeds', () => {
    const a = generateChainVariationChains(
      BASE_CHAIN,
      6,
      CATALOG,
      { paramJitter: true, shaderSwap: 'sameCategory', seed: 'seed-a' }
    );
    const b = generateChainVariationChains(
      BASE_CHAIN,
      6,
      CATALOG,
      { paramJitter: true, shaderSwap: 'sameCategory', seed: 'seed-b' }
    );
    expect(a).not.toEqual(b);
  });

  it('returns an empty array for non-positive counts', () => {
    expect(
      generateChainVariationChains(BASE_CHAIN, 0, CATALOG, {
        paramJitter: true,
        shaderSwap: 'none',
      })
    ).toEqual([]);
    expect(
      generateChainVariationChains(BASE_CHAIN, -3, CATALOG, {
        paramJitter: true,
        shaderSwap: 'none',
      })
    ).toEqual([]);
  });

  it('respects MAX_SHARED_SLOTS when base chain is too long', () => {
    const big: SharedChain = {
      v: 1,
      slots: Array.from({ length: 10 }, (_, i) => ({
        shaderId: `slot-${i}`,
      })),
    };
    const result = generateChainVariationChains(big, 2, CATALOG, {
      paramJitter: false,
      shaderSwap: 'none',
      seed: 'big',
    });
    for (const chain of result) {
      expect(chain.slots.length).toBe(MAX_SHARED_SLOTS);
    }
  });
});
