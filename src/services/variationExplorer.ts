// ═══════════════════════════════════════════════════════════════════════════════
//  variationExplorer.ts
//  Pure logic for fanning out a multi-slot shader chain into N deterministic,
//  seedable variations for A/B comparison.
//
//  Reuses:
//    - randomizeParams logic from vjPresets (uniform sample + step snap + clamp)
//    - buildSharedChain / expandSharedChain / MAX_SHARED_SLOTS from layerChainShare
//    - buildCatalogDefaultsLookup from vjToSharedChain
//    - mapOrderedParamsToSlotParams from utils/shaderParamMapping
//    - shaderCatalog for same-category shader swaps
// ═══════════════════════════════════════════════════════════════════════════════

import { SlotParams, SlotMode } from '../renderer/types';
import { CatalogShader } from './shaderCatalog';
import {
  SharedChain,
  buildSharedChain,
  expandSharedChain,
  MAX_SHARED_SLOTS,
} from './layerChainShare';
import { buildCatalogDefaultsLookup } from './vjToSharedChain';
import { mapOrderedParamsToSlotParams } from '../utils/shaderParamMapping';

export interface VariationOptions {
  /** When true, each non-empty slot gets fresh randomized params (within catalog ranges). */
  paramJitter: boolean;
  /** Whether to swap shaders for same-category alternatives. */
  shaderSwap: 'none' | 'sameCategory';
  /** Optional seed for deterministic, reproducible variations. */
  seed?: string;
}

export interface ChainVariation {
  chain: SharedChain;
  /** Human-readable summary for UI thumbnails. */
  summary: VariationSummary;
}

export interface VariationSummarySlot {
  shaderId: string | null;
  params: Partial<SlotParams>;
}

export interface VariationSummary {
  slots: VariationSummarySlot[];
}

// ─── Deterministic PRNG ───────────────────────────────────────────────────────

function stringHash(str: string): number {
  let h1 = 0xdeadbeef;
  let h2 = 0x41c6ce57;
  for (let i = 0; i < str.length; i++) {
    const ch = str.charCodeAt(i);
    h1 = Math.imul(h1 ^ ch, 2654435761);
    h2 = Math.imul(h2 ^ ch, 1597334677);
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  return (h1 >>> 0) + (h2 >>> 0);
}

function mulberry32(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function createRng(seed?: string): () => number {
  if (seed === undefined || seed === '') {
    return Math.random;
  }
  return mulberry32(stringHash(seed));
}

// ─── Param randomization (mirrors vjPresets.randomizeParams) ──────────────────

function randomizeParamsWithRng(
  shaderIds: string[],
  catalog: CatalogShader[],
  rng: () => number
): Record<string, number>[] {
  const byId = new Map(catalog.map(s => [s.id, s]));
  return shaderIds.map(id => {
    const shader = byId.get(id);
    if (!shader) return {};

    const params: Record<string, number> = {};
    for (const param of shader.params) {
      const raw = rng() * (param.max - param.min) + param.min;
      if (param.step !== undefined && param.step > 0) {
        const steps = Math.round((raw - param.min) / param.step);
        let snapped = param.min + steps * param.step;
        snapped = Math.max(param.min, Math.min(param.max, snapped));
        params[param.id] = snapped;
      } else {
        params[param.id] = raw;
      }
    }
    return params;
  });
}

// ─── Same-category shader swap ────────────────────────────────────────────────

function pickSameCategoryShader(
  originalId: string,
  catalog: CatalogShader[],
  rng: () => number
): string {
  const original = catalog.find(s => s.id === originalId);
  if (!original) return originalId;

  const alternatives = catalog.filter(
    s => s.id !== originalId && s.category === original.category
  );
  if (alternatives.length === 0) return originalId;
  return alternatives[Math.floor(rng() * alternatives.length)].id;
}

// ─── Core variation generator ─────────────────────────────────────────────────

/**
 * Generate N deterministic, seedable variations of a base SharedChain.
 *
 * Rules:
 *  - Slot count is preserved (clamped to MAX_SHARED_SLOTS).
 *  - Blend modes (`enabled`, `mode`) are preserved.
 *  - `paramJitter` re-randomizes every non-empty slot's params within catalog ranges.
 *  - `shaderSwap: 'sameCategory'` swaps each non-empty shader for another shader
 *    in the same catalog category.
 *  - If a `seed` is provided, the same base chain + options always produce the
 *    same variations.
 */
export function generateChainVariations(
  baseChain: SharedChain,
  count: number,
  catalog: CatalogShader[],
  options: VariationOptions
): ChainVariation[] {
  if (!Number.isFinite(count) || count <= 0) return [];

  const baseSlots = (baseChain.slots || []).slice(0, MAX_SHARED_SLOTS);
  if (baseSlots.length === 0) return [];

  const defaultsLookup = buildCatalogDefaultsLookup(catalog);
  const { slotParams: baseParams } = expandSharedChain(
    { v: baseChain.v, slots: baseSlots },
    defaultsLookup
  );

  const byId = new Map(catalog.map(s => [s.id, s]));
  const variations: ChainVariation[] = [];

  for (let i = 0; i < count; i++) {
    const seed = options.seed !== undefined ? `${options.seed}:${i}` : undefined;
    const rng = createRng(seed);

    const slotModes: SlotMode[] = [];
    const enabled: boolean[] = [];
    const modes: Array<string | null> = [];
    const slotParams: SlotParams[] = [];

    for (let slotIndex = 0; slotIndex < baseSlots.length; slotIndex++) {
      const baseSlot = baseSlots[slotIndex];
      const originalId = baseSlot.shaderId;

      enabled.push(baseSlot.enabled !== false);
      slotModes.push(baseSlot.mode === 'parallel' ? 'parallel' : 'chained');

      let shaderId = originalId;
      if (options.shaderSwap === 'sameCategory' && originalId) {
        shaderId = pickSameCategoryShader(originalId, catalog, rng);
      }
      modes.push(shaderId);

      let params: SlotParams;
      if (shaderId && options.paramJitter) {
        const randomized = randomizeParamsWithRng([shaderId], catalog, rng)[0] || {};
        const orderedIds = (byId.get(shaderId)?.params || []).map(p => p.id);
        const mapped = mapOrderedParamsToSlotParams(randomized, orderedIds);
        params = { ...baseParams[slotIndex], ...mapped };
      } else {
        params = baseParams[slotIndex];
      }
      slotParams.push(params);
    }

    const chain = buildSharedChain(modes, slotParams, {
      enabled,
      slotModes,
      defaultsLookup,
    });

    const summary: VariationSummary = {
      slots: chain.slots.map((slot, idx) => ({
        shaderId: slot.shaderId,
        params: slot.params ?? {},
      })),
    };

    variations.push({ chain, summary });
  }

  return variations;
}

/**
 * Convenience helper: produce only the `SharedChain` payloads.
 */
export function generateChainVariationChains(
  baseChain: SharedChain,
  count: number,
  catalog: CatalogShader[],
  options: VariationOptions
): SharedChain[] {
  return generateChainVariations(baseChain, count, catalog, options).map(v => v.chain);
}
